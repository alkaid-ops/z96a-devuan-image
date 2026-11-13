# Z96A 启动 LOGO 交接与启动优化（镜像侧）

本文记录「B 方案：LOGO 一直显示到桌面」在镜像中的落点。**U-Boot 侧未做任何改动**
（内核侧已覆盖交接行为；未来若刷入去掉 `DM_FLAG_OS_PREPARE` 的 U-Boot，
`z96a_handback` 会自动变为 no-op）。

## 1. 根因

U-Boot 的 `bootm` 交接路径会调用 `dm_remove_devices_active()`：

```
arch/arm/lib/bootm.c                  dm_remove_devices_active()
drivers/video/rockchip/rk3568_vop.c   .flags = DM_FLAG_OS_PREPARE
                                      -> rk3568_vop_remove() -> rk_vop2_disable()
```

`rk_vop2_disable()` 把 **eDP 实际输出通道 VP1 的 POST `DSP_CTRL` bit31（STANDBY）置 1**，
屏幕黑掉；但 VOP 图层与 eDP 视频流仍然在跑。实测寄存器：

```
dsp_en = 0x00004008      eDP interface mux = port 1
esmart0_mst = 0x00000001 图层仍在扫描，yrgb = 0x1f800000
post1_ctrl = 0x80000000 STANDBY = 1（输出被关）
edp VIDEO_EN = 1
```

关键细节：`REG_CFG_DONE` 的正确锁存位是 `bit15 | bit[port] | bit[port+16]`
（见 U-Boot `rkvop2_cfg_regdone()`），只写 bit0 不生效。

## 2. 内核侧修复（补丁 0018 / 0019）

`drivers/soc/rockchip/z96a_handback.c`（`subsys_initcall`，内核约 0.12s）：

1. 守卫：PMU `vo` 域打开且 VOP 时钟门控为运行态才访问 VOP（避免 RK3568 总线挂死）
2. 从 `dsp_en` 解出 eDP mux 端口
3. 对 VP0/1/2 清 STANDBY，并按正确 regdone 位锁存
4. 图层未扫描时完全 no-op（USB 冷启动/无 LOGO 路径不受影响）

同时（0018）：

- `drivers/soc/rockchip/z96a_gpio0_ungate.c`：gpio-leds 探测前预开 PMU GPIO0 门控
- `drivers/pmdomain/rockchip/pm-domains.c`：`vo` 域 `GENPD_FLAG_ALWAYS_ON`

DT（0019）：

- `&vop_mmu` 关闭（避免交接时 Linux 接管 VOP IOMMU 的旧隐患；
  `rockchip_drm_init_iommu()` 无 IOMMU 时返回 0，DRM 退回物理 DMA + CMA）
- 去掉 LED 的三处 `linux,default-trigger`（trigger 由用户态 `z96a-charge-led` 设置）。
  否则 `devm_led_classdev_register_ext()` 会等待尚未注册的 trigger 而阻塞约 5.66s。

> SDIO 1.8V/CMD11：0014 在已处于 1.8V 时跳过 CMD11，UHS 初始化失败会回退
> high-speed；0015 把 `vccio_sd` 固定为 1.8V，并**在 0002 之后**重新加回
> `sd-uhs-sdr104` / `max-frequency = <200000000>`（原 0015 的第二段因 0002
> 改写节点而 apply 失败，已按新基线重写）。
> 注意：`vccio_sd` 同时是 `vccio3-supply`（SD 卡槽 IO），1.8V 对 3.3V SD 卡有影响。

## 3. 设备/镜像侧修复

- **硬件 RNG 内建**：`defconfig` 中 `CONFIG_HW_RANDOM=y`、`CONFIG_HW_RANDOM_ROCKCHIP=y`。
  原先 RNG 是模块，`udevd` 启动时 `getrandom()` 被熵阻塞约 6s；内建后
  `crng init` 从 9.79s 降到 0.23s。
- **U-Boot logo 来自 boot 分区**：U-Boot 用 `load mmc 0:1 … z96a-logo.bin.gz` 读取
  `z96a-logo.bin.gz`（1920×1080 BGRA，gzip）。镜像构建时由 `lib/function/staging`
  的 `extlinux()` 把 `usr/share/plymouth/themes/alkaid/logo-bgra.bin.gz` 复制为
  `p1/z96a-logo.bin.gz`（单一来源，两者字节相同）。**缺少该文件时 eMMC/USB 启动都会白屏**
  （2026-11-13 复现：CI 镜像漏带此文件，eMMC 启动白屏；手工补进 boot 分区后恢复）。
