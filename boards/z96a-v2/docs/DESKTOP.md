# Z96A 桌面、主题与电源实施记录

更新：2026-11-09。运行环境与实测数据见 [`MEMORY.md`](MEMORY.md)，硬件见 [`HARDWARE-STATUS.md`](HARDWARE-STATUS.md)。

## 1. 会话与软件包

- `runtime-packages.txt` 包含 `lxqt-core`、`lxqt-powermanagement`、`openbox`、`papirus-icon-theme`、`obconf-qt`、`qterminal`、`qt6-svg-plugins`、`gvfs-daemons`、`inotify-tools`、`nm-tray`、`nm-tray-l10n`、`nm-connection-editor`、`wmctrl` 等；镜像安装脚本关闭 Recommends。
- 登录管理器为 SLiM，`startx` 只启动 LXQt；IceWM 及 `~/.icewm`、`z96a-icewm-tile`、GTK `pcmanfm`、`notification-daemon` 已移除。
- 单虚拟桌面：`z96a-theme` 写 `<desktops><number>1</number></desktops>`，并在构建时删除 `~/.cache/openbox/sessions`。
- LXQt 电源管理恢复锁屏/手动挂起/电源键菜单：`powerKeyAction=6`（打开四项电源菜单）、`suspendKeyAction=4`、`hibernateKeyAction=-1`；自动动作仍关闭（idle/lid/low-battery 为 `-1`），会话启动后另关 X11 blanking/DPMS。
- 文件管理器、`inode/directory`、GVfs 网络协议统一指向 `pcmanfm-qt`。

## 2. 主题系统（`z96a-theme`）

```sh
z96a-theme list
z96a-theme switch windows7|windows10|windows11|macos
z96a-theme backup | restore [snapshot]
```

四个 profile 定义在 `opt/z96a/desktop/profiles/<name>/`（`profile.json` + `panel.conf`）：

| profile | LXQt/Openbox 主题 | 图标 | 壁纸 |
|---|---|---|---|
| windows7 | `Z96A-Win7` / `Z96A-Win7` | `Windows-7` | `z96a/wallpapers/windows7.png` |
| windows10 | `Z96A-Win10` / `Z96A-Win10` | `Windows-10` | `windows10.png` |
| windows11 | `light` / `Z96A-Fluent` | `Papirus` | `windows11.png` |
| macos | `light` / `Z96A-macOS` | `Papirus` | `macos.png` |

- 切换时检查资产、快照托管文件，失败自动回滚；写配置前停 `lxqt-panel` 与 `pcmanfm-qt`。
- 同时写 PCManFM-Qt 的 `Wallpaper`/`WallpaperMode`/`FgColor`/`ShadowColor`，以及图标主题、桌面快捷方式列表。
- Openbox 配置由 `/etc/xdg/openbox/rc.xml` 生成并去命名空间（原因见 `MEMORY.md`）。
- Win10 额外资产：深色 Hero 壁纸、任务栏渐变、白色开始标志、`Z96A-Win10-panel.qss`（深色任务按钮 + 蓝色激活下划线）。
- Win7 额外资产：Harmony 壁纸、深蓝玻璃面板、开始球、`Z96A-Win7-panel.qss`（蓝色玻璃胶囊按钮）。
- 面板尺寸见 `MEMORY.md`；Win10 任务按钮保留图标+文字（纯图标方案已被用户否决）。

## 3. 面板与托盘

- 所有 profile 去掉 `quicklaunch` 与 `desktopswitch`；面板为 开始菜单 → 任务栏 → 状态区 → 托盘 → 挂载 → 系统监控 → 时钟 → 显示桌面。
- 不使用面板音量插件：托盘无喇叭图标，音量只由 `z96a-hotkey` + OSD 反馈。
- 世界时钟高级格式 `M月d日 ddd HH:mm:ss`。
- 开始菜单电源项只有四项，且顺序固定：锁屏 → 挂起 → 关机 → 重新启动。`lxqt-hibernate`/`lxqt-leave`/`lxqt-logout` 三个桌面项由 `uscripts` 删除，`lxqt-applications.menu` 把 X-Leave 与 Screensaver 两个子菜单内联到根菜单并在 X-Leave 内用 `<Layout>` 固定顺序，因此不再出现“离开”层级。
- 系统监控插件 `z96a-sysmon`（`boards/z96a-v2/tools/z96a-sysmon/`）：第一行 `CPU 12%  MEM 45%`，第二行 `↑0.3M  ↓1.2M`；13px、2 秒刷新、读取 `/proc`，运行在 `lxqt-panel` 内，无额外进程；悬停显示完整 CPU/内存/上传/下载数值。
- 网络托盘为 `nm-tray`（`nm-tray-l10n`）：以太网/Wi-Fi、连接/断开；`nm-connection-editor` 提供完整编辑。
- 电池图标由 `z96a-system-tray` 自绘，默认读取 `/sys/class/power_supply/rk817-battery`（电量、充放电、电池/CPU 温度）；关闭 LXQt 自带 battery watcher；点击打开电源管理设置。
- LED 行为：Caps Lock 旁的 `white:power` 是系统运行灯，`default-on` 常亮；C 口 `red:charging`/`green:charging` 由 `z96a-charge-led` 读 `rk817-battery` 容量 + `bq257xx-charger` online 控制，充电红、≥90% 绿、拔掉灭。系统灯不再由 `bq257xx-charger-online` 驱动。当前为事件驱动：驱动 `rk817_charging_monitor` 只在整数容量或充电状态变化时发 `power_supply_changed`，Devuan 的 eudev 读取 `99-z96a-charge-led.rules` 执行一次 `z96a-charge-led --once`；init.d 只在启动时跑一次，无 2 秒轮询。
- 键盘通知关闭（`showKeyboardNotifications=false`），音量/亮度统一走 `z96a-system-tray --osd`。

