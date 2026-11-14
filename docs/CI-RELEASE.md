# CI 与发布（GitHub Actions）

目标：将 U-Boot、kernel、base/apps、整镜像临时构建、整镜像正式发布分成五个可独立
操作的阶段。正式发布严格复用阶段 4 的同一个 Actions artifact，不重新组装镜像。

## 触发方式

| 工作流 | 触发 | 产物 | 是否发布 |
|---|---|---|---|
| `.github/workflows/ci.yml` | PR、push、手动 | 无镜像 | 否 |
| `.github/workflows/kernel.yml` | Actions 手动触发 | kernel 组件 Release | 阶段 2 |
| `.github/workflows/base-apps.yml` | Actions 手动触发 | base/apps 组件 Release | 阶段 3 |
| `.github/workflows/uboot.yml` | Actions 手动触发 | U-Boot 组件 Release | 阶段 1 |
| `.github/workflows/image-temp.yml` | Actions 手动触发 | 90 天 Actions artifact | 阶段 4 |
| `.github/workflows/publish-image.yml` | Actions 手动触发，指定阶段 4 run ID | GitHub Release | 阶段 5 |
| `.github/workflows/build-image.yml` | 被 `image-temp.yml` 调用 | — | 可复用镜像组装实现 |
| `.github/workflows/ci.yml` | PR、普通 push、手动 | 检查报告 | 否 |
| `.github/workflows/probe.yml` | Actions 手动触发 | runner 探测报告 | 否 |

Tag 格式：`vX.Y` 或 `vX.Y.Z`（可带 `-rc1` 之类后缀，后缀会标记为 prerelease）。
正式版本 Tag 由阶段 5 从阶段 4 的源码提交创建；发布流程不使用 tag push 作为构建触发器。
已发布 Tag 不应移动或删除。

可选配置仓库 Settings → Secrets and variables → Actions：`Z96A_SSH_KEY`（公钥）；
`Z96A_ROOT_PASSWORD`（root SSH 密码）；`Z96A_WIFI_SSID` 与 `Z96A_WIFI_PASSKEY`
（必须成对提供）。未设置 SSH key 和 root 密码时，镜像不允许 SSH 登录；本地桌面
登录不受影响。仓库不包含默认密码、私钥或 Wi-Fi 凭据。

## Runner 要求

镜像构建使用 GitHub-hosted **arm64** runner（`ubuntu-24.04-arm`），rootfs 是原生
执行，不再经过 QEMU/binfmt；构建前仍会检查剩余磁盘、loop device 与 privileged
Docker（探针见 hosted-runner-probe）。

- 固定 `ubuntu-24.04-arm`；根文件系统至少 60 GiB 可用。
- 必须能使用 Docker、特权容器、loop device 与 ext4 loop mount。
- 工作流自动构建固定构建根镜像：
  `docker build -f boards/z96a-v2/tools/Dockerfile -t z96a-build:local .`
- 出站网络：apt（Devuan 主源/backports）、vendor URL、GitHub Release 下载。
- 同一时间只运行一个镜像构建（`concurrency: z96a-image-build`）。
- 构建容器以 root 写 `output/`，workflow 使用 `clean: false` 并在容器内清理。
- 完整镜像只由 `image-temp.yml` 手动触发；push/PR 只跑轻量 CI。

## 组件发布与 inputs.lock

镜像总装不再使用单体 `inputs-vN`，而是三个独立组件 Release，全部标为
**prerelease**（它们是构建输入，不是成品）：

| 组件 | Workflow | Tag | 资产 |
|---|---|---|---|
| kernel | `kernel.yml` | `kernel-<ver>-r<run>` | linux-image/headers deb、`SHA256SUMS.kernel`、`kernel-meta.json` |
| base+apps | `base-apps.yml` | `base-apps-<date>` | rootfs tarball、应用 deb、`SHA256SUMS.base` |
| U-Boot | `uboot.yml` | `uboot-<firmware-tag>-p<N>` | u-boot deb、idbloader/u-boot blob、`SHA256SUMS.uboot`、`uboot-meta.json` |

U-Boot 固件仍由 `alkaid-ops/z96a-rk3568-uboot` 的 `fitfix-vN` Release 提供；
`uboot.yml` 负责下载校验、与固定 idbloader 配对、打成 deb 并发布 `-pN` 打包版本。
固件版本与打包版本分离，`uboot-meta.json` 记录源仓库/tag 与两个 blob 的 sha256。

默认锁文件 `config/inputs.lock` 由人工维护；阶段 4 也允许显式选取三个组件 tag：

```toml
kernel_release    = "kernel-7.2.12-r3"
kernel_sums       = "…"   # SHA256SUMS.kernel 的 sha256
base_apps_release = "base-apps-20261113"
base_apps_sums    = "…"
uboot_release     = "uboot-fitfix-v3-p1"
uboot_sums        = "…"
```

默认更新流程：组件 workflow 跑完 → 人工检查产物 → 改 lock 对应两行 → 提交。
阶段 4 可直接使用 lock，或显式传入三个 tag；显式组合会现场计算各自的清单摘要，
生成仅存在于 runner 的临时 lock，并把组合清单作为 `components.json` 留在 artifact 中。
两种路径都不查询 “latest”，也不会自动修改仓库 lock。

