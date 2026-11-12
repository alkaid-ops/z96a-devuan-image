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
