# Z96A 硬件驱动状态

更新时间：2026-11-10。测试环境：Sunniwell Z96A Type-C，Devuan Excalibur，内核 `7.2.12`，设备 `.84`。

状态：✅ 已验证 / 🟡 驱动在位但未完整物理验证 / ❌ 缺失 / N/A 不需要或按用户要求不处理。

## 规格硬件

| 项目 | 实际驱动/节点 | 状态 |
|---|---|---|
| SoC RK3568B2 | 4×Cortex-A55、`panfrost`、`rockchip_vdec`、`hantro_vpu`、`rga` | ✅ |
| PMIC RK809-5 | `rk8xx-i2c`、`rk808` regulator、`rk808-rtc`、`snd_soc_rk817` | ✅ |
| DRAM 4GB LPDDR4X | `MemTotal 4015956kB`；TPL/U-Boot 初始化 | N/A（可用） |
| eMMC 32GB SiliconGo | `mmc0` 29.1GiB；冷启动确认 `mmc0: new HS200 MMC card` | ✅（HS200） |
| WiFi RTL8822CS | `rtw88_8822cs`，SDIO 1.8V / 200MHz SDR104（tuned phase 122–126）；5G 局域网 ~16.6–18.0 MB/s | ✅ |
| 蓝牙 RTL8822CS | `hci_uart` + `btrtl`，`hci0` UP | ✅ |
| 显示屏 BOE NV140FHD-N43 | `panel-edp` + `analogix_dp` + `phy_rockchip_naneng_edp` + VOP；1920×1080 | ✅ |
| 键盘 SH61F83Q / 触控板 CST128-A | `usbhid` | ✅ |
| USB Hub GL852G | `usbcore` generic hub，4-port | ✅ |
| 摄像头 Microdia `0c45:6368` | `uvcvideo`；DT 新增 `vcc_camera`（GPIO2_D0，always-on） | 🟡（驱动/供电就绪，当前未接入） |
| Type-C 控制器 HUSB311 | `tcpci_rt1711h`，`port0` host/source | ✅（非本次充电输入故障层；OTG device 不处理） |
| USB 3.1 切换 D3EB | `gpio_sbu_mux` 绑定 `usb-switch` | ✅ |
| 充电芯片 SC8886 | `bq257xx-charger` | 🟡（正常充电器稳定；已知旧充电器导致输入抖动） |
| 电池 SHT 3585130-2S | RK817 PMIC 库仑计 `rk817-battery`（100% / 8.387V / 5Ah）；`bq257xx-fgu` OCV 已停用；`battery-thermal` 温度 | ✅ |
| 霍尔开关 MH248 | `gpio-keys-hall`，`event0` | ✅ |
| 音频 ADC 3×ES7202 | i2c `0x30/31/32` 均绑定 `es7202`；`z96a_mic` 原生 6ch | ✅（见下） |
| 音频 codec RK809 | `rk817-codec` + `rk809-sound`；差分 MIC（codec reg `0x27=0xf0`） | ✅ |
| 音频功放 AW8737AFCR | `simple-amplifier`，播放时 GPIO3_A6 使能 | ✅ |
| HDMI 音频 | `hdmi_sound`（simple-audio-card）`mclk-fs=128`，与厂内对齐 | 🟡（待 HDMI sink 实测） |
| DC-DC TCS4525 | `fan53555`，`vdd_cpu 1150mV` | ✅ |
| 扬声器/分立 MOS/保护板 | 无 Linux 驱动或按用户要求不处理 | N/A |

## 接口与指示灯

