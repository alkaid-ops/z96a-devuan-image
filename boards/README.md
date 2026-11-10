# boards/ 目录

每块板卡一个子目录，放**构建输入之外**的板级资产：文档、板级 userscript、开发工具、
测试、守护进程源码。真正的构建输入在本仓库约定位置（`lib/boards/`、`defconfig/`、
`files/rootfs-overlay/`、`patches/`），详见 [`../docs/BOARD-GUIDE.md`](../docs/BOARD-GUIDE.md)。

## 约定

```text
boards/<board>/
├── README.md                 板卡总览与构建输入映射
├── docs/                     板级文档
├── userscripts/uscripts      板级镜像定制（run_function0..3）
├── tools/                    板级开发/测试工具
├── tests/                    板级测试
├── patches/                  板级包补丁（按需）
└── power-policy/             板级守护进程源码（如适用）
```

规则：

- 板级内容只放本板目录，不写进别的板卡。
- 通用脚本不写板级条件；需要定制时实现板级 `userscripts/uscripts`。
- `boards/` 下的任何内容都**不会**被拷进镜像根文件系统。

## 现有板卡

| 板卡 | 目录 |
|---|---|
| Sunniwell Z96A Type-C（RK3568） | [`z96a-v2/`](z96a-v2/) |
