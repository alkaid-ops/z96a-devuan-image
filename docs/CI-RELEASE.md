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

镜像构建使用 GitHub-hosted `ubuntu-24.04` runner。实际构建前会检查剩余磁盘、
宿主机 loop/ext4 挂载与 privileged Docker；验证记录见 hosted-runner-probe 工作流。

要求与限制：

- 运行环境固定 `ubuntu-24.04`；工作流先回收预装 SDK 并要求根文件系统至少 60 GiB 可用。
- 必须能使用 Docker、特权容器、loop device 与 ext4 loop mount；探针已成功验证。
- 工作流自动构建固定构建根镜像：

  ```sh
  docker build -f boards/z96a-v2/tools/Dockerfile -t z96a-build:local .
  ```

- 出站网络：容器内 apt（Devuan 主源与 `excalibur-backports`）、应用 vendor URL
  与 GitHub 下载；输入 Release 避免重新构建内核/应用包，但不替代 apt 网络。
- 安装 `rsync`、`xz`、`python3`、`git`。
- Actions runner 需支持 `actions/checkout@v7` 系列（Node 24）。
- 同一时间只运行一个镜像构建；工作流已用 `concurrency` 串行化。
- 构建容器会以 root 写入 `output/`。工作流因此使用 `clean: false`，并在容器内
  显式清空 `output/` 等构建目录；runner 用户不要依赖 `git clean` 删除这些文件。
- 完整镜像构建仅由受控的手动 workflow 或版本 Tag 触发；PR/push 只跑轻量 CI。

## 持久缓存布局

GitHub-hosted runner 每次为临时机器，因此输入通过 `actions/cache` 保留，
缓存 miss 时从不可变的 `inputs-v1` Release 下载并逐文件校验。缓存 key 为
`z96a-inputs-v1-Linux`；更新输入时发布新 `inputs-vN` 并同步更新 workflow key。
chroot 缓存在当前 hosted job 内使用，不跨 job 持久保存。

```text
$Z96A_CACHE_ROOT/
├── input/
│   ├── packages/     内置应用 .deb（含内部 build artifact 包）
│   ├── tarball/      devuan-excalibur-minimal-rootfs-arm64.tar.xz
│   └── debs/         linux-image-*.deb、linux-headers-*.deb、u-boot-*.deb
└── chroot/           chroot-cache.sh 的 p1/p2 结果（当前 job 内可重建）
```

生成输入 Release（仅在维护输入版本时执行）：

```sh
STAGE=/tmp/z96a-inputs-v1
mkdir -p "$STAGE"/{packages,tarball,debs}
cp files/rootfs-overlay/z96a-v2/opt/z96a/packages/*.deb "$STAGE/packages/"
cp output/tarball/devuan-excalibur-minimal-rootfs-arm64.tar.xz "$STAGE/tarball/"
cp output/z96a-v2/linux-image-*.deb output/z96a-v2/linux-headers-*.deb \
   output/z96a-v2/u-boot-*.deb "$STAGE/debs/"
(cd "$STAGE" && find packages tarball debs -type f -print0 | sort -z |
  xargs -0 sha256sum > SHA256SUMS.inputs)
gh release create inputs-v1 "$STAGE"/{packages,tarball,debs}/* \
  "$STAGE/SHA256SUMS.inputs" --title 'Build inputs v1' \
  --notes 'Immutable, SHA256-verified inputs for the Z96A image build.'
```

输入 Release 是**构建输入**，不是可选加速：

- `make image` 需要 rootfs tarball、kernel deb、U-Boot deb 和内置应用 deb。
- 内部应用（`build artifact` 列）没有下载 URL，只能由缓存提供。
- `ci-prepare-inputs.sh` 会校验 `packages-sources.tsv`、`SHA256SUMS` 与所有
  应用 deb 的 SHA256；缺失或损坏立即失败，不会继续构建。

chroot 缓存（`chroot-cache.sh`）只用于加速安装阶段。缓存 key 覆盖板级配置、
TOML、defconfig、features、trim、userscripts、overlay、包校验和 kernel deb；
missing 或 p1 缺 DTB 时自动回退完整 chroot。缓存损坏不会产出错误镜像。

输入缓存是“当前应发布的输入”：升级 kernel、U-Boot、rootfs tarball 或内置
应用 deb 后必须同步更新，否则 Tag 构建会继续使用旧输入。chroot 缓存可以
随时清空，只影响耗时。更新输入后必须新建 Release tag（例如 `inputs-v2`）、
修改 workflow 中的 Release 与 cache key，再验证下载。

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
