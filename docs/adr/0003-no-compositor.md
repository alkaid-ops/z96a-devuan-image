# 0003-no-compositor.md — 不启用合成器

- 状态：已采纳（实测）
- 日期：2026-11-09
- 范围：z96a-v2（当前唯一板卡）

## 背景

希望获得 Win10 风格阴影/透明，需要判断是否引入 picom。实测结果见 `boards/z96a-v2/docs/MEMORY.md`。

## 决策

保持无合成器。picom 的 EGL/GLX 后端在 Panfrost + Mesa 25/26 上直接初始化失败；
XRender 后端可运行但菜单延迟 +19%、4K 播放丢帧 +9%，无收益。

## 后果

无窗口透明/阴影；Win10 观感通过壁纸、面板渐变、qss 与 Openbox 主题实现；
任何“加合成器”的提议都必须先复跑 `boards/z96a-v2/tools/lxqt_perf.py`。
