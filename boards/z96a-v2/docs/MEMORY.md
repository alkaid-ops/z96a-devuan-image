# Z96A 已验证事实（改之前先看）

最后更新：2026-11-09。以下都在 `.84` 实机验证过，不是推测。

## 测试机

- `user@192.168.31.84`，密码 `[local-only]`；root 同。
- Devuan 6 Excalibur，LXQt 2.1.4，Openbox 3.6.1，SLiM，X11 `:0.0`。
- 1920×1080，`Xft.dpi: 144`（面板/图标尺寸按 1.5 倍缩放）。
- 内核 7.2.12，**Mesa 26.1.6（excalibur-backports）**，GPU `Mali-G52 r1 MC1 (Panfrost)`，OpenGL 3.1，DRI3 + Present 可用。
- Vulkan：PanVK 可用（`PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`，已写 `/etc/environment`）。
  Mesa 对 Bifrost 恒定上报 `conformanceVersion=0.0.0.0`，靠
  `/usr/share/vulkan/implicit_layer.d/VkLayer_conformance.json` 抬到 1.3.0.0，
  否则 wgpu 会把 PanVK 判为非合规并隐藏。隐式层 manifest 必须带
  `disable_environment`，否则新版 loader 直接跳过该层。详见 `references/VULKAN-PANVK.md`。
- 升级 Mesa 到 26.1.6 会影响视频呈现（旧隔离测试 4K 丢帧 313 vs 244），系统基线已变，视频需重新测。
- **backports 的 Mesa 不会自动升级**：`excalibur-backports` 优先级 100 低于 main 的 500，
  `apt-get -t` 对已安装包无效，必须用 `Pin: release n=excalibur-backports` + `Pin-Priority: 900`。
  否则镜像里仍是 25.0.7，PanVK/OxideTerm 不可用（2026-11-09 首次完整构建踩到）。

## GPU / 合成器

**当前配置：无合成器。这是有意选择，不要再加。**

| 项目 | 无合成器 | picom XRender |
|---|---:|---:|
| Xorg 空闲 CPU | 0.13% | 0.33% |
| 面板空闲 CPU | 0.27% | 0.20% |
| picom 空闲 CPU | — | 0.0% |
| picom 内存 | — | PSS 1.9MB / RSS 5.7MB |
| 打开 qterminal | 1152ms | 1154ms |
| 开始菜单弹出 | 342ms | 408ms（+19%） |
| 4K HEVC 丢帧（8.3s） | 298 | 324（+9%） |
| 4K 播放平均 GPU 频率 | 619MHz | 752MHz（+21%） |
| 4K 播放 mpv CPU | 62.7% | 60.7% |

- **picom GPU 后端不可用**（12.5 实测）：
  - `--backend egl` → `Failed to create window shaders` / `Failed to setup OpenGL`，退出。
  - `--backend glx` → `X error 167 GLX_BAD_FB_CONFIG` / `Failed to get GLX context`，断言崩溃。
- `xrender` 能跑，但 `x11perf` scroll/copy 数字变高（192→370、190→344 /s）只是画到离屏 pixmap，不代表上屏更快。
- 复测脚本：`../tools/lxqt_perf.py`（板端 `python3 lxqt_perf.py <mode>`，需手动启停 picom）。

## ArtCraft / wgpu 应用（DeckCraft / GridCraft / WordCraft）

- 这三个应用按 wgpu 默认 limits 申请设备，其中 `max_texture_dimension_3d = 2048`；PanVK（Mesa 26.1.6，Mali-G52）只暴露 **512**，于是设备创建失败、进程启动即退出：
  `WGPU error: Limit 'max_texture_dimension_3d' value 2048 is better than allowed 512`