- **不使用 initramfs**：`lib/function/staging` 对 `z96a-v2` 注释掉 `initrd` 行；
  `usb-storage/scsi/block/ext4` 均内建，内核可自行解析 `root=PARTUUID`。
  实测（2026-11-12）：无 initrd + `root=PARTUUID=…` 正常启动，内核解析为 `/dev/sda2`，`/run/initramfs` 不存在。
- **DRM 延后到 X 启动前**：`usr/lib/modprobe.d/z96a-defer-drm.conf` 黑名单挡住 udev 的
  modalias 自动加载；`/etc/init.d/slim` 在启动 X 前显式 `modprobe panel_edp; modprobe rockchipdrm`；
  另有 `z96a-drm-guard`（S02）90 秒兜底。
- **其它**：MTP `mtp-probe` 补齐、`ntpsec` init 权限/启动链接、`haveged` 停用、
  locale 从 `/etc/environment` 移到 `/etc/default/locale`。

上述运行时改动由 `custom.txt` 的 `user_function()`（仅 `BOARD=z96a-v2`）在镜像内执行。

## 4. 验证

```bash
dmesg | grep -E 'Z96HB|crng init done'          # handback 生效、熵池早完成
dmesg | grep -c 'CMD11|Timeout sending command' # SDIO 不应报错（见 0014/0015）
ls /sys/class/leds/                             # white:power / red:charging / green:charging
dmesg | grep 'Initialized rockchip'              # DRM 在 X 前才初始化
```

目标里程碑（内核时间）：`fbcon ~2.2s`、`rockchipdrm ~11s`、`Xorg ~12.5s`。实测（2026-11-12，方案 A）：`mmc1: new UHS-I speed SDR104 SDIO card`，
Bus speed `200000000Hz`，CMD11 不再超时，WiFi 正常连接。`vccio_sd` 同时供
vccio3（SD 卡槽 IO），固定 1.8V 对 3.3V SD 卡有影响，需按实际卡型确认。


交接期间 LOGO 保持，DRM 接管瞬间闪黑约 1s，随后登录界面。

## 5. 已知无害残留

- `rockchip-naneng-combphy fe830000: wait phy status ready timeout`：该 combphy 是
  USB3 host 的 usb3-phy，禁用会丢 U 盘根设备，保留。
- `EVIOCSKEYCODE ... Invalid argument`：USB 键盘不支持运行期键码重映射。
- `simple-amplifier: supply VCC not found, using dummy regulator`：功放供电用 dummy 兜底。

## 3. 开机动画（Plymouth Alkaid，initramfs 早期启动）

设计源是 Alkaid OS 的 SMIL SVG（`boards/z96a-v2/assets/alakid-boot.svg`）。
设备端不安装任何 SVG/Chromium 运行时：开发机把 SVG 预渲染成 PNG 帧，设备只读帧序列。

### 3.1 帧序列与主题

```
SVG(SMIL) --Chromium(setCurrentTime)--> 120 张 1080p PNG
          --256 色索引量化--> 26MB 帧序列
          --Plymouth script 主题(懒加载)--> DRM 全屏动画
```

时间结构（`RefreshRate=10`，实测 ~9.9 fps）：

| 帧区间 | 内容 |
|---|---|
| `f0000..f0060` | 原正片 0–6.0s（星空/地球/星座/字标） |
| `f0061..f0119` | SVG 的持续段 6.1–11.9s（地球自转 + 星点闪烁） |
| 循环回 `f0080` | 8.0–11.9s 无缝循环段（接缝平均差 ~1.8/255） |

主题位于 `boards/z96a-v2/chroot-files/theme/alkaid/`：

- `alkaid.plymouth` 必须包含 `[script]` 组（`ImageDir`/`ScriptFile`），否则脚本路径为
  NULL，`plymouthd` 启动时崩溃
- `alkaid.script` 只预加载第 0 帧，其余在 refresh 回调里逐帧解码；变量必须写
  `global.idx` / `global.finished`（函数内直接赋值是局部变量，否则每帧重置、动画停在第一帧）
- `logo-bgra.bin.gz` / `last-bgra.bin.gz` 供 slim 往 framebuffer 补画

### 3.2 initramfs 集成（动画在 root 挂载前开始）

`boards/z96a-v2/chroot-files/` 由 `scripts/stage1` 复制到 `${P_VALUE}/root/z96a-chroot-files`，
`custom.txt` 在 chroot 内把它安装到：

