# 0001-devuan-sysvinit.md — 使用 Devuan 6 + sysvinit + elogind

- 状态：已采纳（既有事实）
- 日期：2026-11-09
- 范围：z96a-v2（当前唯一板卡）

## 背景

项目要求不使用 systemd，同时需要会话与电源管理（logind 接口）。

## 决策

选择 Devuan excalibur（sysvinit）作为基础发行版，用 elogind 提供 logind 接口；不引入 systemd 组件。

## 后果

电源/会话能力依赖 elogind；所有服务需 sysvinit 兼容写法（`/etc/init.d` + `update-rc.d`）；
不能使用 systemd-only 工具（`systemctl`、`systemd-analyze`）。
