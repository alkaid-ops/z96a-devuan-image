# Z96A 充电器热插拔兼容性（B 场景）— 分析与修复（0023）

日期：2026-11-13
状态：**根因修正 + 补丁 + 编译验证 + 真机验证通过（含自适应退避 B）**（模块热加载，无需重启）
适用：`southchip,sc8886s` / BQ25703 兼容充电器（`bq257xx-charger` 驱动）

## 1. 现象（B 场景）

- U-Boot（主线/原厂）下，兼容性差的充电器 **100% 能启动充电**，不拔就稳定。
- Linux 启动后再插/重插该充电器：
  - `AC_STAT`（reg 0x20 bit15）在 1/0 之间来回跳
  - 充电电流寄存器被重复写入几十次
  - 最终 `AC_STAT` 稳定在 0，充电不再启动
  - 旧模块日志：`charger input recovery timed out after 60 attempts`

## 2. 根因（经实测修正）

**不是输入限流 3A 把充电器拉塌。** 实测反证：只加 AC 去抖、限流保持芯片默认
（`IIN_HOST=0x4100` = 3.3A）时，该“兼容性差”充电器依然稳定充电
（`AC_STAT=0x8400`、`Charging`、`960mA`、IRQ 只有插入边沿）。

真正的问题是**事件处理风暴**：

- 充电器 INT 同时用于 AC 变化与充电状态变化，原驱动在每次中断都执行
  `RESET_VINDPM` + 重写 `ichg/iindpm/vbat`；
- `RESET_VINDPM` 会重启转换器并重新检测 VBUS，同时把输入限流寄存器重载为
  芯片默认值（`0x4100` = 3.3A）；
- “重启→检测→再写参数→再重启”的循环使 `AC_STAT` 来回跳，重试耗尽后锁死为 0。

因此正确修复是**收敛事件处理**，而不是降低限流。

## 3. 修复（`0023-z96a-charger-safe-input-current.patch`）

1. **AC 边沿 300ms 去抖**：INT 与 `external_power_changed` 只调度 delayed work，
   不直接在中断上下文写硬件；连续抖动会合并。
2. **两阶段写参数**：检测到 AC 边沿时先 `RESET_VINDPM`，作废缓存，并
   延迟 200ms 再跑一次工作；等芯片完成重新检测后，再写 `ichg/iindpm/vbat`，
   避免写入被 `RESET_VINDPM` 的默认值覆盖。
3. **去重写**：缓存 `iindpm`/`vbat`，值未变化不写；`ichg` 因芯片在拔出时
   会清掉该寄存器，保留每次 AC=1 重写（写失败不更新缓存，后续会重试）。
4. **AC=0 清理缓存**，不做任何编程；插入后重新走两阶段。
5. **自适应输入限流（B 方案）**：
   - 默认按 DT `input-current-limit-microamp`（3A）运行
   - 15s 窗口内检测到 ≥3 次 AC 边沿 → 限流降 0.5A
     （3A→2.5A→2A→1.5A→1A 下限）
   - 输入稳定 60s 后 → 每 60s 升回 0.5A，直到 DT 上限
   - 降/升档打印 `bq257xx: unstable input, backoff to ...` /
     `bq257xx: stable input, step-up to ...`
   - `iindpm_cur` 必须在 `parse_dt()` 之后初始化（否则会从 0 起步，
     实测曾把 3A 覆盖成 500mA）
   - PD/PD_DRP/PD_PPS 源仍可从供应商 `CURRENT_MAX` 取协商值（限制在 DT 上限内）

未改动：充电电流 1A、充电电压 8.4V、电池参数。

## 4. 验证

- 全序列 `0001..0024` 顺序应用：**零 reject**
- 驱动模块 `bq257xx_charger.ko`：编译 **0 error / 0 warning**，vermagic `7.2.12`
- **上机验证通过**：替换模块后
  `modprobe -r bq257xx_charger && modprobe bq257xx_charger` 热加载，无需重启

实测（兼容性差的充电器，插入后多次采样）：

```
AC_STAT (0x20) = 0x8400   稳定，无 1/0 振荡
IIN_HOST(0x0e) = 0x3b00   3.0A（DT 值；芯片重检测默认 0x4100=3.3A）
ichg    (0x02) = 0x03c0   960mA
status = Charging, online=1, current_now=960000
充电器 INT 计数在拔插时按边沿增长（不再出现中断风暴）
无新的 "charger input recovery timed out"
```

注意：`CONFIG_CHARGER_BQ257XX=m`，镜像构建会重编该模块；本次验证是替换
`/lib/modules/7.2.12/.../bq257xx_charger.ko` 后热加载。
重复热插拔实测（第二次，最终 A 版本）：插入后 `0s / +2s / +10s / +30s` 四次采样：

```
AC_STAT (0x20) = 0x8400   全程稳定
IIN_HOST(0x0e) = 0x3b00   稳定为 DT 的 3.0A（印证 RESET_VINDPM 默认值 0x4100
                          已被 200ms 后的第二阶段覆盖）
ichg    (0x02) = 0x03c0   960mA
status = Charging, online=1, current_now=960000
IRQ 计数 = 5（只有插拔边沿，无中断风暴）
dmesg 无新的 recovery/超时记录
```

因此结论：**根因是 AC 边沿事件处理风暴，不是 3A 限流拉塌**；
去抖 + 两阶段 + 去重写即可稳定，同时保留正常 3A 充电能力。

自适应退避（B）真机实测（2026-11-13）：

```
两次拔插（10s 内）：
  bq257xx: unstable input, backoff to 2500 mA
  IIN_HOST = 0x3100 (2.5A), AC_STAT=0x8400 稳定, Charging

稳定 60s 后：
  bq257xx: stable input, step-up to 3000 mA
  IIN_HOST = 0x3b00 (3A), AC_STAT=0x8400 稳定, Charging
```

（早期日志里的 500mA/1000mA 两条来自初始化顺序 bug 的旧模块，修复后不再出现。）

## 5. 上机复测方法

```bash
i2cget -f -y 0 0x6b 0x20 w   # 插入后应稳定 0x8400
i2cget -f -y 0 0x6b 0x0e w   # 插入稳定后应为 0x3b00（3A）
cat /sys/class/power_supply/bq257xx-charger/status   # Charging
```

## 6. 后续可选

- VINDPM（reg 0x0A）目前仍未配置，可作为下一层输入电压保护。
- 自适应退避的档位/窗口/稳定时间如在实际适配器上不合适，可再调参
  （`BQ257XX_IINDPM_STEP_UA`、`AC_WINDOW_MS`、`AC_STABLE_MS`）。
