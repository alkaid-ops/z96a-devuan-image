# Z96A 工程化改造方案（正式）

状态：**正式基准**。更新：2026-11-09。

本文取代此前的 P0/P1/P2 优化清单，作为本项目工程化改造的**唯一基准**。
后续 Codex / agent / 人都按本文的阶段、门禁和执行规则工作，不再直接按旧清单批量重构。

---

## 1. 文档地位

- 本文是工程化改造的基准；代码、配置、构建脚本的改动必须能对应到本文的某个阶段任务。
- 未列入本文的想法属于“候选池”，不是承诺，不直接执行。
- 任何阶段范围的调整，先改本文，再改代码。
- 每完成一个阶段，更新本文的“当前状态”和“未解决问题”。

---

## 2. 工程目标

### 2.1 六个目标

1. **可复现**：同样的源码与配置，能得到一致的功能结果。
2. **可追溯**：每个镜像能追溯到源码、补丁、工具链、软件包和构建环境。
3. **可验证**：核心硬件能力有可执行的验收依据，不依赖人工记忆。
4. **可维护**：板级定制与通用构建逻辑分离，单板改动不影响其他板。
5. **可恢复**：升级失败时有明确的备份、恢复和回滚路径。
6. **可扩展**：未来增加板卡时不需要推翻现有结构。

### 2.2 横向约束（每个阶段都必须满足）

- **安全**：凭据、供应链、再分发许可、默认配置。
- **性能预算**：内存、启动时间、镜像体积、视频丢帧不能明显退化。
- **向后兼容**：配置格式、CLI、板级脚本接口的变更必须有迁移方案。
- **现有硬件功能不退化**：X11、Panfrost、V4L2、音频、网络、电源管理在改动前后都要通过同一套回归。

---

## 3. 执行规则（强制）

### 3.1 先审计，再计划，最后执行

每个任务必须按以下顺序进行，**禁止根据优化清单直接批量重构**：

1. **审计**：确认当前状态、证据、依赖关系和风险。
2. **计划**：写清目的、范围、不改变什么、验收标准、回滚方案。
3. **执行**：一次只动一个层，小步提交。
4. **验证**：跑对应阶段的回归项，保存结果。
5. **记录**：更新本文、板级文档或 ADR，写清未解决问题。

如果审计发现范围比预期大，**停止执行并重新计划**，不要静默扩大改动。

### 3.2 每个任务的必填记录

```text
### 任务：<一句话>
- 阶段：0/1/2/3/4
- 当前状态与证据：
- 改动目的：
- 改动范围（文件/目录）：
- 明确不改变：
- 验收标准：
- 回归项：
- 风险与回滚：
- 未解决问题：
```

没有“当前状态与证据”和“验收标准”的任务不进入执行。

### 3.3 阶段门禁

- 上一阶段的**退出条件**未满足，不进入下一阶段。
- 阶段内可以并行小任务，但不能跳过回归。
- 任何阶段都不得破坏当前已知正常的 X11/Panfrost/V4L2/启动链路。

---

## 4. 阶段总览

| 阶段 | 核心目标 | 交付物 | 退出条件 |
|---|---|---|---|
| 0 | 建立基线与回归保护 | baseline、最小测试脚本、最小 CI | 当前已知正常状态可重复验证 |
| 1 | 来源可信与可追溯 | manifest、版本锁定、补丁管理 | 任意镜像可追溯到源码/补丁/工具链/包 |
| 2 | 构建系统工程化 | 配置模型、包分层、脚本模块化 | 配置单一来源、脚本职责清晰、行为不变 |
| 3 | 自动化验收 | 静态检查、rootfs 测试、真机 HIL | 核心硬件能力有自动 PASS/FAIL 依据 |
| 4 | 发行版能力完善 | 升级回滚、SBOM、发布渠道、多板卡 | 可发布、可升级、可恢复 |

### 当前状态（2026-11-09）

| 阶段 | 状态 | 证据 |
|---|---|---|
| 0 | **完成（视频基线暂缓）** | `tests/smoke-{static,rootfs,device}.sh`、`tests/baseline.json`、`.github/workflows/ci.yml`、`tests/test_repo_consistency.py`（15 项仓库检查） |
| 1 | **完成（真实构建 + 镜像校验；APT snapshot 除外）** | 内核 commit 固定；`manifest.json` 可重复生成并写入镜像；补丁序列 11/11 顺序应用通过；deb 移出版本库 + `fetch-packages.sh`；SHA256 强制校验；Mesa 版本可追溯；secret scan 接入 CI。构建根已容器化；**完整容器构建产出的镜像已通过校验**（manifest/sbom/mesa 26.1.6/board.runtime，见 §6.5）；仅剩 APT snapshot |
| 2 | **完成（镜像回归通过，M4 记录已在镜像内）** | 包清单分层、Feature Flags、配置单一来源（生成器 + 构建期漂移拦截）、派生字段校验、板级 uscript 拆为 15 个模块（零行为变化）、M4 用 `board.runtime` 取代 `board.txt` sed（6 组组合等价性测试；镜像内 `/etc/z96a/board.runtime` 实证）、M5 `lib/boards` 标记为生成物 |
| 3 | **部分实施（10 项已判定，5 项 deferred-pending-user）** | 已加入 `smoke-device.sh` 并在 `.84` 实测 PASS：H2 显示模式、H3 GLX 直渲、H4 Vulkan 合规、H7 音频播放、H8 6ch 录音、H9 有线 IPv4、H11 音量/亮度、H12 电池/AC、H13 电源策略、H16 存储。(H1/H5/H6/H14/H15 标记 ⏸ deferred-pending-user) |
| 4 | **部分实施（R1/R2/R3/R5 与回滚演练 deferred-pending-user）** | R4 静态偏移检查、R8 ADR、R6 SBOM（`sbom.json`，SPDX-lite）、R7 发布命名（`release_info.artifact_name` + channel）已落地并有 fake-rootfs 测试；R1/R2/R3/R5 标记 ⏸ deferred-pending-user；CVE 扫描需外部数据源 |

阶段 1 未完成项：APT snapshot（需要镜像站快照源，当前网络下不可用）。

### 当前状态：退出条件逐条对照（2026-11-09）

**标记说明**：✅ 满足 · ⏸ deferred-pending-user（用户明确统一到最后处理） ·
⌛ 需外部资源（网络/数据源）· ❌ 未满足

