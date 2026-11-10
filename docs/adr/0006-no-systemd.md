# 0006-no-systemd.md — 不引入 systemd 生态

- 状态：已采纳
- 日期：2026-11-09
- 范围：z96a-v2（当前唯一板卡）

## 背景

Devuan 基础 + sysvinit；部分上游软件包默认依赖 systemd 组件。

## 决策

不安装 systemd、systemd-logind、SDDM、Plasma/KWin、PulseAudio；不升级 LXQt 依赖栈。

## 后果

依赖闭包检查需持续排除 systemd（阶段 1 的 CI 项）；
引入新组件时必须先确认其 systemd 依赖可被 elogind/替代方案满足。