## 4. 桌面图标与快捷方式

- 图标 47px、`DesktopCellMargins=@Size(4 0)`、`DejaVu Sans 9`、阴影 `#80000000`，原因见 `MEMORY.md`。
- 桌面图标顺序固定：`desktop-items-0.conf` 为前六个图标写入自定义位置（用户文件夹 → 计算机 → 回收站 → 网络 → 配置中心 → 网络连接），其余图标按名称升序自动填充剩余格子。`AllSticky=false`，所以只有这六个是钉住的，新图标不会打乱顺序。
- 用户固定四个图标：`DesktopShortcuts=Home,Computer,Network,Trash`。
- `z96a-desktop-shortcut --all` 在构建时把可见应用复制到 `~/Desktop`，排除会话动作、控制中心子页、Fcitx 迁移向导及已有 Z96A 快捷方式。
- 安装五个固定启动器：浏览器、配置中心、文件管理器、终端、网络连接；图标使用主题图标名，构建时做通用图标映射（见 `MEMORY.md`）。
- `z96a-desktop-trust` 在 PCManFM-Qt 加载桌面前写入 GVFS `metadata::trust`，并带 `--watch`（inotify）自动信任新复制的 `.desktop`；单实例、约 1MB PSS。
- PCManFM-Qt profile：`FallbackIconThemeName=Papirus`、`SingleClick=false`、`QuickExec=true`、`UseTrash=false`，双击直接运行无确认框；
- PCManFM-Qt 的 `Terminal=qterminal`，桌面右键“在终端中打开”直接使用 QTerminal（不再落到已卸载的 `xterm`）。右键删除项为“删除”（永久删除，仍有确认框）。因 `UseTrash=false` 时 PCManFM-Qt 不再生成回收站图标，镜像在 `~/Desktop` 预置静态 `trash-can.desktop`，保证四个图标齐全。
- “网络”特殊图标由 libfm-qt 固定使用 `folder-network`；Windows-10/Windows-7 主题内已用 `network-workgroup` 补齐该名称，避免显示成普通文件夹。
- mpv 与 Thorium 桌面图标保留应用原图标（`mpv`、`thorium-browser`），不做通用图标映射。

## 5. 终端 / 输入法 / 媒体

- 仅 `qterminal`；显式 `qterminal.ini`：`fontFamily=Noto Sans Mono CJK SC`、`fontSize=14`（否则 Ctrl+0 会回到极小字号）。
- Fcitx5 + WindInput；托盘显示，关闭悬浮工具栏与状态窗（`ui.toolbar.visible=false`、`ui.status.enabled=false`）。
- 仅 `mpv`；配置与 4K 上限见 `MEMORY.md` / `references/MPV-X11-4K-HEVC.md`。
- 系统语言 `zh_CN.UTF-8`；Qt6/LXQt 语言包齐全，应用逐项状态见 `references/APP-LANGUAGE.md`。

## 6. 音量 / 亮度 / OSD

- 音量键直接绑定 `z96a-hotkey volume-up|down`；显示 0 = 静音，1–100 → raw 178–255（曲线见 `MEMORY.md`）。
- 亮度直接读写 sysfs，最低 5%、步进 5%。
- 级别持久化到 `~/.local/state/z96a/`，会话启动 `restore-hardware`。
- `z96a-volume-feedback` 监听 `amixer -c rk817ext events`，播放预览音并触发 OSD；OSD 原地更新，最后一次变化 1.2 秒后隐藏。
- 不要恢复轮询 `amixer` 的旧实现。