`make image` 不编译内核：kernel/U-Boot 的 deb 全部来自 lock 指向的 Release。

## 缓存设计

runner 是临时的，输入缓存使用 `actions/cache`：

| 缓存 | Key | 内容 | 失效条件 |
|---|---|---|---|
| 输入组件 | `z96a-inputs-<sha256(inputs.lock)>-<arch>` | 三个组件的 deb/tarball/blobs + 校验清单 | lock 任意一行变化 |

- `ci-fetch-inputs.sh` 先从 lock 校验三个组件的 `SHA256SUMS.*`，再逐资产校验；
  缓存命中时用 `.lock-sha` 与本地清单做离线复验，不访问网络。
- 输入缓存约 1.34 GB；仓库缓存容量和淘汰情况需根据实际配额检查。
- CI 显式设置 `CHROOT_CACHE=0`，不恢复、不保存完整 rootfs；本地缓存机制不受影响。
  旧 Actions 缓存不会被本工作流删除。
- GitHub-hosted runner 每次新建，不应假设 Docker 层跨运行持久保存。

输入缓存布局：

```text
$Z96A_CACHE_ROOT/
├── input/
│   ├── debs/        linux-image/headers、u-boot deb
│   ├── packages/    内置应用 .deb
│   ├── tarball/     devuan-excalibur-minimal-rootfs-arm64.tar.xz
│   ├── blobs/       u-boot.itb / idbloader
│   ├── manifests/   SHA256SUMS.kernel / .base / .uboot
│   └── .lock-sha    该缓存对应的 inputs.lock 摘要
```

CI 在文件系统收缩之后，先将镜像裁至完整 512 字节扇区边界（只移除最后
一个完整扇区之后的尾随字节），再直接对原始镜像执行 loop 检查；失败即终止。
CI 使用 `xz -6`（原先是默认级别 6 加 `-e`），然后检查 XZ 完整性、SHA256
和 GitHub Release 资产大小限制。压缩率及耗时以实际构建为准；`validate=false`
只跳过原始镜像的结构校验，不跳过压缩文件检查。本地默认压缩设置保持不变。

## 五阶段正式发布

```text
1. uboot.yml       → uboot-<firmware>-pN
2. kernel.yml      → kernel-<version>-rN
3. base-apps.yml   → base-apps-<date>
4. image-temp.yml  → build/validate once → z96a-image-<run-id>-<attempt> artifact
5. publish-image.yml(run_id, vX.Y.Z) → download that exact artifact → verify → Release
```

阶段 4 的三个组件 tag 必须全部提供或全部留空。留空时使用 `config/inputs.lock`；
提供时工作流下载三个 `SHA256SUMS.*`，计算摘要并生成 runner 临时 lock。该 lock 的
摘要进入缓存键，组合写入 `components.json` 随 artifact 保留，不新增仓库组合配置文件。

阶段 5 必须输入阶段 4 的 run ID。工作流检查 run 成功、来源为 `image-temp.yml`、
artifact 名称与 run ID/attempt 精确匹配且未过期；之后复核 XZ、SHA256、资产大小、
构建证据，并对下载的同一镜像再做 loop 结构校验。只有全部通过后才创建或更新目标
版本草稿并发布。现有 `release.yml` 的 `v*` 自动重建入口已移除，避免发布 tag 时再次
组装镜像。Release tag 使用发布时默认分支目标；实际镜像源码提交以 `build-evidence.json`
为准，两者可能因阶段 4 之后的工作流维护提交而不同。stage-4 artifact 保留 90 天；
过期后必须重新执行阶段 4。

发布资产：

```text
*.img.xz
*.img.xz.sha256
manifest.json
sbom.json
build-evidence.json
components.json
build.log
```

`manifest.json` 的 `release_info` 会记录 `channel` 与 `tag`。`build-evidence.json` 记录
阶段 4 实际构建提交；发布工作流本身不调用镜像构建脚本。

## 失败与安全规则

- 阶段 4 任一前置检查、构建、校验失败 → 不产生可供发布的成功 artifact。
- 阶段 5 仅在精确来源 artifact 全部验证后获得 `contents: write` 权限并发布。
- 第三方 Actions 固定到完整 commit SHA。
- 构建日志（`output/ci/build.log`）随 artifact 上传；失败时另有日志 artifact。
- 校验失败不会上传镜像 artifact，避免误用未验证产物。
- artifact 过期或构建内容需要变化时，重新运行阶段 4 并使用新 run ID；已发布版本不覆盖。

## 与本地构建的对应关系

| CI 步骤 | 本地命令 |
|---|---|
| 播种输入 | `make rootfs/kernel/uboot` 的产物 + `fetch-packages.sh` |
| 构建镜像 | `boards/z96a-v2/tools/build-in-container.sh image` |
| 镜像校验 | `boards/z96a-v2/tools/ci-validate-image.sh <img.xz>` |
| 证据收集 | `boards/z96a-v2/tools/ci-collect-image.sh --log <log>` |

CI 不执行刷机，不修改 eMMC、U-Boot 分区表、GPT、内核或 DTB。
