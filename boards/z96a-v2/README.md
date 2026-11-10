# Z96A Type-C（RK3568）

Sunniwell Z96A Type-C，RK3568B2，4GB LPDDR4X，32GB eMMC，eDP 1920×1080。
镜像：Devuan 6 Excalibur / arm64 / LXQt 2.1.4 + Openbox + SLiM（X11）。

## 构建输入（本仓库约定）

| 内容 | 路径 |
|---|---|
| 板卡变量 | `lib/boards/z96a-v2` |
| 内核 defconfig | `defconfig/z96a-v2_defconfig` |
| 根文件系统 overlay | `files/rootfs-overlay/z96a-v2/`（仅 `etc`/`home`/`opt`/`usr`） |
| git 源码补丁 | `patches/git/z96a-v2/linux-add_sunniwell_z96a/` |
| 芯片家族补丁 | `patches/rockchip/` |
| U-Boot 补丁 | `patches/uboot/` |
| 预编译 U-Boot | `files/boot/uboot/z96a-v2/` |
| 包补丁（slim/video） | `boards/z96a-v2/patches/` |

```sh
make rootfs image board=z96a-v2
```

产物在 `output/z96a-v2/`。

## 板级工作区

| 内容 | 路径 |
|---|---|
| 已验证事实 / 踩坑 | [`docs/MEMORY.md`](docs/MEMORY.md) |
| 硬件驱动状态 | [`docs/HARDWARE-STATUS.md`](docs/HARDWARE-STATUS.md) |
| 桌面 / 主题 / 电源 | [`docs/DESKTOP.md`](docs/DESKTOP.md) |
| 待办 | [`docs/TODO.md`](docs/TODO.md) |
| 视频硬解报告 | [`docs/references/MPV-X11-4K-HEVC.md`](docs/references/MPV-X11-4K-HEVC.md) |
| Vulkan / PanVK | [`docs/references/VULKAN-PANVK.md`](docs/references/VULKAN-PANVK.md) |
| 应用本地化 | [`docs/references/APP-LANGUAGE.md`](docs/references/APP-LANGUAGE.md) |
| 板级镜像定制入口 | [`userscripts/uscripts`](userscripts/uscripts) |
| 镜像定制模块 | [`userscripts/{install,configure,verify}`](userscripts/) |
| 包清单分层 | [`packages/`](packages/)（生成 runtime-packages.txt） |
| 打包工具（manifest/包清单/视频探针） | [`tools/`](tools/) |
| 补丁序列说明 | [`patches/SERIES.md`](patches/SERIES.md) |
| 性能 / GPU 探针 | [`tools/`](tools/) |
| 板级测试 | [`tests/`](tests/) |
| 当前基线快照 | [`tests/baseline.json`](tests/baseline.json) |
| 电源守护进程源码 | [`power-policy/`](power-policy/) |

## 关键约定

- 镜像内所有 Z96A 内容都在 `files/rootfs-overlay/z96a-v2/`；构建脚本另行读取
  `boards/z96a-v2/userscripts/uscripts`，该目录不会进入镜像。
- 桌面/主题/输入法/音频策略见 `docs/DESKTOP.md`，改动前先看 `docs/MEMORY.md`。
- 不在通用 `files/userscripts/uscripts` 中写板级分支。
- 改动前先跑 `tests/smoke-static.sh`；动桌面/GPU/视频后再跑 `tests/smoke-device.sh`。