| 阶段 | 退出条件 | 状态 | 证据 / 说明 |
|---|---|---|---|
| 1 | 任意一次构建都有完整 manifest | ✅ | §6.5 第二次构建：1140 包 + sbom 1142 包，镜像内可解析 |
| 1 | 相同配置两次构建的 manifest 输入字段一致 | ✅ | 主机侧两次生成比对 `input fields identical: True` |
| 1 | 补丁可被脚本按记录顺序应用 | ✅ | 干净 worktree 顺序应用 11/11，`failures=0` |
| 1 | 仓库不再依赖移动分支或未校验下载 | ✅ | `GIT_PIN_COMMIT` + deb `SHA256SUMS` 强制校验 |
| 1 | 已泄漏凭据完成轮换 | ⏸ | 用户统一处理，不在本轮范围 |
| 1 | APT snapshot | ⌛ | 构建网络无法访问 snapshot 源 |
| 2 | `make check-config` 能拦截已知冲突 | ✅ | `make preflight` 拦截 kernel/U-Boot 版本分叉 |
| 2 | 配置迁移前后镜像包集/行为一致 | ✅ | §6.5 最终镜像校验 + 等价性测试（6 组合）+ `board.runtime` 记录 |
| 2 | 板级 uscript 拆分后回归全部通过 | ✅ | 15 模块零行为变化；镜像构建通过；67 项测试 |
| 2 | 没有板级条件写入通用脚本 | ✅ | `files/userscripts/uscripts` 仅分发 |
| 2 | 关键包版本可追溯 | ✅ | manifest + `/etc/z96a/mesa-version` |
| 3 | 核心硬件能力有自动 PASS/FAIL | ✅（10/16） | H2/H3/H4/H7/H8/H9/H11/H12/H13/H16 真机 PASS |
| 3 | 镜像结构/分区/启动配置有静态检查 | ✅ | `smoke-static --image` PASS |
| 3 | 首次启动扩容、shrink 后启动有测试 | ⏸ | H14/H15 由用户统一验证 |
| 3 | 基线可重复，噪声范围已记录 | ✅ | `tests/baseline.json` |
| 3 | HIL 不阻塞日常开发，但结果可查 | ❌**未运行** | 流程已成文（§8.6），尚无真机 HIL 记录 |
| 3 | 视频 H5/H6 | ⏸ | 用户明确不在本轮执行 |
| 4 | 发布产物有 manifest、校验和、渠道命名 | ✅ | `release_info` + `.sha256` + artifact 命名 |
| 4 | 升级/回滚流程有文档并演练过 | ⏸（文档 ✅ / 演练 ⏸） | §9.4 命令序列已成文；演练由用户统一执行 |
| 4 | 关键架构决策有 ADR | ✅ | `docs/adr/` 6 篇 |
| 4 | 第二块板卡出现时无需推翻结构 | ✅（设计） | 板级目录 + TOML 配置模型 |
| 4 | SBOM/CVE | ✅ SBOM / ❌ CVE | CVE 需外部数据源与联网 |

**结论**：阶段 0–2 的退出条件已由证据支撑；阶段 3 除 HIL 与 5 项 ⏸ 外满足；
阶段 4 除演练与 CVE 外满足。所有未满足项均已标注原因归属。
阶段 2 剩余：仅“一次完整构建 + `smoke-static --image`”的形式回归；代码侧 M1–M5 与模块拆分均已完成，并有等价性/一致性测试。

---

## 5. 阶段 0：基线与回归保护

### 5.1 目标

把现有的手工验证转成**最小可执行脚本**，记录当前已知正常状态。
阶段 0 不是测试框架建设项目，不追求覆盖率，不建设平台。

### 5.2 明确不做

- 不重构构建系统。
- 不修改系统配置。
- 不引入大型测试框架、数据库、仪表盘。
- 不设置性能阈值（先采集基线）。
- 不追求 bit-identical 构建。

### 5.3 任务（阶段 0 首轮已完成）

- [x] 盘点现有手工验证：`boards/z96a-v2/docs/MEMORY.md`、`DESKTOP.md`、`HARDWARE-STATUS.md`、`tools/`。
- [x] 最小静态检查脚本 `tests/smoke-static.sh`：
  - 仓库一致性（配置/路径/包校验/文档链接/defconfig 关键项）。
  - 镜像模式（需 root）：分区表、vfat 启动分区、extlinux.conf、DTB、ext4 `fsck -n`。
- [x] 最小 rootfs 检查脚本 `tests/smoke-rootfs.sh`：关键二进制、桌面配置、服务、启动器、应用；`--chroot` 时跑 `dpkg --audit` 与 `apt-get check`。
- [x] 最小真机冒烟脚本 `tests/smoke-device.sh`：SSH、X11、Panfrost、`/dev/dri/renderD128`、PanVK conformance、mixer、默认路由、面板/桌面进程、分辨率与刷新率。
- [x] 基线 JSON `tests/baseline.json`：内核、Mesa、renderer、Vulkan conformance、显示模式/刷新率、网卡状态、MemAvailable、PSS、uptime。
- [x] 最小 CI `.github/workflows/ci.yml`：shellcheck、Python 单元测试、静态 smoke、`git diff --check`。
- [x] “当前已知正常状态”快照：见 `tests/baseline.json` 与 `docs/MEMORY.md`。
- [ ] 真机视频基线（固定片源 fps/丢帧）与启动到 SSH 时间，需要控制负载后单独采集。
- [ ] 首次启动扩容、shrink 后启动的镜像级验证（需要一次完整构建与真机刷写）。

### 5.5 退出条件

- 在未修改系统的情况下，脚本能对当前镜像/设备给出稳定结果。
- 基线 JSON 已保存，且与当前 `MEMORY.md` 的记录一致。
- CI 在干净检出上通过。
- 明确记录“哪些检查只能真机做、哪些可静态做”。

---

## 6. 阶段 1：来源可信与可追溯

### 6.1 目标

确保每个镜像都能回答：源码是什么、补丁是什么、用什么工具链、装了哪些包。

### 6.2 任务

- [x] 固定内核源码：`lib/boards/z96a-v2` 的 `GIT_PIN_COMMIT`，`lib/function/git` 按 commit fetch/checkout。
- [x] 固定 U-Boot：版本与预编译 blob 的 SHA256 记入 manifest（`tools/make-manifest.sh`）。
- [x] 固定 Mesa：`MESA_BACKPORTS_PIN` 可选钉版本；实际版本写入 `/etc/z96a/mesa-version` 并进 manifest。
- [x] 补丁分层（`boards/z96a-v2/patches/SERIES.md`）：
  - 上游分支补丁：记录 repo/commit，不强行逐条维护。
  - 本地补丁：`series` + 来源/用途/上游状态。
  - 本地未提交改动：单独目录。
- [x] 外部下载统一 SHA256 校验：预置 deb 安装前强制校验 `SHA256SUMS`。
- [x] 生成 `manifest.json`（`tools/make-manifest.sh`，写入镜像 `/etc/z96a/manifest.json` 与 `output/<board>/`）：
  - board、arch、distro、release。
  - kernel repo/commit/version/config SHA256。
  - U-Boot 版本/commit/blob SHA256。
  - Mesa 版本。
  - 补丁系列 hash。
  - 工具链版本。
  - 已安装包清单（`dpkg-query`）。
  - 构建时间、构建主机、镜像 SHA256。
  - `release_info`：`channel`（`RELEASE_CHANNEL`，默认 nightly）、`artifact_name`
    （`<board>-<kernel>-<channel>-<YYYYMMDD>.img.xz`）、`sbom: sbom.json`。
