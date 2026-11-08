# Z96A 硬件驱动状态

更新时间：2026-11-08

测试环境：Sunniwell Z96A Type-C，Devuan Excalibur，内核 `7.2.12`，设备 `192.168.31.84`。

状态说明：

- ✅ 驱动已加载并实际验证
- 🟡 驱动在位，但未做完整物理验证，或功能按设计只部分可用
- ❌ 缺失/未实现
- N/A 不需要 Linux 驱动，或按用户要求不处理

## 规格表硬件

| README 项目 | 实际驱动/节点 | 状态 |
|---|---|---|
| 型号、主板 PCB、USB 小板、尺寸 | 无 Linux 驱动概念 | N/A |
| SoC RK3568B2 | 4×Cortex-A55、`panfrost`、`rockchip_vdec`、`hantro_vpu`、`rga` | ✅ |
| PMIC RK809-5 | `rk8xx-i2c`、`rk808` regulator、`rk808-rtc`、`snd_soc_rk817` | ✅ |
| DRAM 4GB LPDDR4X | `MemTotal 4015956kB`；TPL/U-Boot 初始化 | N/A（可用） |
| eMMC 32GB SiliconGo | `mmc0` 29.1GiB；冷启动内核日志确认 `mmc0: new HS400 MMC card` | ✅（HS400） |
| WiFi RTL8822CS | `rtw88_8822cs`，`wlan0` up，`disable_lps_deep=y` | ✅ |
| 蓝牙 RTL8822CS | `hci_uart`+`btrtl`，`hci0` UP | ✅ |
| 显示屏 BOE NV140FHD-N43 | `panel-edp`+`analogix_dp`+`phy_rockchip_naneng_edp`+VOP；1920x1080，背光正常 | ✅ |
| 键盘 SH61F83Q | `usbhid`，输入设备正常 | ✅ |
| 触控板 CST128-A | `usbhid`，鼠标输入设备正常 | ✅ |
| USB Hub GL852G | `usbcore` generic hub，4-port | ✅ |
| 摄像头 Microdia `0c45:6368` | `uvcvideo`；DT 增加 `vcc_camera`（GPIO2_D0）。冷启动确认该稳压器已使能、GPIO2_D0 由 `regulator-vcc-camera` 持有并输出；本次启动 USB 总线未出现该摄像头 | 🟡（驱动/供电就绪，摄像头当前未接入） |
| Type-C 控制器 HUSB311 | `tcpci_rt1711h`，`port0` host/source | ✅（OTG device 模式不处理） |
| USB 3.1 切换开关 D3EB | `gpio_sbu_mux` 绑定 `usb-switch` | ✅ |
| 充电芯片 SC8886 | `bq257xx-charger`，充电状态正常 | ✅ |
| 电池 SHT 3585130-2S | `bq257xx-fgu`，容量/电压；`battery-thermal` 温度 | ✅（见下文） |
| 霍尔开关 MH248 | `gpio-keys-hall`，`event0` | ✅ |
| 音频 ADC 3×ES7202 | i2c `0x30/31/32` 全部绑定 `es7202`；PDM SDI1/2/3 三条线启用，`z96a_mic` 可原生录 6ch（2ch/4ch/6ch 均可） | ✅（见下文通道角色） |
| 音频功放 AW8737AFCR | `simple-amplifier`，播放时 GPIO3_A6 正常使能 | ✅ |
| 扬声器 2×BER-NM14G-R | 功放/RK817 输出正常 | N/A（用户确认正常，不再处理） |
| DC-DC TCS4525 | `fan53555`，`vdd_cpu 1150mV` | ✅ |
| N MOSFET VS3652DB | 分立器件，无 Linux 驱动 | N/A |
| P MOSFET NCE30P20Q | 分立器件，无 Linux 驱动 | N/A |
| 电池保护板/接口 | NTC 使用 SARADC ch4；ID 电阻 ch5 未使用 | N/A |

## 接口与指示灯

