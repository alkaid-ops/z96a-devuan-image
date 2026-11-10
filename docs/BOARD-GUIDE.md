# 新增板卡标准流程

目标：新增一块板卡时，只动它自己的文件，不修改其他板卡的逻辑，也不把板级条件堆进通用脚本。

本仓库已与上游 `debian-image-builder` 解耦，以下路径是本仓库自有约定。
上游的 `files/bsp/` 已废弃为 `files/rootfs-overlay/`，不要恢复或建兼容链接。

## 1. 一块板卡由哪些位置组成

| 位置 | 作用 | 是否必须 |
|---|---|---|
| `lib/boards/<board>` | 板卡变量（ARCH、FAMILY、DTB、分区、内核/U-Boot、补丁目录等） | 必须 |
| `defconfig/<board>_defconfig` | 该板卡使用的内核 defconfig | 必须 |
| `files/rootfs-overlay/<board>/` | 根文件系统 overlay（仅 `etc/`、`home/`、`opt/`、`usr/` 会被拷入镜像） | 按需 |
| `patches/git/<board>/...` | 该板卡的 git 源码补丁（由 `GIT_PATCHDIR` 指定） | 按需 |
| `patches/<family>/...` | 芯片家族补丁（由 `LINUX_PATCHDIR` 指定） | 按需 |
| `boards/<board>/` | 非构建产物：README、docs、userscript、tools、tests、power-policy 源码 | 必须 |

> 构建脚本只认前五项；`boards/<board>/` 是给人/agent 用的板级工作区。

> **命名说明**：`files/rootfs-overlay/<board>/` 是**根文件系统 overlay**
> （只含 `etc`/`home`/`opt`/`usr`），不是“内核 BSP”。
> 内核源码、配置和补丁分别在 `sources/linux`、`defconfig/<board>_defconfig`、
> `patches/`，板卡变量在 `lib/boards/<board>`。

## 2. 步骤

### 2.1 创建板卡变量

```sh
cp lib/boards/<existing> lib/boards/<board>
```

至少确认：

- `ARCH` / `ARCH_EXT` / `CROSS_COMPILE`
- `SERIES` / `FAMILY` / `FAMILY_EXT`
- `DTB` / `DEVICETREE`
- `LINUX_DEFCONFIG` / `UBOOT_DEFCONFIG`
- `BOARD` / `OUTPUT`
- `GIT_PATCHDIR` / `LINUX_PATCHDIR`
- 分区相关：`GPT`、`P_VALUE`、`BOOT_*`、`EXTLINUX`

`Makefile` 会把它复制成 `board.txt`，stage1/stage2 从 `board.txt` 读取。

### 2.2 放内核 defconfig

```text
defconfig/<board>_defconfig
```

### 2.3 放根文件系统 overlay

只把需要进入镜像的目录放到 `files/rootfs-overlay/<board>/`：

```text
files/rootfs-overlay/<board>/
├── etc/
├── home/
├── opt/
└── usr/
```

构建只拷贝这四类目录；`boards/`、`docs/`、`tests/` 不会被带进镜像。

### 2.4 放补丁

- git 源码补丁：`patches/git/<board>/<repo>-<branch>/`
- 芯片家族补丁：`patches/<family>/`
- 启动/U-Boot 补丁：`patches/uboot/`（按 `UBOOT_PATCHDIR`）
- 包补丁（slim、libva 等非内核源码）：`boards/<board>/patches/`

### 2.5 创建板级工作区

```text
boards/<board>/
├── README.md                 # 板卡总览 + 构建输入对照
├── docs/
│   ├── MEMORY.md             # 已验证事实、坑、实测数据
│   ├── HARDWARE-STATUS.md    # 硬件驱动状态
│   ├── DESKTOP.md            # 桌面/会话实施记录（如有）
│   ├── TODO.md               # 未完成事项
│   └── references/           # 报告、实测数据
├── userscripts/
│   └── uscripts              # 板级 run_function0..3
├── tools/                    # 探针、性能脚本
├── tests/                    # 板级测试
├── patches/                  # 板级包补丁（slim/libva 等，按需）
└── power-policy/             # 板级守护进程源码（如适用）
```

### 2.6 板级 userscript

通用入口 `files/userscripts/uscripts` 只负责分发。板级逻辑写到：

```text
boards/<board>/userscripts/uscripts
```

可定义 `run_function0`～`run_function3`，调用时机与构建系统一致：

| 函数 | 时机 |
|---|---|
| `run_function0` | stage1 开始前（host） |
| `run_function1` | stage1 中（host，能改 `${P_VALUE}`） |
| `run_function2` | stage2 chroot 内 |
| `run_function3` | stage1 结束前（host） |

构建时 `lib/source` 会把板级脚本复制为 `/root/userscripts/board-uscripts`，
并写入 `/root/userscripts/board`，chroot 内由通用入口加载。

**禁止**在 `files/userscripts/uscripts` 里写 `if board == ...` 之类的板级分支。

## 3. 构建与验证

```sh
# 生成 board.txt 并构建（具体参数见仓库 README）
make rootfs image board=<board>

# 板级测试（推荐放在 boards/<board>/tests）
python3 -m unittest discover -s boards/<board>/tests -p 'test_*.py'

# 静态检查
bash -n files/userscripts/uscripts boards/<board>/userscripts/uscripts lib/source
git diff --check
```

## 4. 新板卡检查清单

- [ ] `lib/boards/<board>` 存在，`BOARD`/`OUTPUT`/`DTB`/`LINUX_DEFCONFIG` 正确
- [ ] `defconfig/<board>_defconfig` 存在
- [ ] `files/rootfs-overlay/<board>/` 只含 `etc`/`home`/`opt`/`usr`
- [ ] 补丁目录与 `GIT_PATCHDIR`/`LINUX_PATCHDIR` 一致
- [ ] `boards/<board>/userscripts/uscripts` 可独立完成板级定制
- [ ] 板级文档在 `boards/<board>/docs/`
- [ ] 板级测试在 `boards/<board>/tests/`
- [ ] 不修改其他板卡的 `lib/boards/*`、`defconfig/*`、`files/rootfs-overlay/*`
- [ ] `bash -n`、板级测试、`git diff --check` 通过
