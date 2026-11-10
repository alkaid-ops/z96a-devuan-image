# 文档索引

本仓库按板卡组织。**全局文档在本目录，板级文档在 `boards/<board>/docs/`。**
新对话先读根目录 `AGENTS.md`，再按需打开对应板卡的文档。

## 全局文档

| 文档 | 内容 |
|---|---|
| [`BOARD-GUIDE.md`](BOARD-GUIDE.md) | 新增板卡的标准流程与目录约定（必读） |
| [`OPTIMIZATION.md`](OPTIMIZATION.md) | **正式工程化改造方案**（阶段 0–4、执行规则、验收门禁） |
| [`CI-RELEASE.md`](CI-RELEASE.md) | **GitHub Actions**：Tag 自动构建、缓存布局、Release 发布门禁 |
| [`adr/`](adr/README.md) | 架构决策记录（ADR） |
| [`../boards/README.md`](../boards/README.md) | `boards/` 目录说明 |
| [`../README.md`](../README.md) | 早期上游说明（仅供参考） |

## 板级文档

| 板卡 | 入口 |
|---|---|
| `z96a-v2` | [`../boards/z96a-v2/README.md`](../boards/z96a-v2/README.md) |
| `z96a-v2` 已验证事实 | [`../boards/z96a-v2/docs/MEMORY.md`](../boards/z96a-v2/docs/MEMORY.md) |

## 维护规则

- 板级信息只写在 `boards/<board>/` 或该板卡在 `files/rootfs-overlay/<board>/` 的 overlay 里。
- 全局文档不写具体板卡的引脚、DTS、路径；需要时链接到板级文档。
- 数据只留一份：已验证结论进板级 `MEMORY.md`，未完成事项进板级 `TODO.md`。
- 过期计划、一次性调查过程不保留；结论保留并在 `MEMORY.md` 标注。