| README 项目 | 实际状态 | 状态 |
|---|---|---|
| 电源 Type-C | `bq257xx` + `HUSB311`，充电正常 | ✅ |
| USB 2.0 Type-A ×2 | EHCI + GL852G Hub；外口不处理 | N/A（按用户要求） |
| USB 3.0 Type-A ×1 | xHCI，SanDisk 5Gbps 设备实测正常 | ✅ |
| USB 3.1 Type-C OTG ×1 | `dwc3` + role switch，OTG device 模式不处理 | N/A（按用户要求） |
| HDMI 2.0 ×1 | `dwhdmi-rockchip` 已绑定；不处理 | N/A（按用户要求） |
| 3.5mm 耳机孔 | RK817 codec + jack 检测；不处理 | N/A（按用户要求） |
| 模拟麦克风 ×2 | ES7202 PDM，`z96a_mic` 6ch 原生采集；ch0/1 为房间麦克风（0x30），ch2/3 为 AEC 参考（0x31），ch4/5 为耳机/回环（0x32） | ✅（不是 6 麦阵列） |
| 扬声器 ×2 | 功放使能正常 | N/A（用户确认正常） |
| 电源 LED | `white:power`，`bq257xx-charger-online` | ✅ |
| 大写锁定 LED | `input1::capslock`，`kbd-capslock` | ✅ |
| 麦克风静音 LED | 无 LED 节点；键盘 HID 只有 num/caps/scroll 三路 LED | ❌ 阻塞 |
| 充电中 LED | `red:charging`，由 `z96a-charge-led` 控制：AC 接通且电量 < 90% 时亮红灯 | ✅ |
| 已充满 LED | `green:charging`，由 `z96a-charge-led` 控制：AC 接通且电量 ≥ 90% 时亮绿灯；AC 断开时红/绿都灭 | ✅ |
| 调试串口 UART2 | `/dev/ttyS2`，1500000 8N1 | ✅ |
| Maskrom | BootROM 功能 | N/A |

## README 标注未实现/部分的项

| 项目 | 当前结论 |
|---|---|
| 麦克风静音 LED | ❌ 阻塞：DTS、键盘 HID、LED class 均未发现对应引脚/节点 |
| 键盘无线开关 F8 | ✅ IceWM 已绑定 `XF86WLAN`；LXQt 已补 `XF86WLAN -> z96a-hotkey wifi-toggle` |
| 电池电量键 F9 | ✅ IceWM 已绑定 `XF86Battery`；LXQt 已补 `XF86Battery -> z96a-hotkey battery` |
| 三个 ES7202 | ✅ 三颗已全部驱动并进入同一 PDM 采集：ch0/1 = 麦克风（0x30, SDI1）、ch2/3 = AEC 参考（0x31, SDI2）、ch4/5 = 耳机/回环（0x32, SDI3）。实测只有 ch0/1 有房间声学信号，ch2-5 为电信号回环，因此不是 6 麦阵列 |
| Chromium/Thorium 硬件解码 | ✅ `/usr/local/bin/z96a-thorium` 不再覆盖 `--use-gl`，由 Thorium 包装脚本使用 EGL + `--hardware-video-device-path`；`1.mp4` 实播画面正常，日志确认 S264 → NV12、rkvdec 被解码进程占用。ANGLE GLES 路径会导致 NV12 DMA-BUF 无法导入而黑屏 |
| X11 窗口内视频呈现（mpv/Panfrost） | 🟡 1920×1080 ≈ 47fps、1600×900 ≈ 58fps、1280×720 ≈ 59–60fps；瓶颈为 Panfrost NV12/dmabuf 每帧渲染成本（`framedrop=no` 媒体 0.745x、GPU 800MHz、Xorg CPU 1.4%）。Mesa 26.1.6 backport 实测更慢（313 vs 244 丢帧），不采用。1080p@60 仅剩 Bifrost ABI 探针待判定 |

## 本轮收敛内容

