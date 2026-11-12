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

## 3. 开机动画（Plymouth Alkaid）

在 LOGO 交接方案之上，把「内核启动→登录页」这段用 Plymouth 动画覆盖。设计源是
Alkaid OS 的 SMIL SVG（`boards/z96a-v2/assets/alakid-boot.svg`），**设备端不安装任何 SVG/Chromium 运行时**。

### 3.1 管线

```
SVG(SMIL) --Chromium(setCurrentTime)--> 61 张 1080p PNG（0–6s @10fps）
          --索引色量化(256色)--> 13MB 帧序列
          --Plymouth script 主题(懒加载)--> DRM 全屏动画
```

- 主题：`files/rootfs-overlay/z96a-v2/usr/share/plymouth/themes/alkaid/`
  - `alkaid.plymouth` 必须包含 `[script]` 组（`ImageDir`/`ScriptFile`），否则
    脚本路径为 NULL，`plymouthd` 启动时崩溃
  - `alkaid.script`：只预加载第 0 帧，其余在 refresh 回调里逐帧解码；
    变量必须写 `global.idx` / `global.finished`（函数内直接赋值是局部变量，
    否则每帧重置、动画停在第一帧）
  - `logo-bgra.bin.gz` / `last-bgra.bin.gz`：给 framebuffer 补画用（见 3.3）
- `Plymouth.SetRefreshRate(10)`：按 10Hz 推进；索引色帧实测 **9.9 fps**、正片 **6.1s**

### 3.2 slim 集成（`custom.txt` 构建时打补丁）

`/etc/init.d/slim` 在启动 X 前：

1. 等 DRM card（`/dev/dri/by-path/platform-display-subsystem-card`）
2. `paint_fb logo-bgra.bin.gz` —— 把 U-Boot logo 画进 DRM fb（衔接 LOGO→动画）
3. `plymouthd --mode=boot` + `show-splash`，播放 `Z96A_ANIM_SECONDS`（默认 7s）
4. `plymouth quit` + `paint_fb last-bgra.bin.gz` —— 动画最后一帧撑到 X modeset
5. 启动 X

`/etc/slim.conf` 增加 `-novtswitch vt01`：X 留在当前 VT，不申请 VT 切换，避免
`plymouth quit --retain-splash` 留下的内核 VT 死锁（现象：X 卡在 `vt_event_wait`、
`chvt` 超时）。

### 3.3 关闭 framebuffer console（defconfig）

`# CONFIG_FRAMEBUFFER_CONSOLE is not set`。否则 fbcon 会在两处重绘 tty1 启动日志：
DRM 初始化绑定时、Plymouth 退出后。关闭后启动日志只进 dmesg/串口，屏幕不再出现
`Starting SMP IRQ Balancer` 之类的文字。

### 3.4 实测时间线（内核时间）

```
mount ~2.3s → DRM 12.5s → Plymouth 首帧 ~12.5s → 动画 6.1s
→ 最后一帧 → X 20s → 登录页
```

用户观感：`LOGO →（极短切换）→ Alkaid 动画 → 登录页`，无启动日志文字。
