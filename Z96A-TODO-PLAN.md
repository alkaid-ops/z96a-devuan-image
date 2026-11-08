# Z96A 待办计划

更新时间：2026-11-08（硬件驱动状态收敛）

## 当前状态

- 当前测试系统运行在 U 盘 `/dev/sda2`。
- 硬件驱动逐项状态已收敛到 `Z96A-HARDWARE-STATUS.md`。
- eDP、Wi-Fi、音量、麦克风、亮度、触摸板、显示切换、电池状态、截图、锁屏、电源菜单和功能键映射已部署到 `.84`。
- 摄像头已确认是 USB UVC（Microdia/Sonix `0c45:6368`），由 `uvcvideo` 驱动；供电受 `GPIO2_D0` 控制。已用 `0009-z96a-camera-power.patch` 把该电源在设备树中固定为常开；`.84` 已换用带 `vcc_camera` 的 DTB，冷启动自动上电。
- 电池温度已修复：`CONFIG_GENERIC_ADC_THERMAL=y`；`.84` 已加载 `thermal-generic-adc.ko` 并出现 `battery-thermal`。
- F8/F9 已在 IceWM 和 LXQt 中绑定。三颗 ES7202 已全部驱动并实现 6ch 原生采集，实测角色为 2 麦（ch0/1）+ AEC 参考（ch2/3）+ 耳机/回环（ch4/5），不是 6 麦阵列。麦克风静音 LED 已定位：接在键盘 NumLock LED 位（`input1::numlock`），`z96a-hotkey` 静音时点亮。
- 充电灯策略已收敛：新增 `z96a-charge-led`，AC 接通且电量 ≥ 90% 亮绿灯，< 90% 亮红灯，断开时全灭；`.84` 已实测 50% 亮红、98% 亮绿、断开全灭。
- 有线 IPv4 根因已定位：`z96a-wired.nmconnection` 已从 `Z96A Wired Static` 改为 `Z96A Wired DHCP`，但 `.84` 上仍是旧版 `z96a-network-up`，开机反复激活不存在的 `Z96A Wired Static`，随后 `nmcli device connect eth0` 激活了一个 `ipv4.method=disabled` 的临时 external 配置，导致 eth0 只有 IPv6、没有 IPv4。已把新版脚本部署到 `.84`，并手动激活 `Z96A Wired DHCP`，eth0 已恢复 `192.168.31.84/24`。
- 为防止再次漂移：删除 `.84` 上重复的 `eth0.nmconnection`；`z96a-network-up` 改为按固定 UUID `5ee20e57-d34e-494f-ba17-ecdf0163b214` 激活有线配置，重命名配置不再影响开机；同时把 board 当前的 NetworkManager 配置、wifi powersave、`/etc/network/interfaces` 和相关脚本 overlay 回 `files/bsp/z96a-v2/`，已与 `.84` 逐文件比对一致。
- eMMC 已新增 `mmc-hs400-1_8v` DTS 声明，并更新 `.84` 启动 DTB；冷启动内核日志确认 `mmc0: new HS400 MMC card`，HS400 已生效。
- HDMI、3.5mm 耳机、OTG device、USB2 两个外口、扬声器按用户要求不处理。
- 功能键当前使用 `F1-F11` 普通键码；特殊 `XF86*` 键码绑定同时保留。
- `Pause/齿轮键` 已从 `KEY_SLEEP` 改为 `KEY_PAUSE`，不会再因按该键挂起。
- 开机登录使用 `SLiM`，F1 和 IceWM 的 Lock Workstation 使用 `slimlock`，共用 SLiM 主题。
- 仅使用 slimlock；失败时明确报错，不回退到其他锁屏程序。
- 当前未安装 `LightDM`、`light-locker`、`slock`、`xlock` 或 `xss-lock`。
- 托盘音量/亮度图标共用一个面板，面板包含交流电/电池关屏、自动挂起和空闲关机设置；自动挂起与空闲关机互斥，默认均关闭。
- slimlock 已加入鼠标可操作的音量、亮度和关机/睡眠/重启按钮，所有电源动作都要二次确认。
- `.84` 已安装 `slim 1.4.0-0devuan2+z96a2` 和 `z96a-power-policy 1.0.2`；镜像侧已准备 `slim 1.4.1-1devuan1+excalibur2+z96a2` 与 `z96a-power-policy 1.0.2`。
- 本轮运行修复、软件包、补丁和测试已同步到本地 overlay 和 `.132` 镜像构建源，尚未重新打包镜像。

