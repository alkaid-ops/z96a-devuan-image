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
| `0002-z96a-sdmmc1-remote-head.patch` | SDMMC1 指向 remote-head 分支 |
| `0003-mmc-pwrseq-simple-fix-reset-gpio.patch` | MMC pwrseq reset GPIO 修复 |
| `0004-panel-edp-add-boe-nv140fhm-n43.patch` | BOE NV140FHM-N43 面板 |
| `0005-rkvdec-rk3568-dt-bindings.patch` | rkvdec DT bindings |
| `0006-rkvdec-rk3568-vdpu346.patch` | rkvdec VDPU346 |
| `0007-rkvdec-rk3568-dts.patch` | rkvdec DTS |
| `0008-rk3568-edp-140240000.patch` | eDP 140.24MHz |
| `0009-z96a-camera-power.patch` | 摄像头 `vcc_camera` 常开 |
| `0011-z96a-es7202-6ch.patch` | ES7202 原生 6ch 采集 |
| `0012-bq257xx-input-reset.patch` | BQ257xx 输入状态复位/恢复 |
| `0013-z96a-led-system-indicator.patch` | 电源灯改为系统运行指示 |
| `0014-z96a-sdio-uhs-cmd11.patch` | SDIO 1.8V 时跳过 CMD11，UHS 失败回退 high-speed |
| `0015-z96a-wifi-sdr104-1v8.patch` | WiFi SDIO 固定 1.8V、200MHz SDR104 |

`.old` 后缀和 `remote-head/` 是 rebase 过程的中间产物，稳定后清理（见 `docs/TODO.md`）。

## 规则

- 新增本地补丁：放到对应目录，按序号递增命名，并在上表补一行用途。
- 补丁的来源 commit 记录在 `manifest.json`（`kernel.pinned_commit`）。
- 不要修改上游分支补丁的顺序或内容；需要改动时新建本地补丁。
- 包补丁与内核补丁分开，便于独立升级。