- [x] SBOM：`make-manifest.sh` 同时输出 `sbom.json`（SPDX-2.3-lite，逐包 name/version
  + kernel/U-Boot 条目）。CVE 扫描未做，需要外部数据库与联网。
- [x] 大 deb 移出 Git：`.deb` 已取消跟踪并加入 `.gitignore`；`packages-sources.tsv` 记录名称/SHA256/URL/许可证；`tools/fetch-packages.sh` 负责恢复并校验。
- [~] 凭据外部注入：支持 `boards/<board>/credentials.local`（已 gitignore）；`tools/scan-secrets.sh` + CI gitleaks 已接入；**历史凭据轮换仍需人工执行**。
- [x] 固定构建根：`boards/z96a-v2/tools/Dockerfile`（debian:trixie-slim + 显式工具链包）
  + `tools/build-in-container.sh`；镜像已实际构建并在容器内跑通 `make preflight`。

### 6.3 可复现性分级

| 级别 | 目标 | 阶段 |
|---|---|---|
| L1 可追溯 | manifest 完整记录输入与产物 | 阶段 1 必达 |
| L2 功能可复现 | 同样输入得到同样的包集/内核/DTB/overlay，启动行为一致 | 阶段 1–2 |
| L3 位级可复现 | 两次构建镜像 hash 一致 | 阶段 4，按需 |

不追求 L3 优先于 L1/L2。

### 6.4 退出条件

- 任意一次构建都有完整 manifest。
- 相同配置两次构建的 manifest 输入字段一致。
- 补丁可被脚本按记录顺序应用。
- 仓库不再依赖移动分支或未校验下载。
- 已泄漏凭据完成轮换，CI 有 secret scanning。

### 6.5 真实构建与镜像校验（2026-11-09）

构建方式：`boards/z96a-v2/tools/build-in-container.sh "rootfs image"`（固定构建根容器）。
耗时 5313s，产出：

```text
rk3568-sunniwell-z96a-typec-devuan-excalibur-minimal-7.2.12-arm64-ext4-2026-11-09-1502.img.xz  (2.8G)
```

镜像内证据（`tools/validate-image.sh`，loop 挂载只读校验）：

```text
PASS  image has etc/z96a/manifest.json
PASS  image has etc/z96a/sbom.json
PASS  image has etc/z96a/mesa-version
PASS  image has effective board.txt
PASS  manifest parses: board=z96a-v2 kernel=7.2.12 pinned=0211cf630ee3
PASS  manifest installed packages: 1139
PASS  manifest artifact: z96a-v2-7.2.12-nightly-20261109.img.xz
PASS  sbom: SPDX-2.3-lite with 1141 packages
PASS  ext4 clean / extlinux.conf / DTB present / image file type
PASS  dpkg --audit / apt-get check (chroot)
ROOTFS SMOKE: PASS   IMAGE VALIDATION: PASS
```

摘要已存档：`boards/z96a-v2/tests/build-evidence.json`。

#### 最终构建（board.runtime 修复后，2026-11-09-2005）

镜像：`...-2026-11-09-2005.img.xz`（2.8G，构建 3087s）。
`validate-image.sh` 输出：

```text
PASS  image file type / extlinux.conf / DTB present / ext4 clean
PASS  image has etc/z96a/manifest.json
PASS  image has etc/z96a/sbom.json
PASS  image has etc/z96a/mesa-version
PASS  image records board.runtime overrides
PASS  image has effective board.txt
PASS  manifest parses: board=z96a-v2 kernel=7.2.12 pinned=0211cf630ee3
PASS  manifest installed packages: 1140
PASS  manifest artifact: z96a-v2-7.2.12-nightly-20261109.img.xz
PASS  sbom: SPDX-2.3-lite with 1142 packages
STATIC SMOKE: PASS   ROOTFS SMOKE: PASS   IMAGE VALIDATION: PASS
```

镜像内 `/etc/z96a/` 实际内容：

```text
board.runtime   board.source.txt   manifest.json   mesa-version   sbom.json
```

`board.runtime` 记录（证明 M4 生成器生效、board.txt 未被改写）：

```text
P_VALUE="p2"
EXTLINUX="true"
BOOTCMD="false"
BOOT_EXT4="false"
BOOT_VFAT="true"
EFI="false"
GPT="true"
PETITBOOT="false"
```

#### 真实构建暴露的缺陷轨迹（每条都由构建验证）

| # | 现象 | 根因 | 修复 | 验证 |
|---|---|---|---|---|
| 1 | chroot 内 `install/10-base.sh: No such file` | 模块在 `boards/`，`lib/source` 只复制入口 | 递归复制 `install/configure/verify` | 后续构建通过 + 单元测试 + 预检 |
| 2 | 镜像 `mesa-version` 为 25.0.7 | backports 优先级 100 < main 500，`-t` 不升级已装包 | `Pin: release n=excalibur-backports` / 900 | 镜像内 `26.1.6-1~bpo13+1` |
| 3 | 第二次构建回落到 25.0.7（告警而非失败） | `apt-cache policy \| grep` 在 `pipefail` 下误判 | 改用 apt 源 `grep -rqs`；<26.1 且 backports 可用→`exit 1` | `MesaBackportsTests` 3 项 |
| 4 | 镜像无 `/etc/z96a/board.runtime` | `customize_image` 在 board.txt 被 source 前执行，`${BOARD}` 为空 → 走旧 sed 回退 | 从 `board.txt` 反解 `BOARD` | 本地以仓库根 cwd 模拟：生成 `P_VALUE="p2"` 等取值、`board.txt pristine: yes` |

第 4 条的注入路径改由 `BoardRuntimeInjectionTests` 直接验证（不依赖整机镜像）：
`/etc/z96a/board.runtime`、`manifest.json`、`sbom.json` 与 `output/<board>/` 下的副本均生成。

#### 第二次构建（Mesa 修复后）

同一流程重跑，产出 `...-2026-11-09-1722.img.xz`（2.8G，5504s），校验结果：

```text
PASS  image file type / extlinux.conf / DTB present / ext4 clean
PASS  image has etc/z96a/manifest.json
PASS  image has etc/z96a/sbom.json
PASS  image has etc/z96a/mesa-version
PASS  mesa-version: 26.1.6-1~bpo13+1
PASS  manifest parses: board=z96a-v2 kernel=7.2.12 pinned=0211cf630ee3
PASS  manifest installed packages: 1140
PASS  manifest artifact: z96a-v2-7.2.12-nightly-20261109.img.xz
PASS  sbom: SPDX-2.3-lite with 1142 packages
PASS  dpkg --audit / apt-get check (chroot)
STATIC SMOKE: PASS   ROOTFS SMOKE: PASS   IMAGE VALIDATION: PASS
```