## P0：统一 SLiM 登录与锁屏

### 目标

锁屏和开机登录共用 SLiM 主题；继续使用 SLiM，不安装 LightDM。

### 当前待验证

- [x] slimlock 独立 DPMS 计时已关闭，桌面和锁屏的关屏时间统一由 `z96a-power-policy` 管理。
- [ ] 真机验证 slimlock 主题、5 秒熄屏、唤醒后解锁及连续三轮稳定性。
- [x] 实测静置约 30 秒后熄屏；模拟点亮并产生输入活动后，7 秒仍保持亮屏。
- [ ] 连续三轮锁屏、静置 6 秒熄屏、模拟点亮/输入并解锁成功。
- [ ] 用实体电源键确认面板唤醒效果；远程测试使用 DPMS 点亮模拟，未按实体按键。
- [ ] 冷启动后能正常进入 IceWM。
- [ ] slimlock 锁屏后能使用 `user` 密码解锁，并返回原 IceWM 会话。
- [ ] 挂起恢复后锁屏和通知服务仍正常。
- [ ] eDP、键盘、触控板、网络和中文输入法无回退。

## P0：SSH host key 持久化

- [x] 首次启动脚本只补建缺失 host key，不再删除已有密钥。
- [x] 新增早于 sshd 的缺失密钥检查服务；真机启动顺序为 `S02` 检查、`S03` sshd。
- [ ] 验证普通重启后密钥指纹及文件时间稳定。
- [x] 查到并删除会反复触发缺 key 的代码路径：开机 credentials 脚本原先无条件删除 `/etc/ssh/ssh_host_*` 并重配置 OpenSSH。历史日志记录了两次手动 `ssh-keygen -A` 恢复。
- [x] 全量审计 `.132` 构建仓库相关脚本及 `.84` 启动路径，未发现第二个删除 host key 的逻辑。

## P0：IceWM 左右半屏装饰

- [x] 左右半屏使用显式尺寸和坐标，避免触发 IceWM 全高最大化边缘行为。
- [x] 明确关闭最大化时隐藏标题栏和边框。
- [x] 真机左右半屏截图均确认标题栏及最小化、最大化、关闭按钮显示；纯状态转换用例通过。

## P1：镜像构建同步

- [x] 本轮三项修复同步到 `.132` 镜像构建输入；未执行镜像构建。
- [ ] 将其他已验证的 overlay 变更纳入镜像构建流程。
- [ ] 确认镜像包含 `slim`（提供 `slimlock`）、`brightnessctl`、`brightness-udev`、`xinput`、`libnotify-bin` 和 `notification-daemon`，且不安装 XScreensaver。
- [ ] 确认镜像包含 elogind 规则：忽略 `KEY_POWER`、`KEY_SLEEP`、`KEY_HIBERNATE`。
- [ ] 确认 `99-sunniwell-z96a-typec-keyboard.hwdb` 包含 `KEYBOARD_KEY_700F8=pause`、Wi-Fi 和触摸板映射。
- [ ] 确认 IceWM 功能键和 KWin 平铺快捷键都已写入镜像。
- [ ] 不构建镜像，直到用户明确确认开始打包。

## P1：启动与恢复可靠性

- [ ] 验证全新登录后 `notification-daemon` 自动启动。
- [ ] 验证挂起恢复后 `notification-daemon` 和 `slimlock` 仍可工作。
- [ ] 验证 SSH host key 在首次启动和普通重启后保持稳定。
- [ ] 验证 slimlock 异常退出时，F1 明确报告失败且不会启动其他锁屏程序。
- [ ] 验证电源键只打开电源菜单，不直接关机或挂起。

## P2：功能键行为确认

- [ ] 确认是否接受 `F1-F11` 被 IceWM 全局接管。
- [ ] 如需保留应用程序中的普通 F1-F12，确认 Fn Lock 或其他键盘模式的行为。
- [ ] 实测 Print 键在真实按键下启动 Flameshot。
- [ ] 实测电源键在真实按键下弹出 IceWM 电源菜单。
- [ ] 确认 `F12/Scroll Lock`、`Delete/Insert` 和 `Esc` 保持默认。