| 文件 | 作用 |
|---|---|
| `/etc/initramfs-tools/hooks/z96a-plymouth` | 拷贝 `plymouthd`、插件、DRM renderer、主题、`plymouthd.conf`；保留 `logo-bgra.bin.gz`（initramfs 补画用）；并删除 initrd 里的 `blacklist rockchipdrm` |
| `/usr/share/initramfs-tools/scripts/init-premount/plymouth` | 覆盖 stock 脚本：等 `/dev/fb0` → 补画 LOGO → 启动 plymouthd → `--show-splash` |
| `/etc/initramfs-tools/modules` | `panel-edp`、`analogix_dp`、`rockchipdrm`（DRM 在 initramfs 就 probe） |
| `/etc/initramfs-tools/initramfs.conf` | `MODULES=list`（USB/ext4/xhci 都是内建，不需要额外模块） |
| `/etc/plymouth/plymouthd.conf` | `[Daemon] Theme=alkaid`（坏配置会静默回退 text 插件） |
| `/usr/share/plymouth/themes/alkaid` | 运行期主题（slim 也用它补画） |

安装时机在 **kernel 包安装之前**，因此 kernel postinst 触发的 `update-initramfs` 会把
Plymouth 与主题打进 initrd。`lib/function/staging` 为 z96a-v2 启用 extlinux
`initrd ../uInitrd` 并在 cmdline 加入 `splash`。

**premount 覆盖脚本的要点**（踩过的坑）：

- 等 **`/dev/fb0`（devtmpfs 节点，DRM 注册即出现）**，而不是 udev 的
  `/dev/dri/by-path/...` 软链——后者在 initramfs 里受 udev 冷插拔排队影响，可能晚
  ~4.7 s 才出现，旧版等待循环因此把 root 挂载拖到 ~13 s
- DRM modeset 会清掉 scanout 缓冲，先用 `logo-bgra.bin.gz` 补画回 LOGO，动画开始前
  不露黑
- plymouthd 本身启动很快（~0.02 s 返回），无需额外环境变量

### 3.3 slim 交接

`/etc/init.d/slim` 在启动 X 前：

1. 等 DRM card（`/dev/dri/by-path/platform-display-subsystem-card`）
2. `paint_fb logo-bgra.bin.gz`（无 initrd 时的兜底衔接）
3. `plymouth --ping`：若 initramfs 已启动则不再启动第二个 `plymouthd`；否则本地启动
4. 保持 `Z96A_ANIM_SECONDS`（默认 2s）后 `plymouth quit`
5. 等 `plymouthd` 真正退出（`plymouth --ping` 为假，最多 5 s）+ 0.3 s 余量
6. `paint_fb last-bgra.bin.gz`，然后启动 X

**X 使用自己的 VT（vt7）**：`/etc/slim.conf` 不再带 `-novtswitch vt01`。实测
（2026-11-13，.84）让 X 留在 plymouth 的 VT 时，**第一个** X 会继承 splash 的 VT/KMS
状态：22.8 s 时初始化已全部完成，却一直不向 SLiM 发 `SIGUSR1`，slim.log 出现
`WaitForServer: Not seen SigUSR1 from Xserver`，约 130 s 后 SLiM 杀掉 X 重试，第二次
才显示登录页（观感：动画后长时间黑屏）。改为切到 vt7 后首个 X 在 ≈20.6 s 启动并稳定。

### 3.4 无控制台文字

`defconfig` 关闭 `CONFIG_FRAMEBUFFER_CONSOLE`：fbcon 不再在 DRM 初始化 / Plymouth
退出时重绘 tty1 的启动日志；日志只进 dmesg/串口。

### 3.5 实测（2026-11-13，.84，重新打包镜像 + 本节全部修复）

```
DRM 初始化 7.5s → LOGO 补画 7.9s → 动画上屏 8.2s → root mount 8.6s
→ rc → slim → X(vt7) ~32s → 登录页（背景 = 动画最后一帧）
```

`/run/initramfs/z96a-anim.log`（premount 覆盖脚本写入）：

```
Z96A 7.75 entry
Z96A 7.90 card-ready logo-painted
Z96A 7.90 daemon-start
Z96A 7.91 daemon-returned
Z96A 8.18 splash-shown
```

用户观感：LOGO 保持到 DRM 接管（~0.3 s 内补画回来），随后 Alkaid 动画连续播放
（正片 + 持续段 + 无缝循环），最后直接进入带同一帧背景的登录页；无控制台文字、
无长黑屏。