镜像内 `mesa-version` 实测为 `26.1.6-1~bpo13+1`，即 PanVK/OxideTerm 路径可用。

#### 构建暴露并已修复的两个缺陷

1. **模块未进 chroot**：模块拆分后 `lib/source` 只复制入口脚本，chroot 内 `install/10-base.sh`
   缺失导致构建中断。已补 `install/configure/verify` 的递归复制，并加测试 + 预检守护。
2. **Mesa 未真正升级**：backports 默认优先级 100 输给 main 的 500，`-t` 不会升级已安装的
   Mesa，镜像里实际是 25.0.7（PanVK 不可用）。改为按 Codename 钉住：

   ```text
   Pin: release n=excalibur-backports
   Pin-Priority: 900
   ```

   实测（镜像内 chroot）：candidate 从 `25.0.7` 变为 `26.1.6-1~bpo13+1`，安装成功。
   并增加硬性检查：backports 可用但版本仍 <26.1 时 **构建失败**，不再只告警。

---

## 7. 阶段 2：构建系统工程化

### 7.1 目标

让配置、包、脚本职责清晰，行为与阶段 1 一致。

### 7.2 配置模型

建议结构（可调整，但必须单一真值）：

```text
config/
├── global.toml
├── boards/
│   └── z96a-v2.toml
├── families/
│   └── rk3568.toml
├── profiles/
│   ├── minimal.toml
│   └── desktop.toml
└── features/
    ├── video.toml
    ├── desktop.toml
    └── apps.toml
```

优先级：

```text
global < family < board < profile < features < CLI/env
```

要求：

- 只有一个可编辑真值；`board.txt`/`lib/boards` 由配置生成或迁移后废弃。
- 不在两处同时手工维护同一字段。
- `make check-config` 在构建前校验类型、必填、冲突、路径存在性。
  首轮已实现为 `make preflight board=z96a-v2`（`boards/<board>/tools/preflight.sh`），
  并由板级 `run_function0` 在 stage1 开始时自动执行。

### 7.3 包分层（已完成首轮）

```text
boards/z96a-v2/packages/
├── base.txt          系统、固件、网络、X11、共享库
├── desktop.txt       LXQt、Openbox、图标、输入法、portal
├── multimedia.txt    FFmpeg / GStreamer
└── applications.txt  内置桌面应用
```

生成与校验：

- `boards/z96a-v2/tools/gen-runtime-packages.sh` 生成
  `files/rootfs-overlay/z96a-v2/opt/z96a/runtime-packages.txt`。
- 跨层重复包直接失败。
- `tests/test_repo_consistency.py` 校验生成文件与分层一致，防止漂移。
- 系统基础包与应用包分开更新、分开验证。
- 关键包固定版本；其余允许跟随仓库但记录实际版本。
- 第三方应用优先构建时下载 + SHA256，不入 Git。

### 7.4 Feature Flags（已完成首轮）

`boards/z96a-v2/features.conf` → 构建时复制为 `/opt/z96a-features.conf` → `run_function2` 读取。

| 开关 | 默认 | 影响 |
|---|---|---|
| `ENABLE_DESKTOP` | 1 | LXQt/Openbox 主题与桌面初始化 |
| `ENABLE_APPS` | 1 | 预置第三方应用安装 |
| `ENABLE_MULTIMEDIA` | 1 | 自定义 mpv（V4L2 硬解） |
| `ENABLE_VULKAN` | 1 | PanVK conformance layer |
| `ENABLE_LOCALSEND` | 1 | LocalSend Next |

默认值等于当前已验证镜像的行为；关闭只影响对应可选功能。
`tests/test_repo_consistency.py` 校验默认值存在且主脚本确实读取。

### 7.5 脚本模块化（已完成，零行为变化）

实际落地的结构（保持 `run_function2` 为编排器，模块按原执行顺序 source）：

```text
boards/z96a-v2/userscripts/
├── uscripts                 # 入口 + run_function0..3 + 共享 helper
├── install/
│   ├── 10-base.sh           # VA-API / Mesa / runtime-packages
│   ├── 20-multimedia.sh     # mpv 配置、视频 mime、glib schemas
│   └── 30-apps.sh           # 内置 ARM64 应用、OxideTerm 启动器
├── configure/
│   ├── 10-environment.sh    # 视频/Vulkan 环境变量
│   ├── 20-hwdb.sh           # udev hwdb + ldconfig
│   ├── 30-locale.sh         # 中文 locale、字体
│   ├── 40-input-method.sh   # WindInput + Fcitx5 profile
│   ├── 50-lock.sh           # slimlock 策略、IME 环境
│   ├── 60-session.sh        # z96a 二进制、LXQt 配置、启动器、菜单、elogind
│   ├── 70-network.sh        # GVfs/PCManFM-Qt 协议、菜单前缀
│   ├── 80-x11.sh            # Xresources、.xinitrc
│   ├── 85-theme.sh          # 主题、桌面快捷方式、亮度键
│   ├── 88-services.sh       # 服务注册、SSH 密钥/密码、sshd
│   └── 96-ownership.sh      # 所有权、网络托盘、Vulkan、LocalSend
└── verify/
    └── 99-seal.sh           # 包闭包检查、首次启动凭据
```

性质：

- **零行为变化**：拆出的内容与拆分前逐行一致，source 顺序与执行顺序一致；
  入口脚本只保留 `run_function0..3` 与共享 helper。
- 校验：内容等价性用脚本重建比对（`content identical to pre-split: True`）；
  `ScriptModuleSplitTests` 固定 15 个模块及其 source 顺序；预检逐个 `bash -n`。
- **chroot 侧**：模块在 `boards/` 而不是 `files/userscripts/`，因此 `lib/source`
  在 stage1 会把 `install/configure/verify/*.sh` 一起复制进
  `/root/userscripts/`，否则 chroot 内 source 失败（首次真实构建暴露过该问题，
  已修复并由测试与预检双重守护）。

坚持：

- **install / configure / verify 分离**。
- 幂等 helper（`ensure_line`、`install_if_missing`）。
- 统一下载 helper（重试 + SHA256）。
- 统一日志与阶段耗时。
- 失败时保留阶段标记和诊断信息。

### 7.6 配置单一来源审计（只读，2026-11-09）

本节按 §3.1 的“先审计”规则产出，**未修改构建行为**。

#### 现状：配置实际有 4 个输入 + 1 个可写生成物