## P2：文档与恢复资料

- [ ] 记录最终登录管理器、锁屏程序和快捷键方案。
- [ ] 记录 slimlock 无法启动时的恢复方法。
- [ ] 记录 `z96a-hotkey` 全部子命令和对应按键。
- [ ] 保存本轮关键配置的备份位置和 SHA256。
- [ ] 更新镜像构建说明和真机验收记录。

## P0：挂起/唤醒故障安全模式

- [x] 复现证据：用户此前两次误触发的挂起均通过短按电源键恢复，日志也有对应的 `deep` entry/exit；但后续多次出现只有 `PM: suspend entry`、没有 exit 的间歇性恢复失败。
- [x] 单独 `s2idle` + RTC 定时唤醒测试未恢复，短按电源键无响应；该项不能据此推广为所有睡眠状态都完全不可唤醒。
- [x] 临时禁用自动挂起：`AutoSuspendEnabled=false`。
- [x] 临时禁用合盖挂起：`HandleLidSwitch=ignore`、`HandleLidSwitchExternalPower=ignore`、`HandleLidSwitchDocked=ignore`。
- [x] 保留 `IdleAction=ignore`、电源键 ignore；手动锁屏、调暗和 DPMS 保持可用。
- [x] 同步安全策略到本地 overlay 和 `.132` 构建目录。
- [ ] 在修复前禁止通过电源菜单手动 Suspend，禁止重新启用 deep/s2idle。
- [ ] 对比成功和失败挂起前后的状态、启动路径、外设连接、电池/AC、USB 设备和内核日志，定位间歇性触发条件。
- [ ] 使用串口或 `no_console_suspend` 捕获完整 suspend/resume 流程，检查 PMIC/RTC/PSCI、eDP、USB 和设备 suspend 回调。
- [ ] 修复后完成至少 3 次 deep 或受支持 sleep state 的唤醒测试，并验证 eDP、键盘、触控板、Wi-Fi、SSH 和电源策略。

## P0：AC/电池电源策略

- [x] 新增唯一 C 守护进程 `z96a-power-policy`，未安装 xss-lock/UPower/TLP。
- [x] 守护进程监听供电变化，提供 AC/电池调暗、锁屏、挂起计时和睡前 inhibitor。
- [x] Slimlock 已显示电源、电量、充电状态和挂起倒计时。
- [x] F1、IceWM LockCommand 和自动锁屏统一通过 `z96a-lock`。
- [x] elogind 临时改为合盖 ignore、电源键 ignore、系统 idle action ignore，避免再次进入不可唤醒状态。
- [x] 真机验证短时调暗/锁屏、状态行、5 秒 DPMS、锁屏输入重置和密码解锁。
- [x] 20% 低电量 GTK 对话框、实时倒计时、立即关机、强制继续与接电清除状态已实现并验证。
- [x] 通过 SARADC channel 4 NTC 检测电池在位；当前未接电池时显示 absent，不再误报 99%。
- [x] 守护进程实测 RSS 约 6 MiB。
- [ ] 用户确认后测试真实 AC 插拔、合盖/开盖和 deep suspend/resume。
- [ ] 用户确认后重新构建镜像并把已验证 overlay 写入发行流程。

## P0：托盘电源设置与锁屏控制

- [x] 音量、亮度托盘图标统一打开包含“电源设置”的面板。
- [x] 交流电和电池分别设置关屏、自动挂起和空闲关机时间。
- [x] 自动挂起与空闲关机互斥；两者默认关闭，已有 `AutoSuspendEnabled` 配置可迁移。
- [x] 配置先通过 `z96a-power-policy --check-config` 校验，再原子写入用户配置并热生效。
- [x] 低电量关机仅在确认电池单独供电且状态明确时启用，关机前再次核验。
- [x] slimlock 增加鼠标操作和确认后的关机、睡眠、重启按钮；电源调用继续使用活动本地用户的窄范围 polkit 授权。
- [x] 锁屏窗口先同时取得键盘和指针 grab，再发布 `lock-ready`，避免锁屏控件或按键穿透。
- [x] `slimlock` 1.4.0 和 1.4.1 的 Xvfb/PAM 隔离测试通过：错误密码仍锁定、正确密码解锁、鼠标不穿透、按钮二次确认和模拟电源动作。
- [x] Devuan 5/6 的 SLiM 包分别构建，避免混装；Devuan 6 使用 elogind，因此显式关闭旧 ConsoleKit 构建选项。
- [x] `.84` 已备份并安装新包；当前未执行真实关机、重启或挂起动作。
- [x] 真机锁屏确认音量/亮度/电源按钮可见；点击“关机”出现二次确认并已点击“取消”，未执行电源动作。
- [ ] 解锁后在真实桌面打开托盘“电源设置”，修改并保存一次非危险时间项。
- [ ] 用户确认后分别测试一次真实重启与关机按钮；睡眠按钮继续等待挂起/唤醒缺陷修复。
- [ ] 后续实现“挂起后定时唤醒再执行空闲关机”的待办功能。