## 7. 窗口贴边（`z96a-window-tile`）

- 由 IceWM 时期的 `z96a-icewm-tile` 改为 Openbox/EWMH 实现，安装为 `/usr/local/bin/z96a-window-tile`。
- `Super+Left/Right/Up/Down` 半屏并组合成四角；到屏幕边缘再按会移到相邻显示器并翻转方向。
- `Super+Page_Up` 最大化、`Super+Page_Down` 最小化、`Super+Backspace` 还原；上半屏再按 Up 最大化，下半屏再按 Down 最小化。
- 处理 `_NET_FRAME_EXTENTS`、`WM_NORMAL_HINTS` gravity、跨显示器、窗口签名与残留状态清理；`.84` 已验证半屏/四角/还原/最大化/最小化。

## 8. 电源策略与锁屏

守护进程 `z96a-power-policy`（C，`flock` 单实例，RSS 约 6MB），不依赖 UPower/TLP/xss-lock。

| 供电 | 调暗 | 锁屏 | 自动挂起 |
|---|---:|---:|---:|
| AC | 5 分钟 | 10 分钟 | 30 分钟 |
| 电池 | 2 分钟 | 5 分钟 | 15 分钟 |

- 低于 30% 禁止自动挂起；30% 通知；20% 弹 GTK 倒计时（60 秒）执行有序关机，可选“强制继续”并在接电后清除 override；Hibernate 未启用。
- 电池在位由 SARADC ch4 NTC 判断，未接时显示 absent，不误报 OSD 电量。
- 锁屏统一入口 `z96a-lock` → `slimlock`；F1、手动锁屏、自动锁屏都走它，失败明确报错，不回退其他锁屏。
- slimlock 显示电量、充放电、挂起倒计时，并提供音量/亮度/关机/睡眠/重启按钮，所有电源动作二次确认；先取键盘+指针 grab 再发 `lock-ready`。
- polkit 仅允许本地活动 `user` 请求 suspend/poweroff。
- 托盘“电源设置”可分别设置 AC/电池的关屏、自动挂起、空闲关机；自动挂起与空闲关机互斥，默认关闭；配置经 `--check-config` 校验后原子写入并热生效。
- 锁屏入口配置在 `~/.config/lxqt/session.conf` 的 `lock_command=/usr/local/bin/z96a-lock`，避免 LXQt 默认的 `xdg-screensaver lock` 找不到锁屏器。
- 电源键：`lxqt-powermanagement.conf` 设 `powerKeyAction=6`（`PowerShowLeaveDialog`），并在 `~/.config/lxqt/power.conf` 写 `showLeaveDialogCommand=/usr/local/bin/z96a-power-menu`。菜单只有 锁屏/挂起/关机/重启 四项，不直接关机或挂起。
- LXQt 2.1.0 在本镜像上请求 logind `Inhibit(handle-power-key)` 被 polkit 拒绝（`AccessDenied`），因此 elogind 的 `HandlePowerKey`/`HandleSuspendKey` 继续保持 `ignore`，由 `lxqt-globalkeys` 的全局快捷键处理，避免按一次键触发两次动作。
- `z96a-power-policy --daemon` 现在由 `z96a-lxqt-services` 启动（此前 README 说只在 IceWM 会话启动；IceWM 移除后遗漏），负责写 `/run/user/<uid>/z96a-power/status` 并给 slimlock 提供电量/供电/倒计时数据。
- 锁屏顶部“挂起已禁用”只表示自动挂起倒计时关闭（`SUSPEND_REMAINING=-1`），不是手动挂起不可用；手动挂起已恢复。
- 不要在 SSH 里直接重启 `lxqt-powermanagement`：新进程会属于非活动 SSH 会话，polkit 会把 suspend 当成需要认证，菜单/锁屏的“挂起”随后会静默失败。必须在 LXQt 会话内重启或正常重新登录。
- **当前安全状态**：自动挂起与合盖挂起仍关闭（`AutoSuspendEnabled=false`、`HandleLidSwitch=ignore`），系统 idle 走 `ignore`；手动锁屏、调暗、DPMS 可用；手动挂起已按用户要求恢复（菜单与 `lxqt-leave --suspend`），但 P0 挂起/唤醒缺陷仍未修复。

## 9. 备份与回滚

- 设备预改备份：`/root/z96a-lxqt-rollback-20261101`（LXQt/autostart/elogind/快捷键）。
- 主题切换自带快照，`z96a-theme restore` 可回退。
- IceWM 已移除，回滚目标是上一版 LXQt/Openbox 状态，不是 IceWM。
