# 0002-x11-desktop.md — 桌面固定为 X11（LXQt + Openbox）

- 状态：已采纳
- 日期：2026-11-09
- 范围：z96a-v2（当前唯一板卡）

## 背景

RK3568/Panfrost 上 Wayland 方案（labwc + lxqt-wayland-session）不成熟，且 lxqt-globalkeys 仅支持 X11。

## 决策

桌面固定 X11：LXQt 2.1.x + Openbox + SLiM，不提供 Wayland 会话。

## 后果

全局快捷键、截图、窗口贴边（`z96a-window-tile`）、锁屏（slimlock）都基于 X11；
Wayland 相关方案已在历史计划中废弃，不再保留兼容层。
