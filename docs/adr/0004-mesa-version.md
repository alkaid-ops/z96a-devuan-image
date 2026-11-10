# 0004-mesa-version.md — Mesa 使用 excalibur-backports 26.1.x

- 状态：已采纳
- 日期：2026-11-09
- 范围：z96a-v2（当前唯一板卡）

## 背景

PanVK 在 Bifrost v7 上需要 Mesa ≥ 26.1；同时旧隔离测试显示 26.1.6 的 4K 视频丢帧比 25 更多。

## 决策

构建时从 `excalibur-backports` 安装 Mesa 26.1.x，记录实际版本到 `/etc/z96a/mesa-version` 并写入 manifest；
`MESA_BACKPORTS_PIN` 可钉住精确版本。

## 后果

Vulkan/OxideTerm 可用；视频基线需在 26.1.6 上重新采集；
若未来视频回退不可接受，需要重新评估“Vulkan 优先”还是“视频优先”。