- 摄像头供电：新增 `patches/git/z96a-v2/linux-add_sunniwell_z96a/0009-z96a-camera-power.patch`，DT 中增加 `vcc_camera`（`GPIO2_D0`，always-on）。
- 摄像头现场验证：手动拉高 GPIO2_D0 后 `0c45:6368` 正常枚举，`/dev/video4/5` 出现，1920x1080 MJPG 抓帧成功。
- 摄像头 `.84` 持久化：已把带 `vcc_camera` 的 DTB 安装到 `/boot/rockchip/rk3568-sunniwell-z96a-typec.dtb`，原文件备份为 `.before-camera`，下次冷启动自动上电。
- 摄像头冷启动复核：`vcc_camera` regulator 状态为 enabled，GPIO2_D0（gpiochip2 line 24）为 output 且 consumer 为 `regulator-vcc-camera`，说明供电控制已经常开；当前 USB 总线只有 GL852G Hub + 键盘、RTL8153 和 U 盘，没有 `0c45:6368`，因此本次是摄像头未接入/未枚举，不是驱动或供电缺失。
- 电池温度：`defconfig/z96a-v2_defconfig` 打开 `CONFIG_GENERIC_ADC_THERMAL=y`；`.84` 已临时编译并安装 `thermal-generic-adc.ko`，`battery-thermal` 温度实测 31.5°C，且 udev 能自动加载。
- F8/F9：LXQt `globalkeyshortcuts.conf` 增加 `XF86WLAN`、`XF86Battery` 绑定。
- eMMC：新增 `0010-z96a-emmc-hs400.patch`，仅增加 `mmc-hs400-1_8v`；已编译并更新 `.84` 启动 DTB，原文件备份为 `.before-hs400`。没有声明 Enhanced Strobe。重启后内核日志已确认 `mmc0: new HS400 MMC card`，HS400 实际协商成功。
- Thorium 黑屏：确认根因是 `/usr/local/bin/z96a-thorium` 曾强制 `--use-gl=angle --use-angle=gles`；ANGLE GLES 在本平台不提供 NV12 DMA-BUF 导入，硬件解码帧无法合成，表现为黑屏。改为与 Thorium RK3568 包装脚本一致的 EGL + V4L2 设备路径后，`1.mp4` 实播画面正常；`media/gpu/v4l2` 日志显示 `S264` stateless 解码、输出 `NV12`，解码期间 rkvdec 由 Thorium 占用。镜像内 Thorium 包也已替换为带该包装脚本的构建，`SHA256SUMS` 同步更新。
- ES7202：复核发现三颗 `0x30/31/32` 都绑定驱动，且 PDM SDI1/2/3 都在 DTS 启用；当前声卡仍只连 `0x30`，底层实际为 2ch。`plughw` 可返回 4ch WAV，但同时查看 PCM hw_params 显示硬件仍是 2ch，不能视为阵列已驱动。用户提出阵列假设，需进一步确认线序并做原生多通道采集，暂不擅自改 codec mute/格式。
- ES7202 6ch 验证（已完成）：新增 `0011-z96a-es7202-6ch.patch`，把 DAI `channels_max` 提到 6，并用全局实例列表在 stream 开始时解除/停止时恢复三颗 PDM 输出。实测 `arecord -D z96a_mic -c 6` 原生 6ch 成功（hw_params `channels: 6`）；逐颗静音确认映射 ch0/1=0x30(SDI1)、ch2/3=0x31(SDI2)、ch4/5=0x32(SDI3)。扬声器 1kHz 测试显示 ch0/1 为声学拾音（有环境底噪、crest 1.76），ch2-5 为电信号回环（纯正弦比 1.000、彼此相关 1.000、静音时几乎无底噪），因此是“2 麦 + AEC 参考 + 耳机/回环”，不是 6 麦阵列。
- 充电灯策略：新增 `z96a-charge-led` 守护进程和 `/etc/init.d/z96a-charge-led`；AC 接通且电量 ≥ 90% 亮绿灯，AC 接通且电量 < 90% 亮红灯，AC 断开红/绿都灭。守护进程启动时会解除内核默认的 `bq257xx-fgu-*` trigger。
- X11 窗口内视频呈现：实测 1920×1080 ≈47fps、1600×900 ≈58fps、1280×720 ≈59–60fps，瓶颈为 Panfrost 的 NV12/dmabuf 渲染成本；mpv 调参已穷尽，Mesa 26.1.6 backport 反而更慢（313 vs 244 丢帧）。1080p@60 待 Bifrost ABI 探针判定，详见 `Z96A-TODO-PLAN.md` 的“视频呈现”小节。
- 文档：本文件作为硬件驱动状态的收敛清单。

## 保持现状/不处理

- eMMC HS400：已实际协商成功。后续仅在出现稳定性问题时回退到 HS200；未启用 Enhanced Strobe。
- 麦克风静音 LED：没有可确认的 GPIO/HID 通道，继续阻塞。
- ES7202 多通道阵列：已确认三颗全部驱动并实现原生 6ch 采集（`z96a_mic`）。通道角色经逐颗静音与扬声器测试确认：ch0/1 为房间麦克风（0x30），ch2/3 为 AEC 参考（0x31），ch4/5 为耳机/回环（0x32）；ch2-5 是电信号，不是麦克风。改动见 `0011-z96a-es7202-6ch.patch`。
- HDMI、3.5mm 耳机、OTG device 模式、USB2 两个外口、扬声器：按用户要求不处理。
