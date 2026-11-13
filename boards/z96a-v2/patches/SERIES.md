# 补丁序列说明

本目录记录 **z96a-v2 自有补丁**，与上游分支补丁区分。

## 分类

| 类别 | 位置 | 维护方式 |
|---|---|---|
| 上游分支补丁 | `patches/git/z96a-v2/linux-add_sunniwell_z96a/` | 由上游 `yjun123/linux` 分支提供，构建时按目录顺序 apply；只记录来源 commit，不逐条维护 |
| 芯片家族补丁 | `patches/rockchip/` | 按内核版本目录（`6.12`/`6.18`/`6.19`）存放 |
| U-Boot 补丁 | `patches/uboot/v2026.01/` | 按 U-Boot 版本存放 |
| 包补丁（非内核） | `boards/z96a-v2/patches/{slim,video}/` | 构建 deb / libva 时使用 |

## 上游分支补丁清单

目录：`patches/git/z96a-v2/linux-add_sunniwell_z96a/`

| 文件 | 用途 |
|---|---|
| `0001-edp-phy-enable-pclk.patch` | eDP PHY PCLK 使能 |
| `0002-z96a-board-dts.patch` | Z96A 板级 DTS 汇总：电源/LED/摄像头/WiFi SDIO/RK809 MIC/HDMI mclk/VOP MMU/eMMC HS400ES/电池/CPU idle/OPP/NTC/eDP 时钟 |
| `0003-mmc-pwrseq-simple-fix-reset-gpio.patch` | MMC pwrseq reset GPIO 修复 |
| `0004-panel-edp-add-boe-nv140fhm-n43.patch` | BOE NV140FHM-N43 面板 |
| `0005-rkvdec-rk3568-dt-bindings.patch` | rkvdec DT bindings |
| `0006-rkvdec-rk3568-vdpu346.patch` | rkvdec VDPU346 |
| `0007-rkvdec-rk3568-dts.patch` | rkvdec DTS |
| `0008-rk3568-edp-140240000.patch` | eDP 140.24MHz（仅 clk，DTS 部分并入 0002） |
| `0011-z96a-es7202-6ch.patch` | ES7202 原生 6ch 采集（仅 codec，DTS 部分并入 0002） |
| `0012-bq257xx-input-reset.patch` | BQ257xx 输入状态复位/恢复 |
| `0014-z96a-sdio-uhs-cmd11.patch` | SDIO 1.8V 时跳过 CMD11，UHS 失败回退 high-speed |
| `0018-z96a-vop-handback-and-boot-fixes.patch` | 交接保留 LOGO（VP1 POST standby 清除 + 正确 regdone）、GPIO0 门控预开、VO genpd 常开 |
| `0021-z96a-rk809-2s-gauge.patch` | mainline `rk817_charger` 增加 RK809/2S 校准、分压、状态 |
| `0023-z96a-charger-safe-input-current.patch` | 兼容差充电器：非 PD 输入限流保守化 + AC 边沿去抖/去重写 |
| `0024-z96a-rk809-battery-present.patch` | RK809 `BAT_EXS` 不可靠，强制 battery_present（满电校准） |
| `0025-z96a-rk817-charge-led-events.patch` | RK817 充电 LED 按 capacity/status 变化发事件 |
| `0028-z96a-charger-ntc-guard.patch` | 充电器 NTC 保护门控 |
| `0030-z96a-sdhci-dwcmshc-diag.patch` | DWCMSHC 首次写错误诊断（模块参数默认关闭） |
| `0031-rk3568-hs400-txclk-tap-08.patch` | RK3568 rev0 HS400/HS400ES TXCLK tap 固定 0x8 |

原先分散在 0002/0009/0013/0015/0016/0017/0019/0020/0022/0026/0027/0029/0032 的板级 DTS 改动已合并为 `0002-z96a-board-dts.patch`；`.old` 与 `remote-head/` 中间产物已清理。

## 规则

- 新增本地补丁：放到对应目录，按序号递增命名，并在上表补一行用途。
- 补丁的来源 commit 记录在 `manifest.json`（`kernel.pinned_commit`）。
- 不要修改上游分支补丁的顺序或内容；需要改动时新建本地补丁。
- 包补丁与内核补丁分开，便于独立升级。