| 项目 | 实际状态 | 状态 |
|---|---|---|
| 电源 Type-C | `bq257xx` + `HUSB311` | 🟡（HUSB311 状态与好坏充电器一致；问题在充电输入侧） |
| USB 3.0 Type-A | xHCI，SanDisk 5Gbps 实测正常 | ✅ |
| USB 2.0 ×2 / USB-C OTG / HDMI / 3.5mm | 按用户要求不处理 | N/A |
| 模拟麦克风 ×2 | ES7202 PDM，`z96a_mic` 6ch；ch0/1 房间麦(0x30)、ch2/3 AEC(0x31)、ch4/5 耳机/回环(0x32) | ✅（不是 6 麦阵列） |
| 电源 LED | `white:power`，`bq257xx-charger-online` | ✅ |
| 大写锁定 LED | `input1::capslock` | ✅ |
| 麦克风静音 LED | 复用键盘 `input1::numlock`，`z96a-hotkey` 静音时点亮 | ✅ |
| 充电 LED | 红 `red:charging` / 绿 `green:charging`，由 `z96a-charge-led` 控制（AC 且 <90% 红，≥90% 绿，断开全灭） | ✅ |
| 调试串口 UART2 | `/dev/ttyS2`，1500000 8N1 | ✅ |

## 关键结论

- **Thorium 硬件解码**：`/usr/local/bin/z96a-thorium` 不得传 `--use-gl=angle`；ANGLE GLES 无法导入 NV12 DMA-BUF，会黑屏。改用 EGL + `--hardware-video-device-path` 后 `1.mp4` 正常，日志确认 S264→NV12。
- **X11 视频呈现**：1080p 实测 1920×1080≈47fps、1600×900≈58fps、1280×720≈59–60fps；瓶颈是 Panfrost 每帧 NV12/dmabuf 渲染成本。mpv 调参已穷尽；Mesa 26.1.6 隔离测试曾更慢（313 vs 244 丢帧）。**注意：为 Vulkan/PanVK，镜像已把系统 Mesa 升到 26.1.6（excalibur-backports），视频需在新基线上复测。** 细节见 `references/MPV-X11-4K-HEVC.md`。
- **eMMC 速度**：已移除 `0010-z96a-emmc-hs400.patch`；内核 DTS 保持 HS200 / `max-frequency=200MHz`，不启用 `mmc-hs400-1_8v`，与原厂 U-Boot/内核一致。HS400 下 eMMC 写入曾出现 I/O error。
- **电池温度**：`CONFIG_GENERIC_ADC_THERMAL=y`；`.84` 已用临时 `thermal-generic-adc.ko` 验证 `battery-thermal` 31.5°C。
- **电池计量（2026-11-13）**：已启用 RK817 PMIC 库仑计 `rk817-battery`：100% / 8.387V / 5Ah，`present=1`；upower 只显示这一块电池（42.02Wh）。`bq257xx-fgu` 电压 OCV 已 unbind 并 blacklist，不再叠加；待完整充放电周期观察长期漂移。
- **充电灯**：事件驱动。`rk817_charger` 每 8 秒采样，但只在整数 `capacity` 或 `charge_status` 变化时 `power_supply_changed`；eudev 规则 `/etc/udev/rules.d/99-z96a-charge-led.rules` 执行一次 `z96a-charge-led --once`。AC 在线 ≥90% 绿、<90% 红、拔掉灭；插拔由驱动 IRQ 立即通知；init.d 启动时 one-shot，无常驻轮询。
- **充电输入 A/B（2026-11-10）**：正常充电器稳定 `online=1 / Charging`；旧充电器造成 SC8886 `AC_STAT` 和 `online` 周期抖动。HUSB311/TCPM 在好坏充电器下状态一致，不是本次故障层。不要用 0014、运行时重绑定或恢复服务掩盖输入异常。
- **F8/F9**：LXQt `globalkeyshortcuts.conf` 已绑定 `XF86WLAN`、`XF86Battery` 到 `z96a-hotkey`。

## 待验证 / 后续

### 显示
- [ ] eDP `sunniwell,rh218` TX/RX LV3：vendor 有、mainline 无；出现闪屏/link retrain 再移植 PHY 调参。
- [ ] HDMI `rockchip,phy-table`：仅信号/兼容性异常时对比 vendor 5 组校准。
- [ ] panel bpc：vendor RGB666 vs mainline EDID 8bpc，出现色带再做 A/B。
- [ ] VOP `disable-win-move`：仅多屏/窗口迁移异常时再查。
- [ ] 确认面板始终运行在 `1920x1080 60.02Hz`（`xrandr` 同时列出 60.02/40.02，回落会压到 40fps 以下）。

