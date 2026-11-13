# GPIO / pinctrl 对齐审计（2026-11-13）

参考：vendor 反编译 DTS `rea-z97a/docs/ANDROID-archive-rk-kernel.dts`
和当前 live DTB 反编译结果。

## 重要修正：第 4 个 cell 是 phandle，不是原始配置值

`rockchip,pins = <bank pin func CONFIG>` 里的 `CONFIG` 是
**指向 pinctrl config 节点的 phandle**（如 `pcfg-pull-up`），
不是 bias/drive 的位域。之前直接比较十六进制值会误判为“71 个组
pull/drive 不同”，实际应解析 phandle 指向的
`bias-pull-up` / `bias-disable` / `drive-strength` / `input-schmitt-enable`。

## 解析后的结果

- 当前 95 个 pinctrl group，vendor 111 个。
- 同名组中真正配置不同的只有 7 个：

| group | vendor | 当前 | 结论 |
|---|---|---|---|
| `sdmmc1-bus4` | bias-pull-up, drive 2 | 完全相同 | 仅十六进制写法 `0x2` vs `0x02` |
| `sdmmc1-clk` | bias-pull-up, drive 2 | 完全相同 | 同上 |
| `sdmmc1-cmd` | bias-pull-up, drive 2 | 完全相同 | 同上 |
| `spi0m0-pins` | bias-pull-up, drive 1 | bias-disable | SPI0 disabled，无影响 |
| `spi1m0-pins` | bias-pull-up, drive 1 | bias-disable | SPI1 disabled，无影响 |
| `spi2m0-pins` | bias-pull-up, drive 1 | bias-disable | SPI2 disabled，无影响 |
| `spi3m0-pins` | bias-pull-up, drive 1 | bias-disable | SPI3 disabled，无影响 |

实际在用的关键组解析结果：

```text
i2c0-xfer
  vendor : bias-disable, input-schmitt-enable
  current: bias-disable, input-schmitt-enable

sdmmc1-bus4/clk/cmd
  vendor : bias-pull-up, drive-strength=2
  current: bias-pull-up, drive-strength=2
```

其余 pin-equivalent 组（含 hall、PMIC/charger 中断、speaker、USB
enable、Type-C switch 等）解析后的 config 也一致。

## 基线与接口验证（当前 pinctrl，未改）

```text
eMMC:  HS200, mmc0 29.1GiB
WiFi:  mmc1 UHS-I SDR104, tuned phase 119
USB3:  Bus 002/007 5000M，SanDisk 5Gbps 正常
USB2:  键盘/触控板、R8152 以太网正常
Audio: es7202-mic / rk817_ext / HDMI 三个 card 正常
充电:  bq257xx-charger online=1, charging；NTC 23°C
dmesg: 无 I2C/MMC/SDIO/USB/audio error/timeout
```

## 结论

- **实际启用接口的 pull/drive 已经与 vendor 等价**，不需要逐项改。
- 唯一的真实差异是 **SPI0–SPI3 的 pull-up/drive**，但这些控制器
  当前 `status=disabled`，改了没有收益。
- 用户已确认 **板上没有 SPI 控制器/SPI flash 设备**；SPI0–SPI3 和
  SFC 保持 `disabled`，不做对齐，也不启用。
- 因此不生成 pinctrl 覆盖补丁，也不重启；当前 pinmux/电气配置保持。
