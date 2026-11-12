# z96a-v2 视觉源文件

## Alkaid 启动动画

`alakid-boot.svg` 是 Plymouth 主题的设计源（纯 SMIL 动画，1920×1080）。

重新生成帧（需要 Node + Playwright 的 Chromium，仅在开发机使用，设备端不需要）：

```sh
# intro 0-6s
NODE_PATH=/path/to/playwright/node_modules PW_CHROME=/path/to/chromium \
node boards/z96a-v2/tools/render-svg-frames.js \
  boards/z96a-v2/assets/alakid-boot.svg /tmp/alkaid-frames 10 6

# continuation / loop source 6.1-12s
node boards/z96a-v2/tools/render-svg-range.js \
  boards/z96a-v2/assets/alakid-boot.svg /tmp/alkaid-loop 10 6.1 12

# 转 256 色索引 PNG（解码更快），按 f0000-f0060（正片）、f0061-f0119（持续段）
# 放入 boards/z96a-v2/chroot-files/theme/alkaid/
```

主题脚本只预载第 0 帧，其余在 refresh 回调逐帧解码；播放时长由
`/etc/default/z96a-anim` 的 `Z96A_ANIM_SECONDS` 控制。
