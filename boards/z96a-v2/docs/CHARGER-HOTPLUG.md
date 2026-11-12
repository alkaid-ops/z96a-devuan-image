# Z96A 充电器热插拔兼容性（B 场景）— 分析与修复（0023）

日期：2026-11-13
状态：**补丁 + 编译验证 + 上机热插拔验证通过**（模块热加载，无需重启）
适用：`southchip,sc8886s` / BQ25703 兼容充电器（`bq257xx-charger` 驱动）

## 1. 现象（B 场景）

- U-Boot（主线/原厂）下，兼容性差的充电器 **100% 能启动充电**，不拔就稳定。
- Linux 启动后再插/重插该充电器：
  - `AC_STAT`（reg 0x20 bit15）在 1/0 之间来回跳
  - 充电电流寄存器被重复写入几十次
  - 最终 `AC_STAT` 稳定在 0，充电不再启动

## 2. 代码路径与根因

充电器 INT → `bq257xx_irq_handler_thread()` → `bq257xx_external_power_changed()`：

```c
bq257xx_get_state()               // online = AC_STAT
if (!online) goto notify;         // AC=0：只通知，不写寄存器
...
set_ichg(ichg_max);               // 每次 AC=1 重写 1A
set_iindpm(imax);                 // 每次 AC=1 重写 3A（DT 最大值）
set_vbatreg(vbat_max);
```

形成正反馈：

```
插入 → AC=1 → 写 iindpm=3A
     → 弱适配器被拉到超过其供电能力 → VBUS/VSYS 塌陷
     → AC=0 → 只 notify
     → 电源恢复 → AC=1 → 又写 3A → 再塌
     → 反复；最终适配器进入保护/锁死，AC 稳定 0
```

与 U-Boot 的关键差异：

| 项 | U-Boot | Linux |
|---|---|---|
| `IIN_HOST` (0x0E) | `0x1e00` = **1.55A** | `0x3b00` = **3.0A**（DT `input-current-limit-microamp`） |
| 充电电流 (0x02) | `0x0400` = 1.0A | `0x03c0` = 0.96A（基本一致） |
| `MIN_VSYS` (0x0C) | `0x1200` = 5.632V | `0x1500` = 6.4V（`voltage-min-design=6.6V`） |
| VINDPM (0x0A) | 未写 | 驱动从未配置 |
| 事件处理 | 一次初始化 | 每个 AC 边沿重写满参数 |

U-Boot 稳定的关键不是“握手协议”，而是 **1.55A 输入限流 + 只写一次**。弱适配器不会
被拉塌，因此“不拔就一直稳定”。

其他逻辑缺陷：
- 非 PD 源（`USB_TYPE_C`/`UNKNOWN`/纯 DC）也按 DT 最大 3A 执行；
  只有 PD 类型才会去取供应商的 `CURRENT_MAX`。
- AC 边沿无去抖、无退避；INT 同时用于充电状态变化，导致寄存器写入风暴。
- `AC_STAT=0` 分支不做状态复位；下一次 AC=1 立刻按 3A 重来。
- BQ25703 的 VINDPM（reg 0x0A）完全没有配置，失去输入电压调节保护。

## 3. 修复（`0023-z96a-charger-safe-input-current.patch`）

1. **非 PD 源使用保守输入限流 1.55A**：`imax = min(DT max, 1_550_000)`；
   只有 PD/PD_DRP/PD_PPS 且供应商给出有效 `CURRENT_MAX` 时才允许升到 DT 上限。
2. **AC 边沿去抖**：INT/`external_power_changed` 只调度 300ms 延迟工作，
   延迟工作里重新采样 `AC_STAT` 后再编程；避免在抖动中写硬件。
3. **去重写**：缓存已写入的 `iindpm`/`vbat`，值不变不写；
   `ichg` 因芯片在拔出时会清掉该寄存器，保留每次 AC=1 重写。
4. **写失败不更新缓存**，后续事件会重试。
5. **AC=0 时清理缓存**，不做任何升档；插入后重新按保守值起步。
6. probe 时的 `hw_init` 也使用保守限流，并在 300ms 后跑一次去抖工作
   （PD 源仍可升档）。

未改动：充电电流 1A、充电电压 8.4V、电池参数、DT `input-current-limit-microamp`
（仍作为上限，仅驱动策略改变）。

## 4. 验证状态

- 全序列 `0001..0024` 顺序应用：**零 reject**
- 驱动模块 `bq257xx_charger.ko`：编译 **0 error / 0 warning**，vermagic `7.2.12`
- **上机验证通过**（2026-11-13）：替换模块后 `modprobe -r bq257xx_charger`
  → `modprobe bq257xx_charger` 热加载，无需重启

实测（兼容性差的充电器，插入后 0s / +9s / +60s 三次采样）：

```
AC_STAT (0x20) = 0x8400   稳定，不再 1/0 来回跳
IIN_HOST(0x0e) = 0x1e00   1.55A（修复前 0x3b00 = 3A）
ichg    (0x02) = 0x03c0   960mA
status = Charging, online=1, current_now=960000
充电器 INT 计数 = 1（仅一次插入边沿，无中断风暴）
dmesg 无新的 "charger input recovery timed out"
```

注意：`CONFIG_CHARGER_BQ257XX=m`，所以镜像构建会重编该模块；本次验证是替换
`/lib/modules/7.2.12/.../bq257xx_charger.ko` 后热加载。

补充（重复热插拔实测）：`0012` 的 `RESET_VINDPM` 在 AC 边沿会把输入限流寄存器
重新加载为芯片默认值（读到 `0x4100` = 3.3A）。因此 0023 采用两阶段：边沿先
`RESET_VINDPM`，延迟 200ms 后再写入限制，最终 `IIN_HOST` 稳定为 `0x1e00`（1.55A）。

## 5. 上机验证方法

```bash
# 插入前
i2cget -f -y 0 0x6b 0x20 w      # AC_STAT
i2cget -f -y 0 0x6b 0x0e w      # 应为 0x1e00 (1.55A)，非 0x3b00 (3A)

# 开机后插入/重插，观察 1~2 分钟
i2cget -f -y 0 0x6b 0x20 w      # 应稳定 0x8400 一档，不来回跳
cat /sys/class/power_supply/bq257xx-charger/status   # Charging
dmesg | grep -i bq257
```

若稳定，再考虑后续优化（VINDPM reg 0x0A、MINVSYS 对齐 U-Boot `0x1200`）。