- 触发条件：`/etc/environment` 里的 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` 让 wgpu 选中 PanVK。该变量不能删（mpv/OxideTerm 需要 PanVK 硬件 Vulkan）。去掉变量时 wgpu 会落到 lavapipe（`libvulkan_lvp`，软件渲染，能开但很慢），**这不是修法**。
- 修法：`/usr/local/bin/{deckcraft,gridcraft,wordcraft}` 包一层 `WGPU_BACKEND=gl`，改走 Panfrost OpenGL ES（硬件加速）。桌面项是 `Exec=deckcraft %F` 按名字查找，而 LXQt 会话 PATH 首位是 `/usr/local/bin`，所以双击图标也被覆盖。
- 验证：GL 路径下 `/proc/<pid>/maps` 只有 `libEGL`、没有 `libvulkan`；DeckCraft 窗口标题 `DeckCraft`，GridCraft 新建表格标题 `Book1`。
- OxideTerm 不受影响（它能在 PanVK 上正常创建设备）。

## 充电输入、LED 与电池

- Z96A 两颗 LED 分工：`white:power`（Caps Lock 旁）是**系统运行灯**，应 `default-on` 常亮；`red:charging`/`green:charging`（C 口）是充电灯，由 `z96a-charge-led` 按 `online` + 电量控制（充电红、≥90% 绿、离线灭）。不要把 `white:power` 绑到 `bq257xx-charger-online`，否则充电器状态抖动会让系统灯闪。
- bq257xx/SC8886S 的 VINDPM 由芯片按 `VBUS-1.28V` 自动设置，**不要强行写 15V**（VBUS 低于 15V 时会让充电器停止取电）。拔插后要重新检测时使用 `BQ25703_CHARGE_OPTION_4`(0x35) 的 `RESET_VINDPM`(bit5)，不要把一次边沿重检测扩展成离线轮询。
- `0012-bq257xx-input-reset.patch` 只在 **AC 插入边沿**调用一次 `RESET_VINDPM`，并重写充电参数；不在离线时轮询/反复 reset，避免 IRQ 风暴时反复重启 converter。`0013-z96a-led-system-indicator.patch` 把 `white:power` 改成 `default-on`。
- **2026-11-10 充电器 A/B 复核**：正常充电器插回后稳定为 `online=1 / Charging`，实测约 704 mA；SC8886 `0x21=0x84`、VBUS ADC `0xB5`。同一线材和方向的旧充电器会产生 `online=1→0` 周期抖动，SC8886 `AC_STAT` 反复出现/消失，失败时 VBUS ADC `0x00`，IRQ 在短时间内由 78 增长到 116。
- 同一 A/B 中 HUSB311 的 `POWER_STATUS=0x08`、`CC_STATUS=0x20/0x30`、`ROLE_CONTROL=0x55` 在好坏充电器下基本一致，TCPM `online=0`、IRQ 始终为 0。因此 **HUSB311/CC 协商不是本次输入故障的直接故障层**；异常发生在 SC8886 的输入检测/VBUS 路径或充电器侧。
- 不要再部署 `bq257xx` 离线有限重试、运行时重绑定、恢复服务或插座自动断电脚本。它们不能稳定修复周期性掉电的输入，只会掩盖外部供电故障。`0014-bq257xx-bounded-recovery.patch` 已移除。
- 已知旧充电器应停用；若要把范围继续缩到“充电器本体”还是“自带线/插头”，需要换线 A/B 或对适配器输出/VBUS 实测。不要再把旧的“QC 芯片锁死、只能断电池”结论当作已验证事实。

## 会话 / 开始菜单

- 开始菜单必须有 `XDG_MENU_PREFIX=lxqt-`
- LXQt 电源动作枚举：`PowerLogout=0`、`PowerHibernate=1`、`PowerReboot=2`、`PowerShutdown=3`、`PowerSuspend=4`、`PowerMonitorOff=5`、`PowerShowLeaveDialog=6`；锁屏是 `-2`，无动作是 `-1`。
- 本镜像上 LXQt powermanager 的 logind `Inhibit(handle-power-key/handle-suspend-key)` 被 polkit 拒绝（`AccessDenied`），所以 elogind 必须保持 `HandlePowerKey=ignore`、`HandleSuspendKey=ignore`，否则电源键会同时被 elogind 和 LXQt 处理。
- 电源键打开 `z96a-power-menu`（`powerKeyAction=6` + `~/.config/lxqt/power.conf` 的 `showLeaveDialogCommand`）；锁屏命令在 `~/.config/lxqt/session.conf` 的 `lock_command=/usr/local/bin/z96a-lock`。
- 从 SSH 直接重启 `lxqt-powermanagement` 会让它落在非活动的 SSH 会话（`pkcheck` 返回需要认证），于是菜单/锁屏的“挂起”会静默失败。必须在 LXQt 会话内重启（注销重登、重启，或从会话内启动器拉起）；正常开机的 autostart 路径是正确的。
- slimlock 顶部“挂起已禁用”只对应状态文件里的 `SUSPEND_REMAINING=-1`（自动挂起关闭）；手动挂起仍可用。把 `SUSPEND_REMAINING` 设为正数时同一位置显示“挂起 mm:ss”。
- `z96a-power-policy --daemon` 必须在 LXQt 会话启动（`z96a-lxqt-services`）；不启动时 slimlock 顶部显示“电源未知 · 电池状态未知”，且 `SUSPEND_REMAINING=-1` 显示“挂起已禁用”。
- 开始菜单电源项：删除 `lxqt-hibernate.desktop`、`lxqt-leave.desktop`、`lxqt-logout.desktop` 后只剩锁屏/挂起/关机/重启；顺序由 `/etc/xdg/menus/lxqt-applications.menu` 决定——X-Leave 和 Screensaver 要设为 `inline="true"`（Screensaver 在前），并在 X-Leave 菜单里加 `<Layout>` 指定 suspend→shutdown→reboot。改完必须重启 `lxqt-panel`。，否则按钮点了没反应（找不到 `applications.menu`）。
  已写入 `~/.xinitrc`、`/etc/environment`，并加 `/etc/xdg/menus/applications.menu → lxqt-applications.menu` 兜底。
- `z96a-theme` 重启面板时会 `setdefault` 该变量，从裸 shell 手动重启也不会坏。

## 主题系统（`z96a-theme`）

- 四个 profile：`windows7` / `windows10` / `windows11` / `macos`。
- LXQt 启动 Openbox **不带 `--config-file`**，实际读 `~/.config/openbox/rc.xml`（不是 `lxqt-rc.xml`）。
- 生成 `rc.xml` 必须：以 `/etc/xdg/openbox/rc.xml` 为模板（空文件会丢鼠标绑定）；去掉 XML 命名空间（`ns0:` 会让 Openbox 忽略配置）；写 `<desktops><number>1</number></desktops>`。
- `~/.cache/openbox/sessions` 会覆盖桌面数量，构建时删除。
- 切换前先停 `lxqt-panel` 和 `pcmanfm-qt`，否则它们退出时回写旧配置。
- 资产：壁纸 `/usr/share/z96a/wallpapers/{windows7,windows10,windows11,macos}.png`；任务栏渐变 `/usr/share/z96a/panel/{windows7,windows10}.png`；开始标志 `/usr/share/z96a/icons/{start-orb.png,start-win10.png}`；图标主题 `/usr/share/icons/{Windows-7,Windows-10}`（B00merang）。
- `Z96A-Win7` / `Z96A-Win10` LXQt 主题由 `uscripts` 从 `ambiance` 复制、替换开始图标并追加 qss。
- 面板尺寸（logical）：Win7 `50/30/170`；Win10 `40/24/170`；Win11 `42/32/200`；macOS `36/28/190`。
  Win10 的 44px 纯图标按钮试过，用户不喜欢，已回退；任务按钮保留图标+文字。

## 桌面图标

- 图标尺寸必须 **47**（≥48 时 libfm-qt 悬停会在左上角画“+”选择角）。
- 桌面固定顺序：`~/.config/pcmanfm-qt/z96a/desktop-items-0.conf` 只放 6 个自定义位置（user-home、computer、trash-can、network、z96a-control-center、z96a-network），坐标按逻辑像素网格 **90×93**、起点 **(12,12)** 排列；`settings.conf` 需 `SortColumn=name`、`SortOrder=ascending`、`AllSticky=false`。改图标尺寸/字体/单元格边距后必须重算这些坐标，否则 `alignToGrid` 会把图标吸附到错误格子。
- `DesktopCellMargins=@Size(4 0)`；桌面字体 `DejaVu Sans 9`（libfm-qt 用 `averageCharWidth*13` 算格宽，CJK 字体在 144dpi 下会把格子撑到约两倍）。
- `ShadowColor=#80000000`（纯黑会变成文字后的黑块）。
- `DesktopShortcuts=Home,Computer,Network,Trash`（用户要求的四个图标，别删）。
- 信任：`z96a-desktop-trust` 启动时全量 + `--watch` 用 inotifywait 监听新复制的 `.desktop`。
- 需要 `qt6-svg-plugins`，否则开始菜单/部分 SVG 图标空白。
- 右键菜单的删除项由 `UseTrash` 决定（libfm-qt 只有一个 `deleteAction_`）：`UseTrash=true` 显示“移至回收站”，`UseTrash=false` 显示“删除”（永久）。本镜像 profile 设为 `UseTrash=false`，因此右键是“删除”。桌面 `Delete` 键同样永久删除，`Shift+Delete` 行为相同。主目录/计算机/网络/回收站是虚拟项，不可删除，由 `DesktopShortcuts` 控制。
- `UseTrash=false` 时 PCManFM-Qt 不再自动生成回收站图标，所以镜像在 `~/Desktop` 预置静态 `trash-can.desktop`（`Exec=pcmanfm-qt trash:///`，无动态计数）。
- “网络”特殊图标由 libfm-qt 固定使用 `folder-network`；Windows 主题原本没有该名称，会回退成普通文件夹。已在 `Windows-10` / `Windows-7` 图标主题内用 `network-workgroup` 补齐 `folder-network`。
- 图标映射（构建时由 uscripts 套用）：Geany→`accessories-text-editor`，htop→`utilities-system-monitor`，mc→`system-file-manager`，mcedit→`accessories-text-editor`，Xarchiver→`file-roller`，Geeqie→`image-x-generic`，Flameshot→`applets-screenshooter`；配置中心→`preferences-system`。**mpv 和 Thorium 保留应用原图标**（`mpv`、`thorium-browser`）。

