# CI 与发布（GitHub Actions）

目标：推送版本 Tag 后自动构建 Z96A 镜像、执行完整镜像校验、校验通过后发布
GitHub Release。PR 与普通 push 只跑轻量检查，不构建整张镜像。

## 触发方式

| 工作流 | 触发 | 产物 | 是否发布 |
|---|---|---|---|
| `.github/workflows/ci.yml` | PR、push、手动 | 无镜像 | 否 |
| `.github/workflows/build.yml` | Actions 手动触发 | Actions artifact | 否 |
| `.github/workflows/release.yml` | 推送 `v*` Tag | Actions artifact + GitHub Release | 是 |
| `.github/workflows/build-image.yml` | 被上面两个工作流调用 | — | 由调用方决定 |

Tag 格式：`vX.Y` 或 `vX.Y.Z`（可带 `-rc1` 之类后缀，后缀会标记为 prerelease）。
Tag 必须指向默认分支上的提交；`release.yml` 会检查 `git merge-base --is-ancestor`。
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
- 完整镜像只由手动 workflow 或版本 tag 触发；push/PR 只跑轻量 CI。

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

**锁文件 `config/inputs.lock` 是总装的唯一输入**，由人工维护（策略 A）：

```toml
kernel_release    = "kernel-7.2.12-r3"
kernel_sums       = "…"   # SHA256SUMS.kernel 的 sha256
base_apps_release = "base-apps-20261113"
base_apps_sums    = "…"
uboot_release     = "uboot-fitfix-v3-p1"
uboot_sums        = "…"
```

更新流程：组件 workflow 跑完 → 人工检查产物 → 改 lock 对应两行 → 提交 →
触发 `build.yml`（或打 tag）。总装不会查询 “latest”，也不自动改 lock。

`make image` 不编译内核：kernel/U-Boot 的 deb 全部来自 lock 指向的 Release。

## 缓存设计

runner 是临时的，所有缓存都用 `actions/cache`：

| 缓存 | Key | 内容 | 失效条件 |
|---|---|---|---|
| 输入组件 | `z96a-inputs-<sha256(inputs.lock)>-<arch>` | 三个组件的 deb/tarball/blobs + 校验清单 | lock 任意一行变化 |
| chroot | `z96a-chroot-<sha256(inputs.lock)>-<arch>` | `output/cache/chroot`（stage1 保存的已装包 rootfs） | lock 变化；内核更新会使缓存失效（内核 deb 在 chroot 内安装） |

- `ci-fetch-inputs.sh` 先从 lock 校验三个组件的 `SHA256SUMS.*`，再逐资产校验；
  缓存命中时用 `.lock-sha` 与本地清单做离线复验，不访问网络。
- 输入缓存约 1.3 GiB；chroot 缓存由 `actions/cache` 内部压缩，仍受仓库 10 GiB
  缓存上限约束，维护时留意淘汰旧 key。
- Dockerfile 构建层可由 runner 的 docker layer cache 承担；不再使用 binfmt/QEMU。

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
└── chroot/          stage1 的已装包 rootfs（可随时清空）
```

## Tag 发布流程

```text
push tag vX.Y.Z
  → release.yml / tag job：校验 Tag 格式与分支来源
  → build-image.yml：
      checkout → runner 检查 → 播种输入 → preflight → 单测 → secret scan
      → build-in-container.sh image（RELEASE_CHANNEL=stable, RELEASE_TAG=<tag>）
      → ci-validate-image.sh（DTB/extlinux/ext4/manifest/SBOM/Mesa/固件/包闭包）
      → ci-collect-image.sh（SHA256、耗时、build-evidence.json）
      → upload-artifact
  → release.yml / publish job：下载 artifact、复核 SHA256、创建 GitHub Release
```

发布资产：

```text
*.img.xz
*.img.xz.sha256
manifest.json
sbom.json
build-evidence.json
```

`manifest.json` 的 `release_info` 会记录 `channel` 与 `tag`。

## 失败与安全规则

- 任一前置检查、构建、校验失败 → 不创建 Release。
- Release job 只在 `needs: build` 成功后运行，且单独授予 `contents: write`；
  构建 job 只有只读权限。
- 第三方 Actions 固定到完整 commit SHA。
- 构建日志（`output/ci/build.log`）随 artifact 上传；失败时另有日志 artifact。
- 校验失败不会上传镜像 artifact，避免误用未验证产物。
- 需要重跑时删除并重新推送同一 Tag（或发新 Tag）；工作流按 Tag 串行执行。

## 手动构建

`build.yml` 仅生成 Actions artifact，不创建 Release，用于验证 runner、缓存与
输入是否就绪。参数：

- `channel`：`nightly` / `stable` / `test`，写入 manifest。
- `validate`：是否执行 loop 挂载镜像校验，默认开启。

## 与本地构建的对应关系

| CI 步骤 | 本地命令 |
|---|---|
| 播种输入 | `make rootfs/kernel/uboot` 的产物 + `fetch-packages.sh` |
| 构建镜像 | `boards/z96a-v2/tools/build-in-container.sh image` |
| 镜像校验 | `boards/z96a-v2/tools/ci-validate-image.sh <img.xz>` |
| 证据收集 | `boards/z96a-v2/tools/ci-collect-image.sh --log <log>` |

CI 不执行刷机，不修改 eMMC、U-Boot 分区表、GPT、内核或 DTB。