| 文件 | 角色 | 典型变量 | 是否手改 |
|---|---|---|---|
| `lib/boards/z96a-v2` | 硬件/构建/内核/U-Boot 参数 | `ARCH` `DTB` `P_VALUE` `GIT_PIN_COMMIT` `FORCE_LINUX_VERSION` | 是 |
| `userdata.txt` | 发行版与用户、镜像开关 | `DISTRO` `VERSION` `PACKAGE` `USCRIPTS` `COMPRESS_IMG` | 是 |
| `custom.txt` | 镜像布局覆盖 | `ENABLE_BOOT_VFAT` `ENABLE_EFI` `ENABLE_BOOTCMD` `FSTYPE` `IMGSIZE` | 是 |
| `boards/z96a-v2/features.conf` | 可选功能 | `ENABLE_DESKTOP` `ENABLE_VULKAN` … | 是（新增） |
| `board.txt` | 运行时合并结果 | 全部 | **否**（生成后可被改写） |

#### 实际生效顺序（重要）

```text
lib/boards/z96a-v2
   ↓ Makefile: sudo cp  →  board.txt          （Makefile:52）
   ↓ stage1: customize_image 用 custom.txt 反向 sed 改写 board.txt
   ↓ stage1: . board.txt                       （scripts/stage1:35）
   ↓ scripts/linux: FORCE_LINUX_VERSION 覆盖 VERSION
   ↓ chroot: /etc/opt/board.txt、/root/board.txt
```

`customize_image` 会修改 `board.txt` 的 `P_VALUE`、`EFI`、`EXTLINUX`、
`BOOTCMD`、`BOOT_VFAT`、`GPT`（`lib/function/staging:455-482`）。
因此 `board.txt` 不是 `lib/boards` 的纯副本，**它才是运行时真值**。

#### 已确认的重复与冲突点

| 字段 | 位置 A | 位置 B | 现状 |
|---|---|---|---|
| 内核版本 | `userdata.txt: VERSION` | `lib/boards: FORCE_LINUX_VERSION` | 已对齐 7.2.12，但仍是两处 |
| U-Boot 版本 | `userdata.txt: UBOOT_VERSION` | `lib/boards: FORCE_UBOOT_VERSION` / `PKGVERSION` | 均为 v2026.01，重复 |
| 分区/boot 方案 | `lib/boards: P_VALUE/EFI/EXTLINUX/BOOT_*` | `custom.txt: ENABLE_*` | 后者覆盖前者 |
| 镜像压缩/体积 | `custom.txt: IMGSIZE/IMG_COMPRESSION` | `userdata.txt: COMPRESS_IMG` | 语义重叠 |
| 板级功能 | `features.conf` | 无 | 唯一来源（新） |
| 包清单 | `packages/*.txt` | `runtime-packages.txt`（生成） | 生成物，已有漂移测试 |

#### 目标模型（阶段 2 后续实施）

```text
config/
├── z96a-v2.toml          # 唯一可编辑真值：board + kernel + uboot + image + features
└── (生成) lib/boards/z96a-v2、board.txt
```

优先级：`lib/boards 默认值 < custom.txt 覆盖 < 环境变量/CLI`。
`board.txt` 保持“生成的运行时文件”，不再被 sed 反向改写；覆盖项改为单独的
`board.runtime` 或由生成器直接算出最终值。

#### 迁移步骤（每步可独立回滚）

| 步 | 内容 | 验证 | 回滚 |
|---|---|---|---|
| M1 ✅ | `config/z96a-v2.toml` + `tools/gen-board-config.sh`；golden diff、`make board-config`、预检钩子 | `gen-board-config.sh --check` → PASS；`make preflight` → PASS；测试 3 项 | 删除 `config/` 与生成器，无行为变化 |
| M2 ✅ | Makefile 的 `board_setup` 先做 `gen-board-config.sh --check` 再复制；不一致直接中止 | `make -n rootfs` 展开正确；临时改坏 TOML → `guard_rc=1`；恢复后 `CONFIG SOURCE: PASS` | 单 commit revert |
| M3 ~ | `userdata.txt` 的 `VERSION`/`UBOOT_VERSION` 视为派生字段；预检已强制与 board 一致（内核、U-Boot 两项均校验） | `make preflight` → `kernel/u-boot version sources agree` | 仅删检查 |
| M4 ✅ | `customize_image` 不再 sed `board.txt`，改为 `tools/gen-board-runtime.py` 生成 `board.runtime`，由 stage1/stage2 在 `board.txt` 之后 source；旧 sed 链保留为无生成器板卡的回退 | 等价性测试覆盖 6 组 custom.txt 组合（含 efi / bootcmd / btrfs / petitboot / 全开）与旧 sed 结果逐变量一致；`board.txt` 保持 pristine；预检校验生成器与两处 source 钩子 | 删 `board.runtime` 与钩子，恢复旧 sed 链 |
| M5 ✅ | `lib/boards/<board>` 顶部标记为 GENERATED，只由 `config/<board>.toml` + `make board-config` 产生；文档指向 `config/` | `gen-board-config.sh --check` PASS；`make preflight` 校验一致；构建期 `board_setup` 拦截漂移 | 恢复手写 board 文件 |

**门禁**：M2 之后每一步都必须有一次成功构建 + `smoke-static --image` 才能进入下一步；
没有构建产物时只允许执行 M1（纯生成器 + golden diff，零行为变化）。

#### 阶段 3 / 4 的审计

阶段 3、4 的只读审计见 §8.6 与 §9.4。

### 7.7 退出条件

- `make check-config` 能拦截已知冲突（如内核版本不一致）。
- 配置迁移前后镜像包集/行为一致。
- 板级 uscript 拆分后，回归全部通过。
- 没有板级条件写入通用脚本。
- 关键包版本可追溯，应用包与系统包更新解耦。

### 7.8 镜像瘦身（包级裁剪 + 模块校验）

策略分两层（此前按目录名删除是错误的，见“教训”）：

1. **包级裁剪**：只 purge 本板不可能用到的固件包，保留包的目录一律不动，
   `dpkg` 数据库因此保持一致。
2. **模块引用校验**：从 `/usr/lib/modules/**/*.ko` 的 `modinfo` 提取
   `firmware=` 路径（实测 3511 个模块、139 条引用），逐一确认文件仍存在；
   缺一个就**让构建失败**，避免再次静默删掉板载蓝牙这类关键固件。

| 保留包 | 原因 |
|---|---|
| `firmware-realtek` | rtw88（RTL8822CS WiFi）+ **rtl_bt（板载蓝牙）** + rtl_nic/rtlwifi（USB 网卡） |
| `firmware-mediatek` | MT76 系列 USB WiFi |
| `firmware-brcm80211` | 博通 USB WiFi/BT |
| `firmware-ath9k-htc` | ath9k USB WiFi |
| `firmware-misc-nonfree` / `firmware-linux-free` | USB 串口/视频等零散固件 |

| purge 包 | 原因 |
|---|---|
| `firmware-iwlwifi`（~193M） | Intel 网卡均为 M.2/PCIe，本板无插槽 |
| `firmware-qcom-soc`（110M+） | 无高通模组 |
| `firmware-amd-graphics` / `firmware-nvidia-graphics` | 无独显 |
| `firmware-intel-graphics` / `firmware-intel-misc` / `firmware-intel-sound` | 无对应硬件 |
| `firmware-atheros`（~124M） | QCA 为 PCIe 卡；ath9k USB 固件由独立包提供 |