## LXQt + Openbox 桌面迁移与主题

- [x] 运行时包清单加入 `lxqt-core`、`lxqt-powermanagement`、`openbox`、`papirus-icon-theme`、`obconf-qt`；保留 IceWM 供回退。
- [x] 增加 SLiM 可选 `LXQt (Openbox)` 会话，`startx` 默认 LXQt，`startx icewm` 保留回退。
- [x] 增加三套原创 inspired 外观 profile 与带备份/失败回滚的 `z96a-theme` 切换器。
- [x] 新增用户级 XDG 覆盖以禁用 LXQt 桌面及内置电源管理 autostart，并通过 Z96A session service 启动 z96a PCManFM-Qt profile 与既有电源守护进程；对应模块 desktop-entry 名称仍需按目标 Devuan 包版本核验。
- [x] 更新实施记录：[Z96A-LXQT-IMPLEMENTATION.md](Z96A-LXQT-IMPLEMENTATION.md)。
- [x] 2026-11-07 在 `.84` 真机会话验证音量加/减/静音、亮度、麦克风静音快捷键，并修复 ALSA 引擎、按卡名寻址的 `/etc/asound.conf`、全局快捷键配置；仍需用实体键帽做最终手感确认。
- [x] 2026-11-07 在 `.84` 真机加入音量变化提示音与亮度百分比通知：`z96a-volume-feedback` 监听 RK817 混音事件并在每次音量变化后播放预览音；亮度快捷键通过 `notify-send` 显示 `屏幕亮度: N%`。已验证无重复监听器、无 `aplay` 僵尸进程、服务重复启动可安全替换。
- [x] 2026-11-08 修正亮度连续调整延迟（直接读写 sysfs）、5% 最低亮度与 5% 步进、音量 100% 无声和音量曲线；音量快捷键改为 `z96a-hotkey`，0 为静音，1–100 线性映射到安全 raw 70–100%（raw 154–220）。
- [x] 2026-11-08 音量/亮度加入用户级持久化（`~/.local/state/z96a`），会话启动时恢复；亮度恢复下限 5%。
- [x] 2026-11-08 托盘音量/亮度改为事件驱动：`z96a-system-tray` 不再每 250ms/1s 调用 `z96a-hotkey volume-info` 和 `brightnessctl`，仅在 `volume-changed`/`brightness-changed` 信号变化时读取硬件，避免 ALSA 控制接口被大量 `amixer` 进程占满。
- [x] 2026-11-08 网络配置补齐：LXQt 通过 XDG autostart 运行 `nm-tray`，面板显示网络/Wi-Fi 托盘图标；新增桌面“网络连接”图标运行 `nm-connection-editor`，可编辑 Wi-Fi 与有线连接；IceWM 启动脚本同步启动 `nm-tray`；运行时包加入 `nm-tray`、`nm-tray-l10n`、`nm-connection-editor`。
- [x] 2026-11-08 新增桌面“配置中心”图标（`lxqt-config`），与其它桌面启动器一样自动写入 GVFS 信任标记；补齐 `qt6-svg-plugins` 后左下角 LXQt 开始菜单图标恢复显示，开始菜单 → 首选项 → LXQt 配置中心可用。
- [x] 2026-11-08 桌面启动器双击信任修复：`z96a-desktop-trust` 在会话启动、PCManFM-Qt 加载桌面之前写入 GVFS `metadata::trust`，消除 `~/Desktop` 的叹号徽标；启动器图标改为绝对 Papirus/hicolor 路径并加入 `qt6-svg-plugins`；PCManFM-Qt profile 设置 `FallbackIconThemeName=Papirus`、`SingleClick=false`、`QuickExec=true`，双击直接运行且无执行确认框；信任状态写入 `~/.local/share/gvfs-metadata` 并可跨会话保留。
- [x] 2026-11-08 复用既有 IceWM 托盘弹窗作为 LXQt OSD（`z96a-system-tray --osd`），隐藏状态图标；同一窗口原地更新音量/亮度，连续调节不堆叠，最后一次变化 1.2 秒后隐藏；面板 `showKeyboardNotifications=false`；无包装器僵尸进程。Wayland 与 LXQt 升级暂不考虑。
- [ ] 在 Devuan ARM64 目标仓库重新模拟/验证完整依赖闭包，确认无 systemd、systemd-logind、Plasma、KWin 等非预期依赖。
- [ ] 真机验证 SLiM 会话选择、LXQt/Openbox 启动/注销、桌面图标、托盘、音频/网络/输入法、锁屏与主题切换。
- [ ] 测量基线及三套 profile 的 PSS/RSS、整机可用内存、空闲 CPU、启动耗时和 30 分钟变化；测试前不启用 Picom/Plank。
- [ ] 真机验收通过后再评估 IceWM 清理；当前不得卸载。

