# 架构决策记录（ADR）

记录关键取舍，避免未来重复讨论。

| 编号 | 决策 |
|---|---|
| [0001](0001-devuan-sysvinit.md) | Devuan + sysvinit + elogind |
| [0002](0002-x11-desktop.md) | 桌面固定 X11 |
| [0003](0003-no-compositor.md) | 不启用合成器 |
| [0004](0004-mesa-version.md) | Mesa 26.1.x（backports） |
| [0005](0005-v4l2-hardware-decoding.md) | V4L2 硬解 + X11 呈现 |
| [0006](0006-no-systemd.md) | 不引入 systemd 生态 |

新增决策时复制现有文件格式；被推翻的决策不要删除，改为“已废弃”并注明替代项。