## 时钟

- 世界时钟高级格式：`customFormat=M月d日 ddd HH:mm:ss`，效果 `11月9日 周一 10:15:09`。四个 profile 均已写入。
- 面板系统监控插件 `z96a-sysmon`：CPU/内存 + 上传/下载两行显示，13px，2 秒采样，读取 `/proc`，运行在 `lxqt-panel` 进程内，无额外进程；四个 profile 中位于挂载与时钟之间。

## 音频 / 亮度

- RK817 按卡名 `rk817ext` 解析，不写死卡号（HDMI/es7202 卡号会变）。
- **外放路由（2026-11-12 实测）**：外置功放输入取自 codec 的**耳机输出**（DTS routing：`Speaker Amp INL <- HPOL`、`Internal Speakers <- Speaker Amp OUTL`）。因此 `Playback Mux` 必须保持 **HP**；设为 **SPK** 会让功放断电（`GPIO3_A6 enable` 变低），表现为 mpv/浏览器/音量提示音**全系统无声**。`Internal Speakers` pin-switch 控制外放静音，插耳机时关。开机由 `/usr/local/bin/z96a-audio-mux`（init `z96a-audio-mux`）保证 `Mux=HP` 并按耳机检测联动开关。
- 音量曲线（`z96a-hotkey`）：显示 0 = raw 0（静音）；显示 1–100 线性映射到 raw **178–255**（安全上限默认 255，可听下限为上限的 70%；`Z96A_VOLUME_MAX_LEVEL` / `Z96A_VOLUME_AUDIBLE_MIN` 可覆盖）。
- 亮度：直接读写 `/sys/class/backlight/backlight`；最低 5%，步进 5%。
- 持久化：`~/.local/state/z96a/{volume-level,brightness-level}`，会话启动 `z96a-hotkey restore-hardware`。
- OSD 复用 `z96a-system-tray --osd`；`z96a-volume-feedback` 监听 mixer 变化。
- 电池图标：`z96a-system-tray` 默认 `BATTERY_DEVICE=/sys/class/power_supply/rk817-battery`；LXQt 自带 battery watcher 保持关闭，避免重复图标。
- 不要再用轮询 `amixer` 的旧实现（曾把 ALSA 控制接口堵死）。