## 安全边界

- 不修改 eMMC、U-Boot、GPT、内核或 DTB，除非另行创建独立计划。
- 不在未备份的情况下替换显示管理器。
- 不直接删除 `SLiM`；如采用 LightDM，必须先完成完整替换和回退测试。
- 不在未验证的情况下重新打包或刷写 eMMC。

## 长期待办：显示/电源/音频二次核验（2026-11-07）

> 这些不是当前已复现故障，等真正空闲时再做；不做也不影响日常使用。
> 当前 `.84` 已运行 7.2.12，`/boot/recovery` 保留 7.2.11 回退。

### 显示

- [x] VPLL/DCLK_VP1 = 140.24M：已在 7.2.12 上验证，eDP 60Hz。
- [x] 背光：当前 `20..220/200` 步，最大 100% duty，正常。
- [ ] eDP `sunniwell,rh218` TX/RX LV3：vendor 有，mainline 无；若出现偶发闪屏或 link retrain，再考虑移植 PHY 调参。
- [ ] HDMI `rockchip,phy-table`：vendor 有 5 组 PHY 校准，mainline 用静态表；仅 HDMI 信号/兼容性异常时再对比。
- [ ] panel bpc：vendor RGB666/6bpc，mainline 走 EDID 8bpc；若出现色带再做 A/B。不要直接把 compatible 改成 patch 0004 的 139.8M/2080x1120 模式。
- [ ] VOP `disable-win-move`：vendor workaround，mainline 无；仅多屏/窗口迁移异常时再查。

### 热与电源

- [x] TSADC 95°C/mode1 + trips 95：4 核满载 4 分钟，CPU 最高 68.1°C、GPU 56.1°C，无关机/降频，95°C 未触发。
- [ ] vendor 120°C/mode0 + trips 115：仅在需要更宽松的 vendor 策略时再做 A/B；注意高温风险。
- [ ] charger NTC / `high_temp_off=43`：mainline bq257xx 未配置 NTC 高温截止，vendor SC8886 有。需要驱动支持或确认充电器 TS 脚硬件默认；不要通过加热电池来验证。
- [ ] PMIC 长按/复位：vendor `press-on-time`、`long-press-off-time-sec`、`long-press-restart`、`pmic-reset-func`、`not-save-power-en` 未被 rk8xx 解析；需要驱动支持或用户手动长按测试。
- [x] 发现 `.84` 电池 NTC 温度不可见：`CONFIG_GENERIC_ADC_THERMAL` 未启用，`battery-thermal` thermal zone 没有注册；已把 `defconfig/z96a-v2_defconfig` 改为 `CONFIG_GENERIC_ADC_THERMAL=y`。
- [x] `.84` 已用临时编译的 `thermal-generic-adc.ko` 验证：`battery-thermal` 出现，温度 31.5°C；udev 可通过 `of:N*T*Cgeneric-adc-thermal` 自动加载。
- [ ] 重建内核/镜像后确认内建版本同样生成 `battery-thermal`（`CONFIG_GENERIC_ADC_THERMAL=y`）。

