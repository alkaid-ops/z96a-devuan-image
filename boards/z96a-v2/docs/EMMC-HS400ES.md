# eMMC HS400ES 200MHz

状态：2026-11-14 启用为生产默认。

## 配置

```text
模式：HS400 / HS400ES
频率：200MHz
总线：8-bit
电压：1.8V
TXCLK：0x29000008（tap 0x8）
RXCLK：0x28000000
STRBIN：0x09000004（tap 4）
CMDOUT：0x00000000
DLL：LOCKED=1, TIMEOUT=0
```

## 补丁

```text
patches/git/z96a-v2/linux-add_sunniwell_z96a/0031-rk3568-hs400-txclk-tap-08.patch
patches/git/z96a-v2/linux-add_sunniwell_z96a/0032-z96a-emmc-hs400es-200mhz.patch
```

- `0031`：RK3568 `revision == 0` 且 HS400/HS400ES 时，TXCLK tap 固定为 `0x8`；HS200 路径不变。
- `0032`：生产 DTS 的 `&sdhci` 增加 `mmc-hs400-1_8v`、`mmc-hs400-enhanced-strobe`；`max-frequency` 保持 200MHz。

## 验证摘要

| 项目 | 结果 |
|---|---|
| HS200 200MHz tap 0x8 | 通过 |
| HS400ES 200MHz tap 0x8 | 通过 |
| 100MHz A/B/A（tap 0x8 vs 0x10） | tap 0x8 3/3 通过；tap 0x10 复现 DATA_CRC |
| 200MHz TXCLK 扫描 | `0x04–0x0C` 通过；`0x0E/0x10` DATA_CRC |
| 200MHz STRBIN 扫描 | tap 4/6/8 均通过 |
| 测试区 SHA256 | 写入后读回与原文一致 |
| CRC / Timeout / ADMA | 通过项均为 0 |

TXCLK `0x08` 在稳定窗口内写入吞吐最高（约 129 MB/s）；`0x0A` 原始读取略高（约 227 MB/s），差异在单次测量噪声范围内。

## 历史

早期 `0010-z96a-emmc-hs400.patch` 只增加 `mmc-hs400-1_8v`，未修正 RK3568 rev0 TXCLK tap，导致 HS400 写入 I/O error，补丁随后被移除。2026-11-14 定位为 TXCLK tap 问题后重新启用，并固定 tap `0x8`。仅恢复 DTS 的 HS400 属性而不带 `0031` 会重现旧故障。

## 回滚

```text
恢复 HS200：移除 0032 的两行 DTS 属性；0031 在 HS200 下不改变行为。
```

若需完全回退 TXCLK 行为，同时移除 `0031`。
