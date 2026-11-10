# Z96A 桌面应用中文支持报告

日期：2026-11-09  
系统：Devuan 6 / LXQt 2.1 / X11  
系统语言：`LANG=zh_CN.UTF-8`、`LANGUAGE=zh_CN:zh`

## 已设置或确认支持中文

| 应用 | 中文来源 | 状态 |
|---|---|---|
| LXQt 面板、配置中心、会话、电源管理、通知、快捷键、策略代理 | `qt6-translations-l10n` + 对应 `lxqt-*-l10n` | 中文 |
| PCManFM-Qt | `libfm-qt-l10n`、`pcmanfm-qt-l10n` | 中文 |
| QTerminal | `qterminal-l10n`、Qt6 中文翻译 | 中文 |
| Openbox 设置（obconf-qt） | `obconf-qt-l10n` | 中文 |
| nm-tray / 网络连接编辑器 | `nm-tray-l10n`、`nm-applet.mo` | 中文 |
| GridCraft | 应用内 `language=zh` | 中文 |
| WordCraft | 应用内 `language=zh-CN`（也可自动跟随系统） | 中文 |
| OxideTerm | 应用内 `language=zh-CN` | 中文 |
| Thorium 浏览器 | 启动参数 `--lang=zh-CN`，自带 `zh-CN.pak` | 中文 |
| Geany | gettext `geany.mo` | 中文 |
| Geeqie | gettext `geeqie.mo` | 中文 |
| Xarchiver | gettext `xarchiver.mo` | 中文 |
| Flameshot | 自带 `Internationalization_zh_CN.qm` | 中文 |
| Fcitx5 / 输入法配置 | `fcitx5.mo`、Fcitx5 Qt 翻译 | 中文 |
| im-config | `im-config.mo` | 中文 |
| Midnight Commander / mcedit | `mc.mo` | 中文 |
| 清风输入法（WindInput）设置/导入 | 应用自带中文 | 中文 |
| 微信、QQ | 应用自带中文 | 中文 |

## 无中文界面（需要上游支持）

| 应用 | 现状 | 说明 |
|---|---|---|
| DeckCraft | 仅英文 | 二进制内没有中文界面字符串；配置文件也没有可用的界面语言项。属于 ArtCraft 系列中唯一没有中文本地化的应用。 |
| htop | 仅英文 | Debian 包未提供 `zh_CN` gettext 目录，界面没有中文。 |
| mpv | 仅英文 | mpv 的快捷键/OSD/菜单没有中文翻译；播放本身正常。 |
| Vim | 仅英文 | `vim-runtime` 没有中文消息目录，命令与提示为英文。 |

## 说明

- 系统级语言已统一为 `zh_CN.UTF-8`，Qt5、Qt6、LXQt、GTK 应用在重启后会加载中文翻译。
- Thorium 使用 `/usr/local/bin/z96a-thorium` 启动，已经固定加上 `--lang=zh-CN`。
- GridCraft、WordCraft、OxideTerm 的语言设置写入各自用户配置；重装或恢复默认配置后需要重新选择中文。
- DeckCraft、htop、mpv、Vim 这四个应用需要上游提供中文翻译；当前无法通过系统配置实现中文界面。