### 音频

- [x] 三颗 ES7202 全部驱动：`0011-z96a-es7202-6ch.patch` 把 DAI `channels_max` 提到 6，并用全局实例列表在采集开始时解除、停止时恢复三颗 PDM 输出。`arecord -D z96a_mic -c 6` 原生 6ch 成功（hw_params `channels: 6`）；2ch/4ch/6ch 均可。
- [x] 通道角色确认：ch0/1 = 麦克风（0x30, SDI1），ch2/3 = AEC 参考（0x31, SDI2），ch4/5 = 耳机/回环（0x32, SDI3）。逐颗静音验证映射；1kHz 扬声器测试显示 ch0/1 为声学拾音，ch2-5 为电信号回环，因此不是 6 麦阵列。
- [x] `/etc/asound.conf` 增加命名采集设备 `z96a_mic`（按 card ID，不依赖 card 号）。
- [x] LED 遍历完成：主板并排三灯为电源 `white:power`（GPIO0_D3）、大小写（键盘 HID `input1::capslock`）、静音（键盘 HID `input1::numlock` 复用）；Type-C 口另有一颗充电指示灯 `red:charging`（GPIO0_D5）/`green:charging`（GPIO0_D6）。
- [x] 静音灯已接入：写 `input1::numlock` 的 brightness 即可控制（权限 root:input 0664，user 在 input 组）。`z96a-hotkey` 静音时置 1、恢复时置 0，实测有效。GPIO0_B7 的 work LED 是 V1 固件残留，V2 不接灯，相关补丁已撤销。
- [ ] 若后续确认 0x31/0x32 实际接的是额外麦克风（需原理图/实物），再调整通道角色与默认采集配置。
- [ ] `rockchip,mic-in-differential`：mainline codec 驱动支持，但 DTS 未写；有 3.5mm 麦克风时 A/B 录音 RMS、噪声和差分输入效果。
- [ ] HDMI `mclk-fs` 256 vs vendor 128：需要 HDMI 线 + 音频 sink；当前 HDMI 为 disconnected，未做 A/B。
- [x] PDM `path-map`：vendor `1 3 0 2` vs mainline `1 2 3 0`，实测 4ch 结果一致（ch0/1 有信号，ch2/3 静音）；当前无需改。

### 摄像头

- [x] 硬件确认为 USB 2.0 UVC：`0c45:6368` Microdia/Sonix，挂在 GL852G Hub 的 `2-1.2` 端口，走主线 `uvcvideo`，无需额外 sensor/ISP 驱动。
- [x] 供电脚定位为 `GPIO2_D0`（gpiochip2 偏移 16，sysfs 全局号 592）：手动拉高后立即枚举出 `0c45:6368`。
- [x] 已整理为 `patches/git/z96a-v2/linux-add_sunniwell_z96a/0009-z96a-camera-power.patch`：新增 `regulator-vcc-camera`，`regulator-always-on`/`regulator-boot-on`，并在 pinctrl 中把 `GPIO2_D0` 设为 GPIO 输出。
- [x] `.84` 实测：`/dev/video4`、`/dev/video5` 出现，`uvcvideo` 可通过 udev 自动加载；支持 1920x1080 MJPG，`ffmpeg` 抓帧成功。
- [x] 重建内核并冷启动验证：不依赖手动 `gpioset`，开机后 `vcc_camera` 已使能、GPIO2_D0 由 `regulator-vcc-camera` 持有输出。
- [ ] 摄像头当前未插或未枚举：USB 总线只有 GL852G Hub、键盘、RTL8153 和 U 盘，无 `0c45:6368`；接回摄像头后确认 `/dev/video*` 重现阶段。
- [ ] 在 LXQt/IceWM 里选一个摄像头应用（如 `cheese` 或 `ffmpeg` 预览）做最终出图确认。

### GPU / 蓝牙

- [x] Thorium 播 MP4 黑屏已修复：`/usr/local/bin/z96a-thorium` 不再传 `--use-gl=angle`，改由 Thorium 包装脚本使用 EGL + `--hardware-video-device-path`；`1.mp4` 实播画面正常，日志确认 S264→NV12 硬件解码。镜像内 Thorium deb 已替换为带 EGL 包装脚本的构建并更新 `SHA256SUMS`。
- [x] BT scan 正常；主线硬件 RTS 已足够，vendor `uart_rts_gpios` GPIO 回退仅在 BT 异常时再查。
- [ ] GPU devfreq：vendor `upthreshold=40` / `downdifferential=10`，mainline `simple_ondemand` 无等价属性；仅性能/功耗调优时再研究。

