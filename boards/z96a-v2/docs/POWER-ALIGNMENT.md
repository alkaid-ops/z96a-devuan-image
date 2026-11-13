# 原厂电源/频率对齐路线

更新：2026-11-13。参考原厂 DTS `rea-z97a/docs/ANDROID-archive-rk-kernel.dts`
和当前 `.84` 实测（Devuan 6 / 内核 7.2.12 / eudev 3.2.14）。

## 状态总表

| 项目 | 原厂 | 当前 `.84` | 状态 | 说明 |
|---|---|---|---|---|
| CPU governor | 有完整 OPP/PVTM，运行时动态 | `performance`，4 核固定 1992 MHz | ✅ 已改仓库，真机已切 `schedutil` | 空闲可降频，满载仍到 1992 MHz |
| CPU idle states | `cpu-sleep` PSCI `0x10000`，100/120us，1ms | 已注册 `state0=WFI`、`state1=cpu-sleep` | ✅ 2026-11-13 重启验证 | `0026` 已生效，cpuidle usage 持续增长 |
| GPU 变频 | `power-model`、`upthreshold` | `simple_ondemand` 200–800 MHz | ✅ 已动态，无需改 | 原厂 power-model 仅热估算差异 |
| CPU OPP PVTM/leakage | `pvtm-voltage-sel`、nvmem leakage/pvtm/mbist | 固定 nominal 电压；已把 1416/1608MHz nominal 对齐原厂 1.0/1.075V | 🟡 部分 | 补丁 `0027` 已落 nominal 电压；PVTM 逐片选压仍需内核驱动 |
| GPU OPP | 600MHz 875mV nominal | 600MHz 900mV | ✅ 补丁 `0027` 已对齐 875mV | 仅 nominal；无 GPU PVTM |
| 热策略 | `sustainable-power=905`、75/85/115°C、cooling-map contribution | `step_wise`、70/75/95°C | 🟡 部分差异 | 当前无 `power_allocator`；当前温度 ~33°C，不紧急 |
| deep suspend | 原厂完整 | `mem_sleep=deep`，自动挂起关闭，手动挂起有 P0 唤醒缺陷 | ❌ 待修 | 最大省电项；需先解决唤醒，不能盲开 |
| NPU | `npu@fde40000` + OPP + supply | DTB 无节点、无驱动 | ❌ 缺驱动 | 需 RKNPU 驱动移植，工作量大 |
| VENC/JPEG/IEP/RGA | `rkvenc`/`jpegd`/`iep`/`rk_rga` | `rkvdec`/`hantro_vpu`/`rga`/`v4l2_jpeg` | 🟡 部分 | 无 `rkvenc`/`iep` vendor 路径，按需补 |
| SFC/SPI NOR | `sfc@fe300000` okay | disabled | 🟡 待确认硬件 | 需确认板上 SPI NOR 用途，不盲开 |
| SPDIF/SATA1 | 原厂有节点 | 当前节点存在但未验证 | 🟡 待确认 | 与 eDP/外部接口相关，按需 |
| Type-C PD | `switch-ctl-gpios`、PDO `0x40190c8` | `gpio-sbu-mux` 已用同一 GPIO4_D2；PDO `0x220190c8` | ✅ switch 已对齐 | vendor switch 与当前 `usb-switch` 同一引脚；PDO 保留 DUAL_ROLE+DATA_SWAP，避免破坏 source/OTG |
| SC8886 NTC | NTC 表 + io-channels + 输入限流 | 0023 输入回退 + `battery-thermal`；0028 新增 0/43°C 充电抑制 | ✅ 已实现/真机验证 | 5s 轮询，REG00 CHRG_INHIBIT；20°C 强制截止测试通过 |
| 背光曲线 | 0–255 原始曲线 | 20–220 + 200 级插值 | 🟡 有意差异 | 当前曲线为低亮度稳定调过，暂不改 |
| U-Boot | A SPL + P1 FIT / DDR 1560 | B 版 / DDR 1184 | ⏸ 按用户要求不动 | 不碰引导区 |

## 已落地

- `files/rootfs-overlay/z96a-v2/etc/default/governor`
  - `GOVERNOR="schedutil"`；重启后 `S02governor` 自动应用。
  - 真机已安装并执行 `governor -r`：空闲 1.6–1.8 GHz，4 核满载 1992 MHz。