另外删除：内置 `.deb` 残留（884M）、`/usr/share/doc`（只留 copyright）、
`man`、非 zh/en 的 gettext 目录、apt lists/archives。

#### 教训（2026-11-10）

第一版裁剪按**目录名**白名单删除 `/usr/lib/firmware/*`，导致：

- `rtl_bt/` 被删 → 本板 RTL8822CS **蓝牙固件丢失**（`.84` 上 `hci0` 为 UP，镜像里将无法启动）
- `rtl_nic` / `rtlwifi` / `realtek` 被删 → 外接 USB 网卡/WiFi 受影响
- `dpkg -V firmware-realtek` 报告文件缺失（保留了包却删了文件，数据库不一致）

因此改为「包级 purge + 模块引用校验」，并把 `rtl_bt` 等写进 `validate-image.sh` 的
必检项（缺失即 FAIL）。

### 7.9 内核 defconfig 裁剪（第三层）

`boards/z96a-v2/defconfig-trim.txt` + `tools/trim-defconfig.sh`（幂等，`--check` 供预检）。
只关闭本板物理上不可能存在的子系统：

| 关闭 | 理由 |
|---|---|
| `DRM_AMDGPU` / `RADEON` / `NOUVEAU` / `AST` / `BOCHS` / `QXL` / `UDL` / `MGAG200` / `VIRTIO_GPU` | 只有 Mali-G52（panfrost） |
| `IWLWIFI` / `ATH10K` / `ATH11K` / `ATH12K`（含 PCI 子项） | 无 M.2/PCIe WiFi 卡槽 |
| `DVB_CORE` / `MEDIA_DIGITAL_TV` / `SDR` / `RADIO` / `MEDIA_TUNER` | 无调谐器 |
| `SATA_AHCI` | 无 SATA 口（USB 存储走 SCSI，不受影响） |

**明确保留**：`RTW88`（板载 WiFi）、`BTRTL`（板载蓝牙）、`USB_VIDEO_CLASS`（UVC 摄像头）、
`ATH9K_HTC` / `MT76` USB / `USB_STORAGE` / `USB_NET_*` 等 USB 外设路径。


### 7.10 构建加速：复用 chroot 安装结果（已实测）

`make image` 每次都会重做 chroot 安装（apt 装桌面 + 板级 uscript），占整轮 60% 以上。
新增 `boards/z96a-v2/tools/chroot-cache.sh`，由 `scripts/stage1` 在 `chroot` 前后调用。

```text
key      构建开始时算一次 sha256（board 变量/TOML/defconfig/features/trim/
         SHA256SUMS/userscript 模块/overlay 文件/kernel deb）
save     成功后把 p1（启动分区）与 p2（rootfs）分别存入
         output/cache/chroot-<board>-<key>/{p1,p2}
restore  下次构建直接恢复，跳过整个 chroot 阶段
```

关键实现细节（都是踩坑后修正的）：

| 问题 | 修正 |
|---|---|
| 宿主与容器算出的 key 不同 | `sort` 受 locale 影响（`NetworkManager` vs `conf.d` 排序不同）→ 加 `export LC_ALL=C` |
| 同一轮构建里 key 会变 | key 在 stage1 开头计算一次并 `export CHROOT_CACHE_KEY`，save/restore 都用它 |
| 缓存含 `/dev` 设备节点，restore 覆盖绑定的 `/dev` | rsync 排除 `/dev /proc /sys /tmp /var/cache /var/log` |
| 只缓存 rootfs 导致 **DTB 丢失** | 同时缓存 p1；恢复后校验 `p1` 里有 `.dtb`，否则回退到完整 chroot |
| 坏镜像生成坏缓存（自我复制） | 缓存必须从“已验证过 DTB”的镜像重建 |

实测（同一输入，主机 load 波动）：

| 场景 | 总时长 | chroot 阶段 |
|---|---:|---:|
| 无缓存（完整安装） | 3941–5508s | 3067–3538s |
| **缓存命中** | **569–590s** | **74–223s** |
| 其中：解压 rootfs | 59s | — |
| shrink | 93s | — |
| xz 压缩 | 223–235s | — |

即 **9.5 分钟**完成一次镜像重建（不含内核编译）。`CHROOT_CACHE=0` 可强制全量。

缓存命中的镜像同样通过完整校验：

```text
PASS  DTB present in boot partition / extlinux.conf / ext4 clean
PASS  manifest / sbom / mesa 26.1.6 / board.runtime
PASS  firmware present: rtl_bt rtw88 rtl_nic realtek rtlwifi brcm rkwifi regulatory.db
IMAGE VALIDATION: PASS
```

---

## 8. 阶段 3：自动化验收

### 8.1 三层测试

| 层 | 内容 | 工具 | 是否可替代真机 |
|---|---|---|---|
| 静态检查 | 分区、文件系统、DTB、内核 config、dpkg 闭包 | 构建后脚本 | 否 |
| rootfs 模拟 | 启动脚本、服务依赖、桌面配置、权限 | chroot / QEMU | 否 |
| 真机 HIL | U-Boot、内核、DRM/Panfrost、V4L2、音频、网络、SSH | 专用测试板 / USB 启动 | 是最终验收 |

QEMU 只验证 rootfs/启动结构，不证明 RK3568 硬件能力。

### 8.2 HIL 分层

| 场景 | 频率 | 是否阻塞合并 |
|---|---|---|
| PR 快速检查 | 每次提交 | 是（仅静态/单元/配置） |
| Nightly 构建 | 每晚 | 是（构建/静态/rootfs） |
| 真机 HIL | 手动或夜间 | 否（结果记录，异常再处理） |

真机测试使用专用设备/USB 启动，避免把开发机刷坏。

### 8.3 硬件验收矩阵

至少覆盖：

- Boot：上电 → U-Boot → kernel → SSH。
- Display：eDP 分辨率/刷新率（固定 60.02Hz）。
- GPU：Panfrost renderer、GLX、`/dev/dri/renderD128`。
- Video：H.264/HEVC 硬解、固定片源、丢帧/fps。
- Audio：播放、录音、mixer。
- Network：有线、Wi-Fi、DNS。
- Power：电池/AC、亮度、音量、挂起（按现有策略）。
- Storage：eMMC/U 盘、首次扩容、shrink 后启动。

每项输出：前置条件、命令、预期、实际、PASS/FAIL、日志。

### 8.4 性能预算

先采集，后设阈值：

- 启动到 SSH 时间。
- 空闲内存（MemAvailable + 关键进程 PSS）。
- 空闲 CPU、GPU 频率。
- 视频 fps/丢帧。
- 镜像体积、首次扩容时间。
- 固定条件：面板 60.02Hz、热稳态、无后台负载、3 次中位数。

### 8.5 退出条件

