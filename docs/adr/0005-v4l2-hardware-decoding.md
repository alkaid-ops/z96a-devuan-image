# 0005-v4l2-hardware-decoding.md — 视频硬解走 V4L2 Request + EGL/X11

- 状态：已采纳（实测）
- 日期：2026-11-09
- 范围：z96a-v2（当前唯一板卡）

## 背景

需要 1080p60 与 4K HEVC 播放；RGA 零拷贝路线经实测不可行（该内核 RGA 不支持 DMABUF 导入）。

## 决策

mpv 使用 `hwdec=v4l2request`、`vo=gpu`、`gpu-context=x11egl`、`gpu-dumb-mode=yes`、`dither=no`；
不投入 RGA 集成，不采用 DRM/KMS 直出（与“必须在 X11 窗口内”的约束冲突）。

## 后果

1080p60 达标；4K60 HEVC 约 40fps（X11/GPU 合成上限，非解码瓶颈）；
Thorium 同样受此限制（约 32fps）。