- `patches/git/z96a-v2/linux-add_sunniwell_z96a/0002-z96a-board-dts.patch`
  - 给 4 个 CPU 加 `cpu-idle-states = <&cpu_sleep>`；
  - 增加原厂 `cpu-sleep`（PSCI `0x10000`，100/120us，1ms residency）；
  - CPU 1416MHz nominal 1.025V → 1.0V、1608MHz 1.1V → 1.075V；
  - GPU 600MHz nominal 0.9V → 0.875V；
  - 仅 nominal 电压对齐，逐片 PVTM 选压仍未实现；已编译验证；
  - **需重启后验证 `/sys/devices/system/cpu/cpu0/cpuidle` 出现**。

## 真机验证（2026-11-13 重启后）

替换 DTB（基于当时 live DTB，仅加 idle-states + OPP nominal 电压）并重启后：

```text
/etc/default/governor: GOVERNOR="schedutil"
scaling_governor: schedutil

cpuidle:
  state0 name=WFI
  state1 name=cpu-sleep
  state1 usage 持续增长

rk817-battery: present=1, capacity=100
bq257xx-charger: online=1
green:charging=1, red:charging=0
```

满电静置 20 秒没有 `rk817-battery` 的 8 秒周期性 uevent；没有常驻
`z96a-charge-led` 进程。DTB 备份：
`/boot/rockchip/rk3568-sunniwell-z96a-typec.dtb.pre-power-align-20261113`。

### 充电 NTC / Type-C 验证（同日，未重启）

- `bq257xx-charger` 新模块加载后打印
  `NTC guard: 0..43 C, poll 5000 ms`；
- 用 `test_high_temp_c=20` 强制低截止，当前 20.2°C 触发：
  `battery 20166 mC, charging inhibited`，`status=Not charging`、
  `current=0`；
- 恢复 `test_high_temp_c=-1` 后：
  `battery 20277 mC, charging enabled`，`status=Charging`；
- Type-C：`usb-switch/gpio-sbu-mux` 使用与 vendor `switch-ctl-gpios`
  相同的 GPIO4_D2；`port_type=dual`、`data_role=host`、
  `power_role=source`，USB3 5Gbps 正常。PDO 保留
  `DUAL_ROLE|DATA_SWAP`，不改成 vendor 的 `USB_COMM` 单标志。

## 需要独立驱动的项

这些不能只改 DTS，必须移植/实现内核支持，建议单独立项：

1. **CPU PVTM/leakage 选压**：原厂 `rockchip,pvtm-voltage-sel`、`nvmem-cells`；当前内核没有对应驱动，补 DTS 无效。
2. **NPU**：原厂 `rockchip,rk3568-rknpu`；当前无驱动、无节点。
3. **VENC/IEP/JPEG**：原厂独立 `rkvenc`/`iep`/`jpegd`；当前只有部分 hantro/rkvdec 路径。
4. **deep suspend 唤醒**：属于 P0 稳定性问题，需串口/`no_console_suspend` 抓完整 suspend/resume 日志。

## 需要确认硬件后再动

- SFC/SPI NOR：确认板上是否有独立 NOR、是否被 EC/恢复流程使用。
- SPDIF/SATA1：确认外部接口/连接器是否实际存在。
- 背光曲线：当前 20–220 + 插值是针对低亮度稳定性调过的，不建议为“数字对齐”回退。
- U-Boot：按用户要求保持现状，不碰 eMMC 引导区。

## 验证清单

1. 重启后：
   - `cat /sys/devices/system/cpu/cpu0/cpuidle/state0/name` 应出现；
   - `cat /sys/class/thermal/thermal_zone0/temp` 正常；
   - `cat /sys/class/leds/green:charging/brightness` 仍按 90% 策略。
2. 空闲/满载各 10 秒采样 `scaling_cur_freq`，确认 `schedutil` 降频、满载升到 1992。
3. `udevadm monitor --subsystem-match=power_supply` 确认充电事件仍正常。
4. 挂起测试前先确认可接受“无法唤醒”风险；修复前不要启用自动挂起。