## 终端 / 网络 / 输入法 / 媒体

- PCManFM-Qt 的 `Terminal` 必须显式设为 `qterminal`；默认值是 `xterm`，而镜像已卸载 xterm，桌面右键“在终端中打开”会报错。
- 终端只留 `qterminal`（PSS 13.5MB，低于 lxterminal 19.7MB）；`x-terminal-emulator` 指向 qterminal；`z96a-hotkey mixer` 用 `qterminal -e alsamixer`。
- 托盘网络用 `nm-tray`（`nm-tray-l10n`），不装 `nm-applet`/`network-manager-gnome`；完整编辑用 `nm-connection-editor`。
- 输入法：Fcitx5 + WindInput（`windinput`）；`~/.config/WindInput/config.toml` 里 `ui.toolbar.visible=false`、`ui.status.enabled=false`，只在托盘显示。
- 媒体只留 `mpv`，配置 `hwdec=v4l2request` / `vo=gpu` / `gpu-context=x11egl` / `gpu-dumb-mode=yes` / `dither=no`。1080p60 达标；4K60 HEVC 约 40fps（X11/GPU 合成上限，不是解码问题，详见 `references/MPV-X11-4K-HEVC.md`）。
- DeckCraft 上游无中文界面（0.16.0 仍如此），只能等上游，不要再去调 locale。