### 视频呈现（X11 窗口内，必须保留 X11）

测试条件：`/opt/mpv-rga/bin/mpv --vo=gpu --gpu-context=x11egl --hwdec=v4l2request --gpu-dumb-mode=yes --dither=no --deband=no --swapchain-depth=3`，片源 `test-jellyfin-avc-1080p60-*.mp4`，面板 1920×1080@60.02，Mesa 25.0.7 / Panfrost。

- [x] 瓶颈已定位为 Panfrost 的 NV12/dmabuf 每帧渲染成本，不是 X11 拷贝：`--framedrop=no` 时媒体 0.745x（VO 真阻塞）；播放时 GPU 800MHz、Xorg CPU 1.4%；裸 GLX 全屏能跑满 60fps。
- [x] 已测上限：1920×1080 ≈ 47fps；1600×900 ≈ 58fps；1280×720 ≈ 59–60fps。
- [x] mpv 调参已穷尽：`dumb-mode`、`dither/deband`、`swapchain-depth 1–4`、`swapinterval 0|1`、`fbo-format`、`scale=nearest`、`blend-subtitles=no`、`framedrop` 组合都无法让 1920×1080 到 60fps。
- [x] 用户已确认必须留在 X11 窗口内；DRM/KMS 直出方案不作为当前目标（仅作为“若放开限制”的备选记录）。
- [x] RGA 路线已否：该内核 RGA（V4L2 M2M）只支持 MMAP，不支持 dmabuf 导入，零拷贝 4K→1080p→EGL 不可行。
- [x] Mesa 26.1.6（`excalibur-backports`，解包到 `/opt/mesa26` 隔离测试）不改善：同条件丢帧 313 vs 系统 Mesa 25 的 244（同轮 A/B），仅带来 GLES 3.2 功能。注意 `MESA_LOADER_DRIVER_OVERRIDE` 必须用 `rockchip`；用 `panfrost` 会掉到 llvmpipe。
- [ ] 重启清状态后复测 1600×900 / 1920×1080 基线并固定为正式上限（当前绝对值有抖动，125–244 丢帧）。
- [ ] 若 1920×1080@60 是硬指标：只剩专有 Bifrost。先做 1 小时 ABI 探针：从 Radxa `libmali-bifrost-g52-g13p0` 提取 `KBASE_IOCTL_VERSION_CHECK` 期望版本，与 Bootlin r8p0 的 `BASE_UK_VERSION 10.6` 对比；不匹配即放弃，匹配再评估 vendor Xorg 与 ABI 成本。
- [ ] 清理 `/opt/mesa26`、`/tmp/mesa26`（复测结束前保留）。
- [ ] 确认面板始终运行在 `1920x1080 60.02Hz`；现在 `xrandr` 会同时列出 60.02 与 40.02，若回落到 40.02 所有呈现都会被压到 40fps 以下。

### 构建 / 维护

- [ ] 全镜像 `...7.2.12...img.xz` 只做了静态校验，未刷机启动；空闲时刷第二张 USB 做完整启动验证。
- [ ] Tsinghua `excalibur-security` 的 zlib 包同步后，删除 `files/bsp/z96a-v2/etc/apt/preferences.d/zlib1g`，并重新跑一次 `apt upgrade`。
- [ ] 若 yjun123 remote HEAD 再前进，重新 fetch 并 rebase `0002-z96a-sdmmc1-remote-head.patch` / `0008`；当前 `.cache` 为 `0211cf630`。
- [ ] 确认稳定后清理 `0002-z96a-wifi-power-rail.patch.old` 和 `remote-head/` 说明文件。
- [ ] 7.2.12 稳定运行一段时间后，再决定是否移除 `/boot/recovery` 的 7.2.11 回退入口。
- [ ] vendor-only 功能（IR 遥控、MXC6655 加速度计、ADC keys、BT SCO/I2S2、SPDIF、SATA1/SFC、NPU/VENC/JPEG/IEP）按需再补；多数需要额外驱动或节点。