### 热与电源
- [x] TSADC 95°C/mode1 + trips 95：4 核满载 4 分钟 CPU 最高 68.1°C、GPU 56.1°C，未触发降频。
- [ ] vendor 120°C/mode0 + trips 115：仅在需要更宽松策略时做 A/B（注意高温风险）。
- [x] 2026-11-10 完成充电器 A/B：正常充电器稳定充电；旧充电器稳定复现 SC8886 输入抖动，HUSB311 不是故障层。
- [ ] 停用已知故障的旧充电器；若需进一步区分充电器本体与自带线/插头，再做换线 A/B 或硬件测量。
- [ ] charger NTC / `high_temp_off=43`：mainline `bq257xx` 未配置 NTC 高温截止；需驱动支持或确认硬件默认，不要加热电池验证。
- [ ] PMIC 长按/复位属性未被 `rk8xx` 解析；需驱动支持或手动长按测试。
- [ ] 重建内核后确认内建 `CONFIG_GENERIC_ADC_THERMAL` 同样生成 `battery-thermal`。

### 音频
- [x] 三颗 ES7202 全部驱动，`arecord -D z96a_mic -c 6` 原生 6ch 成功（2/4/6ch 均可）。
- [ ] 若原理图/实物确认 0x31/0x32 接的是额外麦克风，再调整通道角色。
- [ ] `rockchip,mic-in-differential` 未写入 DTS；有 3.5mm 麦克风时做 A/B 录音对比。
- [ ] HDMI `mclk-fs` 256 vs vendor 128：需要 HDMI 音频 sink，当前 disconnected。
- [x] PDM `path-map`：vendor `1 3 0 2` vs mainline `1 2 3 0` 实测 4ch 一致，无需改。

### 摄像头
- [x] 确认为 USB 2.0 UVC `0c45:6368`，`uvcvideo` 驱动；供电 `GPIO2_D0` 已固定常开（`0009-z96a-camera-power.patch`）。
- [x] 手动拉高后 `/dev/video4/5` 枚举，1920×1080 MJPG 抓帧成功；冷启动确认 `vcc_camera` 使能。
- [ ] 当前 USB 总线未出现摄像头；接回后确认 `/dev/video*` 重现，并用应用做最终出图确认。

### GPU / 蓝牙 / 视频上限
- [ ] GPU devfreq：vendor `upthreshold=40`/`downdifferential=10`，mainline `simple_ondemand` 无等价属性，仅性能调优时研究。
- [ ] BT：主线硬件 RTS 已足够；`uart_rts_gpios` GPIO 回退仅在异常时再查。
- [ ] 重启清状态后复测 1600×900 / 1920×1080 视频基线并固定为正式上限（当前 125–244 丢帧有抖动）。
- [ ] 若 1920×1080@60 是硬指标：只剩专有 Bifrost，先做 1 小时 ABI 探针（Radxa `libmali-bifrost-g52-g13p0` 的 `KBASE_IOCTL_VERSION_CHECK` vs Bootlin r8p0 `BASE_UK_VERSION 10.6`），不匹配即放弃。
- [ ] 清理 `/opt/mesa26`、`/tmp/mesa26`（系统已升级到 26.1.6，隔离测试目录已无用）。
- [ ] 在 Mesa 26.1.6 系统基线上复测 mpv 1080p/4K，确认升级没有让视频明显退化；同时验证 OxideTerm(Vulkan)、LocalSend(OpenGL)、Thorium 硬解。
- [ ] 确认 Vulkan conformance layer 实际加载（`vulkaninfo --summary` 中 Mali 的 `conformanceVersion=1.3.0.0`，且无 `disable_environment` 警告）。