## 内存 / swap

- **只用 zram，不用磁盘 swap**：`/etc/fstab` 不生成 swap 项；`zram-tools` 以 `PERCENT=50`、`ALGO=lz4`、`PRIORITY=100` 建 zram（3.8 GiB 板约 1.9 GiB，符合“4 GiB 板最多 2 GiB”的上限）。
- `vm.swappiness = 30`（`/etc/sysctl.d/99-zram.conf`），尽量减少 A55 上的压缩开销。
- 内核 `CONFIG_CRYPTO_LZ4=y`、`CONFIG_ZRAM_BACKEND_LZ4=y`，defconfig 默认压缩器已改为 `lz4`；但本内核树的 `/proc/crypto` 只注册了通用 `lz4-scomp`，**没有 arch/arm64 专用 LZ4 加速实现**，如需真正的 NEON/ARM64 优化需另加内核补丁或换基线（未经确认不要动内核）。

## 已知坑

- 运行中的 `pcmanfm-qt` / `lxqt-panel` 退出时会回写配置；改配置先停进程。
- Openbox 配置不能带 XML 命名空间；开始菜单依赖 `XDG_MENU_PREFIX`。
- 桌面图标 ≥48px 会出现“+”选择角。
- `.84` 的 `ffmpeg` 无 `x11grab`，截图用 `xwd` + `netpbm`。
- 从 SSH 手动重启 `pcmanfm-qt` 时必须带上 LXQt 会话环境（尤其 `DBUS_SESSION_BUS_ADDRESS`、`XDG_RUNTIME_DIR`），否则读不到 GVFS 信任信息，桌面图标会全部出现黄色感叹号。
- 改动落在 overlay：`files/rootfs-overlay/z96a-v2/...` 和 `boards/z96a-v2/userscripts/uscripts`。

## 回归基线（阶段 0）

- 快照：`../tests/baseline.json`，用 `../tests/smoke-device.sh --save` 重新采集。
- 2026-11-09 采集值：kernel 7.2.12、Mesa 26.1.6、renderer `Mali-G52 r1 MC1 (Panfrost)`、Vulkan conformance 1.3.0.0、显示 1920×1080@60.02、eth0/wlan0 up、MemAvailable ≈2.72GB、lxqt-panel PSS ≈23.7MB、pcmanfm-qt PSS ≈28.1MB。
- 改动前跑 `../tests/smoke-static.sh`；动桌面/GPU/视频后再跑 `../tests/smoke-device.sh`，指标明显偏离即为回归。