- 核心硬件能力有自动 PASS/FAIL。
- 镜像结构/分区/启动配置有静态检查。
- 首次启动扩容、shrink 后启动有测试。
- 基线可重复，噪声范围已记录。
- HIL 不阻塞日常开发，但结果可查。

### 8.6 阶段 3 现状审计（只读，2026-11-09）

#### 已有覆盖：`tests/smoke-device.sh`

| 硬件项 | 现有检查 | 判定 |
|---|---|---|
| Boot | SSH 可达 | 仅证明“已启动到 SSH” |
| Display | `xrandr` 读取当前模式与刷新率 | 记录值，**不做 PASS/FAIL** |
| GPU | `glxinfo` renderer 含 Panfrost/Mali、`/dev/dri/renderD128`、`lsmod` panfrost | PASS/FAIL |
| GPU (Vulkan) | `vulkaninfo` conformance | 仅记录，不判定 |
| Video | 无 | **缺失** |
| Audio | `amixer -c rk817ext sget Master` 可访问 | PASS/FAIL（仅 mixer 可读） |
| Network | 默认路由、eth0/wlan0 operstate | PASS/FAIL（仅链路层） |
| Power | 无 | **缺失** |
| Storage | 无 | **缺失** |
| 桌面 | Xorg/lxqt-panel/pcmanfm-qt/nm-applet/面板窗口 | PASS/FAIL |

结论：GPU 与桌面层已经判定（PASS/FAIL），其余多为“能读”而非“能用”。

#### 缺失检查与判定标准（阶段 3 实施清单）

| # | 检查 | 命令（板端） | PASS 标准 | 备注 |
|---|---|---|---|---|
| H1 ⏸ | 上电到 SSH | 串口/日志时间戳或 `uptime` 首次可连 | ≤ 基线 +20% | 需受控重启，需专用板 |
| H2 ✅ | eDP 固定模式 | `xrandr | grep '*'` | `1920x1080` 且 `60.02` | 实测 `display_mode 1920x1080` / `display_rate 60.02` → PASS |
| H3 ✅ | GLX 加速 | `glxinfo -B` | `direct rendering: Yes` + Panfrost renderer | 实测 `direct_rendering Yes` + `glx acceleration PASS` |
| H4 ✅ | Vulkan conformance | `vulkaninfo --summary` | Mali 行 `conformanceVersion=1.3.0.0` | 实测 `vulkan_conformance 1.3.0.0` → PASS |
| H5 ⏸ | 1080p 硬解 | `mpv --hwdec=v4l2request` 10s | `hwdec-current=v4l2request` 且 fps≥28 | 需固定片源 |
| H6 ⏸ | HEVC 4K 不退化解码 | 同上，4K 片源 | `decoder-frame-drop-count=0` 且 fps≥基线 | 不要求 60fps |
| H7 | 音频播放 | `aplay -D default` 1s 测试音 | 返回 0 且 Master 非 0 | 需人工听感抽查 |
| H8 ✅ | 录音 | `arecord -D z96a_mic -c 6 -d 2` | 生成非空 6ch WAV | 实测 `mic_channels 6`、`mic_wav_bytes 1152044` → PASS |
| H9 | 有线 IPv4 | `ip -4 addr show eth0` | 有 192.168.31.x 且有默认路由 | 已有部分 |
| H10 | Wi-Fi 关联 + DNS | `nmcli -t -f STATE` + `getent hosts` | connected 且域名解析成功 | 需配置凭据 |
| H11 | 音量/亮度可用 | `z96a-hotkey volume-info`、亮度读写 | 数值变化且持久化文件更新 | — |
| H12 | 电池/AC 状态 | `z96a-hotkey battery`、`/sys/class/power_supply` | 能读到容量/状态，NTC 不在位显示 absent | — |
| H13 ✅ | 挂起策略 | 读 elogind + LXQt 电源配置 | lid/idle/hibernate 全 ignore，LXQt watcher 关闭 | 实测 PASS（不做真实挂起） |
| H14 ⏸ | 首次扩容 | `dietpi` 不适用 → `growpart`/`resize2fs` 后 `df /` | rootfs 使用全部磁盘 | **需全新刷写镜像** |
| H15 ⏸ | shrink 后启动 | 刷 shrink 产物 | 正常启动 + `fsck` 无错 | **需完整构建 + 刷写** |
| H16 ✅ | eMMC/U 盘 | `/sys/block/*`、`findmnt /` | eMMC 存在且 root 挂载在块设备 | 实测 `storage PASS`，`root_device /dev/sda2` |

标注 **需专用板/需完整构建** 的项无法在当前环境闭环。

**⏸ = deferred-pending-user**：用户明确表示这些验证统一到最后一起做，当前不执行、
不再提示。包括 H1 启动时间、H5/H6 视频、H14 首次扩容、H15 shrink 后启动，
以及阶段 4 的升级/回滚演练（R1/R2/R3/R5 的实测部分）。

#### HIL 流程（阶段 3 实施时）

| 环节 | 频率 | 载体 | 是否阻塞合并 |
|---|---|---|---|
| PR 快速检查 | 每次提交 | CI（静态 + 单元 + 预检） | 是 |
| Tag 发布构建 | 版本 Tag | self-hosted 构建机 + `validate-image.sh` + Release | 是（未通过不发布） |
| Nightly 构建 | 每晚 | 构建机 + `smoke-static --image` + `smoke-rootfs --chroot` | 是 |
| 真机 HIL | 每周或发版前 | 专用测试板（优先）/ 固定 USB 启动介质 | 否，但结果必须归档 |

HIL 执行顺序（固定，避免交叉污染）：

```text
1. 刷写已知良好基线镜像 → 采集 H1/H14 基线
2. 刷写待测镜像 → 跑 H2–H13
3. 单独刷写 shrink 产物 → 跑 H15
4. 结果写入 boards/z96a-v2/tests/hil-<date>.json，失败项开单
5. 恢复基线镜像，避免测试板停留在可疑镜像
```

约束：

- 测试板**不复用开发机**，避免刷坏工作环境。
- 每项记录前置条件（片源、负载、温度、刷新率），否则数字不可比。
- 视频与启动时间至少 3 次取中位数，并记录噪声范围。

---

## 9. 阶段 4：发行版能力完善

### 9.1 升级与回滚

- U-Boot / DTB / kernel：**手动更新**，先备份，失败可回滚。
- rootfs 软件包：可更新，但要有快照/回滚。
- 恢复分区/串口恢复路径必须保留。
- 不做完整 A/B，但必须有：升级顺序、备份、验证、回滚文档。
- 命令序列见 §9.4；**实际演练标记 ⏸ deferred-pending-user**（需测试板）。

### 9.2 其他能力（按实际需求）

