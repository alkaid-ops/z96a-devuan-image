# Z96A 待办

更新：2026-11-09。只保留未完成事项；已完成结论已并入 `MEMORY.md` / `DESKTOP.md` / `HARDWARE-STATUS.md`。

当前测试系统运行在 U 盘 `/dev/sda2`。**未得到用户明确确认前不重新打包、不刷机。**

## P0 挂起/唤醒缺陷（自动挂起仍禁用；手动挂起已按用户要求恢复）

- [x] 自动挂起保持关闭（`AutoSuspendEnabled=false`），禁止重新启用自动 deep/s2idle；手动挂起入口（电源菜单/`lxqt-leave --suspend`）已恢复，使用时仍需承担 P0 无法唤醒风险。
- [ ] 对比成功/失败挂起前后的状态、启动路径、外设、电池/AC、USB 与内核日志，定位间歇性触发条件。
- [ ] 用串口或 `no_console_suspend` 捕获完整 suspend/resume，检查 PMIC/RTC/PSCI、eDP、USB 与设备回调。
- [ ] 修复后至少 3 次 deep/受支持 sleep state 唤醒测试，并验证 eDP、键盘、触控板、Wi-Fi、SSH、电源策略。

## P0 SLiM / 锁屏验收

- [ ] 真机验证 slimlock 主题、5 秒熄屏、唤醒后解锁，连续三轮稳定。
- [ ] 连续三轮：锁屏 → 静置 6 秒熄屏 → 输入点亮 → 密码解锁返回原会话。
- [ ] 用实体电源键确认唤醒效果（此前只用 DPMS 模拟）。
- [ ] slimlock 异常退出时 F1 明确报错且不启动其他锁屏。
- [ ] 挂起恢复后锁屏与通知服务仍正常。
- [ ] 确认 eDP、键盘、触控板、网络、中文输入法无回退。

## P0 SSH host key

- [ ] 普通重启后确认主机密钥指纹与文件时间稳定（删除逻辑已移除）。

## P0 电源策略真机确认

- [ ] 解锁后打开托盘“电源设置”，修改并保存一个非危险时间项。
- [ ] 用户确认后测试一次真实重启与关机；睡眠按钮已恢复手动挂起，真机挂起/唤醒测试前需确认可接受无法唤醒风险。
- [ ] 用户确认后测试真实 AC 插拔、合盖/开盖、deep suspend/resume。
- [ ] 后续实现“挂起后定时唤醒再执行空闲关机”。

## P1 镜像构建同步

- [ ] 把本轮已真机验证的 overlay 变更全部纳入构建流程（含主题/图标/托盘/菜单环境）。
- [ ] 在 Devuan ARM64 目标仓库重新模拟依赖闭包，确认无 systemd、systemd-logind、Plasma、KWin 等非预期依赖。
- [ ] 确认镜像包含 `slim`（提供 `slimlock`）、`xinput`、`libnotify-bin`、`wmctrl`、`z96a-window-tile`、`inotify-tools`、`qterminal`、`qt6-svg-plugins`、`gvfs-daemons`、`network-manager-gnome`、`nm-connection-editor`；不安装 XScreensaver/Picom/Plank。
- [ ] 确认 elogind 规则忽略 `KEY_POWER`、`KEY_SLEEP`、`KEY_HIBERNATE`。
- [ ] 确认 `99-sunniwell-z96a-typec-keyboard.hwdb` 含 `KEYBOARD_KEY_700F8=pause`、Wi-Fi、触摸板映射。
- [ ] 重建镜像后复核 `Meta+Left/Right/Up/Down`、`Meta+Prior/Next/BackSpace` 全局快捷键。

## P1 启动与恢复

- [ ] 验证全新登录后 LXQt 通知服务、托盘、桌面信任 watcher 均自动启动。
- [ ] 验证挂起恢复后通知服务与 slimlock 仍可用。
- [ ] 用实体电源键验证只打开 `z96a-power-menu`（锁屏/挂起/关机/重启），不直接关机或挂起。
- [ ] 真机验证 SLiM 会话选择、LXQt/Openbox 启动/注销、桌面图标、托盘、音频/网络/输入法、锁屏与主题切换。

## P2 功能键与输入

- [ ] 实测 Print 键启动 Flameshot。
- [ ] 确认 `F12/Scroll Lock`、`Delete/Insert`、`Esc` 保持默认。
- [ ] 如需在应用内使用普通 F1–F12，确认 Fn Lock 或其他键盘模式行为。
- [ ] **BT SCO / I2S2（未来）**：vendor `bt-sco`（`delta,dfbmcs320`）+ `bt-sound`
  使用 `i2s@fe420000`；当前 `CONFIG_SND_SOC_BT_SCO` 未编译、无 `bt-sco` 节点。
  需要时再开配置 + DTS，验证蓝牙 HFP/耳机麦克风。

## P2 构建 / 维护

- [ ] 全镜像 `...7.2.12...img.xz` 只做静态校验，刷第二张 USB 做完整启动验证。
- [ ] Tsinghua `excalibur-security` 的 zlib 同步后，删除 `files/rootfs-overlay/z96a-v2/etc/apt/preferences.d/zlib1g` 并重跑 `apt upgrade`。
- [ ] yjun123 remote HEAD 再前进时，重新 fetch 并 rebase `0002-z96a-board-dts.patch` / `0008`（当前 `.cache` 为 `0211cf630`）。
- [ ] 7.2.12 稳定运行一段时间后，再决定是否移除 `/boot/recovery` 的 7.2.11 回退入口。
- [ ] vendor-only 功能（IR 遥控、MXC6655、ADC keys、BT SCO/I2S2、SPDIF、SATA1/SFC、NPU/VENC/JPEG/IEP）按需再补。

## 安全边界

- 不修改 eMMC、U-Boot、GPT、内核或 DTB，除非另建独立计划。
- 不在未备份时替换显示管理器；不未验证就重新打包/刷写。
- 硬件相关的待验证项在 `HARDWARE-STATUS.md`。
