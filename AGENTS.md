# 项目入口（给 agent / 新对话）

本仓库源自 `debian-image-builder`，但**已经与上游解耦、自成一体**：
不再以兼容上游路径或方便合并上游为目标。当前维护 Sunniwell Z96A（RK3568）的
Devuan 6 桌面镜像，并按多板卡方式组织：**板级内容集中在 `boards/<board>/`，
镜像文件位于 `files/rootfs-overlay/<board>/`**。

**先读本文；然后只打开当前板卡目录下需要的那一篇，不要通读全部。**

## 与上游的关系（重要）

- 本仓库是独立项目。上游 `debian-image-builder` 的文档/路径只作参考，不作为兼容约束。
- 根文件系统板级目录使用 **`files/rootfs-overlay/<board>/`**。
  上游的 `files/bsp/<board>/` 已废弃，**不要恢复、不要建兼容符号链接**。
- 板级定制脚本使用 **`boards/<board>/userscripts/uscripts`**；
  通用入口 `files/userscripts/uscripts` 只负责分发。
- 新增/调整路径时，直接改本仓库的 `lib/`、`docs/`、`boards/`，不必考虑上游能否接受。
- 文档中的“上游”仅表示历史来源，不代表需要保持同步。

## 当前板卡

| 项 | 值 |
|---|---|
| 板卡 ID | `z96a-v2` |
| 板级目录 | `boards/z96a-v2/` |
| 构建入口 | `lib/boards/z96a-v2`、`defconfig/z96a-v2_defconfig`、`files/rootfs-overlay/z96a-v2/` |
| 系统 | Devuan 6 Excalibur / arm64 / sysvinit + elogind |
| 桌面 | LXQt 2.1.4 + Openbox 3.6.1 + SLiM（X11，**不是** Wayland） |
| GPU | Mali-G52 r1（Panfrost），Mesa 26.1.6，`Xft.dpi=144` |
| 测试机 | `user@192.168.31.84`，密码 `[local-only]`（root 同） |
| 构建机 | `hsy@192.168.31.132` |

## 文档地图

### 全局

| 文档 | 用途 |
|---|---|
| `docs/README.md` | 文档索引与维护规则 |
| `docs/BOARD-GUIDE.md` | **新增板卡的标准流程**（必读） |
| `docs/OPTIMIZATION.md` | **正式工程化方案**（阶段 0–4，执行前必读） |
| `docs/CI-RELEASE.md` | **GitHub Actions**：Tag 自动构建、缓存与发布门禁 |
| `docs/adr/` | 架构决策记录（X11、无合成器、Mesa、V4L2、无 systemd） |
| `boards/README.md` | 板级目录约定 |

### Z96A 板级（`boards/z96a-v2/`）

| 文档 | 用途 | 什么时候看 |
|---|---|---|
| `boards/z96a-v2/docs/MEMORY.md` | 已验证事实、踩坑、实测数据 | **改任何东西之前先看** |
| `boards/z96a-v2/docs/HARDWARE-STATUS.md` | 硬件驱动、DTS/补丁、待验证项 | 动内核/驱动/DTS 时 |
| `boards/z96a-v2/docs/DESKTOP.md` | LXQt 桌面、主题、图标、面板、电源与锁屏 | 改桌面/主题/快捷键时 |
| `boards/z96a-v2/docs/TODO.md` | 当前未完成待办 | 接任务前确认现状 |
| `boards/z96a-v2/docs/references/MPV-X11-4K-HEVC.md` | 视频硬解/呈现实测 | 动 mpv/播放时 |
| `boards/z96a-v2/docs/references/VULKAN-PANVK.md` | PanVK / conformance layer / wgpu | 动 GPU/Vulkan/OxideTerm/LocalSend 时 |
| `boards/z96a-v2/docs/references/APP-LANGUAGE.md` | 应用中文支持 | 动本地化时 |
| `README.md` | 早期上游说明（仅供参考，不再要求同步） | 构建参数 |

## 目录约定

```
boards/<board>/
├── README.md                 板卡总览与构建输入映射
├── docs/                     板级文档
├── userscripts/uscripts      板级镜像定制（run_function0..3）
├── tools/                    板级开发/测试工具
├── tests/                    板级测试
└── power-policy/             板级守护进程源码（如适用）
```

构建输入位置（本仓库约定）：`lib/boards/<board>`、`defconfig/<board>_defconfig`、
`files/rootfs-overlay/<board>/`、`patches/git/<board>/`。新增板卡见 `docs/BOARD-GUIDE.md`。

## 硬性约束

- 保持 Devuan 6 / LXQt 2.1.x / X11 / Openbox / SLiM。
- 不引入 systemd、SDDM、Plasma/KWin、PulseAudio；不升级 LXQt 依赖栈。
- 不做 Wayland 双会话（已明确放弃，历史方案已删除）。
- 不未经确认修改 eMMC / U-Boot / GPT / 内核 / DTB，不重新打包或刷机。
- 所有镜像改动必须落在 overlay：`files/rootfs-overlay/<board>/...`；板级定制脚本放
  `boards/<board>/userscripts/uscripts`，不要只改设备。

## 常用验证

```sh
# 打包输入预检（构建前必跑，也由 run_function0 自动执行）
make preflight board=z96a-v2

# 恢复不在 git 里的应用 deb（校验 SHA256）
boards/z96a-v2/tools/fetch-packages.sh

# 凭据扫描
boards/z96a-v2/tools/scan-secrets.sh

# 配置生成与一致性（改 config/*.toml 后）
make board-config board=z96a-v2

# 固定构建根（容器内跑构建；镜像已本地构建过）
boards/z96a-v2/tools/build-in-container.sh preflight

# 仓库静态检查（不需要设备/镜像）
boards/z96a-v2/tests/smoke-static.sh

# 单元测试（含仓库一致性、文档链接）
python3 -m unittest discover -s boards/z96a-v2/tests -p 'test_*.py'

# 真机冒烟（SSH，只读；--save 更新基线）
boards/z96a-v2/tests/smoke-device.sh --save

# 镜像/rootfs 检查
sudo boards/z96a-v2/tests/smoke-static.sh --image output/z96a-v2/image/*.img
sudo boards/z96a-v2/tests/smoke-rootfs.sh <rootfs-dir> --chroot

bash -n files/userscripts/uscripts boards/z96a-v2/userscripts/uscripts lib/source
git diff --check
```

基线快照：`boards/z96a-v2/tests/baseline.json`。

设备截图（`.84` 的 ffmpeg 无 `x11grab`）：

```sh
xwd -root -silent > /tmp/s.xwd && xwdtopnm /tmp/s.xwd | pnmtopng > /tmp/s.png
```

## 最容易踩的坑（详见 Z96A 的 `MEMORY.md`）

- 改 `lxqt-panel` / `pcmanfm-qt` 配置前先停进程，否则退出时回写旧配置。
- Openbox 配置不能带 XML 命名空间，且 LXQt 实际读 `~/.config/openbox/rc.xml`。
- 开始菜单依赖 `XDG_MENU_PREFIX=lxqt-`。
- 桌面图标尺寸必须 47（≥48 出现“+”选择角）。
- 不要启用合成器：picom EGL/GLX 在 Panfrost 上直接失败，XRender 实测更慢。
- 从 SSH 重启 `pcmanfm-qt` 必须带 LXQt 会话的 `DBUS_SESSION_BUS_ADDRESS`。