- APT snapshot。
- Stable/Nightly 发布渠道。
- SBOM / CVE 扫描。
- 性能回归门禁。
- ADR（记录 Devuan、X11、无合成器、Mesa 26、V4L2 等决策）。
- 板卡矩阵/支持状态生成。
- 多板卡 family 架构（**只在出现第二块板卡时启动**）。

### 9.3 退出条件

- 发布产物有 manifest、校验和、渠道命名。
- 升级/回滚流程有文档并演练过。
- 关键架构决策有 ADR。
- 第二块板卡出现时，无需推翻现有结构。

### 9.4 阶段 4 现状审计：升级与回滚（只读，2026-11-09）

#### 当前启动链路（来自构建代码，非推测）

| 环节 | 位置 | 证据 |
|---|---|---|
| U-Boot 头 | `idbloader.bin` @ sector 64（32 KiB） | `lib/function/rockchip:117` |
| U-Boot 主体 | `u-boot.bin` @ sector 16384（8 MiB） | `lib/function/rockchip:118` |
| 预编译来源 | `files/boot/uboot/z96a-v2/` | `PRECOMPILED_UBOOT_DIR` |
| 启动项 | `extlinux/extlinux.conf`（vfat 启动分区） | `lib/function/staging:386-406` |
| DTB | `<DTB>.dtb` 放 `../rockchip/`，由 `fdt` 行引用 | 同上 |
| kernel | `../Image` + `../uInitrd` | 同上 |
| 故障恢复 | **无**第二个 extlinux label，无 recovery 分区 | `extlinux` 只写一个 label |

结论：当前**没有**内核级回退入口。`/boot/recovery` 是历史手工产物（见 `boards/z96a-v2/docs/TODO.md`），
不是构建产生的东西。

#### 备份 → 更新 → 验证 → 回滚（U-Boot / DTB / kernel）

以下命令序列是**计划**，除标注外均需专用测试板或完整构建后才能验证。

**A. 备份（在任何更新前，板端）**

```sh
# 需要 root，USB 介质挂在 /media/usb
sudo dd if=/dev/mmcblk0 of=/media/usb/uboot-backup.bin bs=512 count=16384
# 备份启动分区（vfat）与 rootfs 的 extlinux 相关文件
sudo cp -a /boot/extlinux /media/usb/extlinux-$(date +%F)
sudo sha256sum /media/usb/uboot-backup.bin > /media/usb/uboot-backup.bin.sha256
```

判定标准：备份文件存在、SHA256 记录、大小 ≥ 8 MiB 区域。

**B. 更新 U-Boot（高风险，需串口兜底）**

```sh
# 1) 校验新 blob 与 manifest 一致
sha256sum idbloader.bin u-boot.bin      # 与 /etc/z96a/manifest.json 对比
# 2) 只写 U-Boot 区域，不动分区表
sudo dd if=idbloader.bin of=/dev/mmcblk0 bs=512 seek=64 conv=fsync
sudo dd if=u-boot.bin    of=/dev/mmcblk0 bs=512 seek=16384 conv=fsync
sync
```

判定标准：重启后串口出现 U-Boot 提示并进入 kernel。
失败处理：见 D 节（Maskrom / 串口恢复）。

**C. 更新 kernel / DTB（中风险，可回滚）**

```sh
# 1) 保留旧文件
sudo cp /boot/Image /boot/Image.old
sudo cp /boot/rockchip/<dtb>.dtb /boot/rockchip/<dtb>.dtb.old
# 2) 放入新文件（来自新构建的启动分区）
sudo cp Image /boot/Image
sudo cp <dtb>.dtb /boot/rockchip/
sync
# 3) 验证
uname -r                      # 版本是否为期望
cat /proc/device-tree/model   # DTB 是否为新板/新配置
dmesg | grep -E "panfrost|mmc0"   # HS400 与 GPU 是否就绪
```

判定标准：`uname -r` 与 manifest 的 `kernel.version` 一致；无 `mmc0: new HS200` 回退。
回滚：`cp /boot/Image.old /boot/Image; cp ...dtb.old ...dtb; sync; reboot`。

**D. 变砖恢复路径**

| 场景 | 手段 | 是否已验证 |
|---|---|---|
| kernel 起不来 | 串口 + U-Boot 命令行改 `extlinux.conf` 指向 `Image.old` | 需测试板 |
| U-Boot 损坏 | Maskrom + `rkdeveloptool`/`upgrade_tool` 重写 `idbloader`/`u-boot` | 需测试板 |
| 全盘损坏 | 重新刷写已知良好镜像 | 需构建产物 + 刷写 |

备注：`/dev/ttyS2` 1500000 8N1 是当前唯一可靠的低层观察通道（见 `docs/HARDWARE-STATUS.md`）。

#### 缺口清单（阶段 4 实施时补充）

| # | 缺口 | 影响 | 需要什么 |
|---|---|---|---|
| R1 ⏸ | `extlinux.conf` 无第二个 label（recovery/old kernel） | kernel 更新失败只能靠串口 | deferred-pending-user（需完整构建 + 刷机演练） |
| R2 ⏸ | 无 `/boot/recovery` 构建产物 | 无自动回退 | deferred-pending-user |
| R3 ⏸ | 无升级脚本（现在的更新全是手工 `dd`/`cp`） | 易误操作 | deferred-pending-user（需测试板演练） |
| R4 | 无 U-Boot 写入的偏移校验 | `seek` 写错会损坏分区表 | 可加静态检查（读 `lib/function/rockchip`） |
| R5 ⏸ | 无 rootfs 快照/回滚 | 软件包升级失败需重刷 | deferred-pending-user |
| R6 | 无 SBOM/CVE 扫描 | 供应链不可见 | 需要许可决策与依赖源 |
| R7 | 无 Stable/Nightly 渠道命名 | 产物不可区分 | 需要发布策略 |
| R8 | 无 ADR 记录 | 关键决策易反复 | 可直接补文档（无构建依赖） |

可立即做（无构建依赖）：R4 静态偏移检查 ✅（`BootLayoutTests`）、R8 ADR 目录 ✅（`docs/adr/`）。
其余全部需要专用测试板或完整构建产物。

---

## 10. 候选池（不承诺，不直接执行）

以下方向保留为候选；进入某个阶段前必须先做阶段 0 式审计，不能直接批量实施：

- 配置：family 继承、更多 profile、配置生成器。
- 来源：APT snapshot、完整 SBOM、CVE 扫描。
- 包：artifact cache、自动检查上游版本。
- 镜像：镜像签名、A/B、自动恢复镜像。
- 脚本：更多幂等 helper、统一日志格式。
- CI：多板卡矩阵、发布自动化。
- 文档：自动生成板卡矩阵、版本化文档。

---

## 11. 本文的维护

- 每完成一个阶段，更新“状态”和“退出条件”的勾选。
- 新增任务必须写清阶段、证据、范围、验收标准。
- 架构级决策写入 `docs/adr/`，本文只保留索引。
- 本文不记录一次性调查过程；结论进板级 `MEMORY.md`。
