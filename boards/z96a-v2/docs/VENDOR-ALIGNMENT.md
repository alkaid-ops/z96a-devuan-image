# Z96A 镜像仓库与原厂对齐方案

日期：2026-11-12
适用仓库：`/home/hsy/project/z96a-devuan-image`

## 0. 结论

当前镜像仓库与“已验证的 live 状态”和原厂配置的差异及处理状态：

1. **U-Boot 预编译文件是 B 版、DDR 1184MHz**，不是 live 的 A SPL + P1 FIT、DDR 1560MHz。**用户要求暂不处理 U-Boot。**
2. **eMMC HS400 补丁已删除**；内核 DTS 保持 HS200 / `max-frequency=200MHz`，与厂商一致。
3. **WiFi SDIO 已实现 200MHz / SDR104**：`vccio_sd` 固定 1.8V，配合内核补丁 0014（跳过 CMD11 + UHS 失败回退）和 DTS 补丁 0015。

其余（充电器参数、Type-C PDO、NPU、OPP/PVTM、SPI flash、背光曲线、eDP/音频）属于后续对齐项。

## 1. U-Boot 预编译文件（最高优先级）

镜像构建使用：

- `lib/boards/z96a-v2`：`PRECOMPILED_UBOOT="true"`、`PRECOMPILED_UBOOT_DIR="files/boot/uboot/z96a-v2"`
- `packaging/pkgvars`：`uboot_precompiled_packaging` 直接把 `${PRECOMPILED_UBOOT_DIR}/*.bin` 复制到输出并打包
- `lib/function/rockchip` / `files/scripts/write2mmc`：`idbloader.bin` 写扇区 64，`u-boot.bin` 写扇区 16384

当前文件：

```text
files/boot/uboot/z96a-v2/idbloader.bin  202752  SHA-256 7d799106...
files/boot/uboot/z96a-v2/u-boot.bin     1220096 SHA-256 efd764f4...
```

核对结果：

- `idbloader.bin` 头 `0x90` 和 `0x800..0xF000` 都是自定义 **1184MHz** blob 的哈希 `a26184e4...`。
- `u-boot.bin` 是 B 版 FIT，U-Boot 数据 948,960 字节。
- 镜像 deb `output/z96a-v2/u-boot-rk3568-z96a-v2_2026.01-1_arm64.deb` 里就是这两个文件。

live 已验证状态：

```text
A idbloader + vendor v1.13 DDR 1560MHz
  build/recovery-20261111/idbloader-1560-vendor-rksd.img
  204800 字节  SHA-256 35c368f3ad8d84acd756e4bb45bcbff56912b9b4a8892ac605ff35809bf683ac

P1 FIT
  build/out/armbian-p1/u-boot.itb
  1221120 字节 SHA-256 3dd682033885ed88c3c95fa02d152747bf577fadfd678372f59304dcc7f215ea
```

### 操作

```sh
cd /home/hsy/project/z96a-devuan-image
mkdir -p /tmp/z96a-uboot-backup-20261111
cp -a files/boot/uboot/z96a-v2/idbloader.bin \
     files/boot/uboot/z96a-v2/u-boot.bin \
     /tmp/z96a-uboot-backup-20261111/

cp /home/hsy/project/rea-z97a/build/recovery-20261111/idbloader-1560-vendor-rksd.img \
   files/boot/uboot/z96a-v2/idbloader.bin
cp /home/hsy/project/rea-z97a/build/out/armbian-p1/u-boot.itb \
   files/boot/uboot/z96a-v2/u-boot.bin

sha256sum files/boot/uboot/z96a-v2/idbloader.bin files/boot/uboot/z96a-v2/u-boot.bin
```

预期：

```text
35c368f3...  idbloader.bin
3dd68203...  u-boot.bin
```

然后重新打包镜像/deb，确认 `output/z96a-v2` 的 u-boot deb 内文件哈希也为 35c368f3/3dd68203。

注意：

- 该 idbloader 是 A SPL + 原厂 v1.13 DDR blob，RKNS 头哈希有效；不要手工替换 DDR 段。
- 如果以后改为源码构建 U-Boot，必须把 `RKBIN_RAM` 指向原厂 v1.13 blob；当前 board config 没有定义 `RKBIN_*`，只靠 precompiled 路径。
- 原厂 v1.13 blob 副本：`/tmp/opencode/vendor-ddr-v1.13.bin`（59,392 字节，SHA-256 `763947ff...`），建议存入仓库 `files/boot/uboot/z96a-v2/ddr-v1.13-1560.bin` 以便重建。

## 2. eMMC HS400 补丁（已处理）

原应用：

```text
patches/git/z96a-v2/linux-add_sunniwell_z96a/0010-z96a-emmc-hs400.patch
```

补丁在 `&sdhci` 中增加：

```dts
+ mmc-hs400-1_8v;
```

原厂：

- U-Boot 2017 DTS：`mmc-hs200-1_8v`，无 HS400。
- Android 内核 DTS：`supports-emmc`、`max-frequency=200MHz`，无 HS400。
- mainline eMMC Linux DTB（已安装）：`max-frequency=200MHz`，无 HS400。

实测：HS400 下 `dd` 写 eMMC 报 I/O error；去掉 HS400、50MHz 后写入成功。

### 状态（2026-11-12）

- 已删除 `0010-z96a-emmc-hs400.patch`。
- 已从 `boards/z96a-v2/patches/SERIES.md` 移除该行。
- 已在 `HARDWARE-STATUS.md` 更正为 HS200 / 200MHz，无 HS400。

### 状态（2026-11-14）：重新启用 HS400ES 200MHz

早期 HS400 写入失败已定位为 TXCLK tap 问题，根因与 `mmc-hs400-1_8v` 本身无关。现已重新启用，并固定 TXCLK tap：

```text
patches/git/z96a-v2/linux-add_sunniwell_z96a/0031-rk3568-hs400-txclk-tap-08.patch
patches/git/z96a-v2/linux-add_sunniwell_z96a/0002-z96a-board-dts.patch
```

- `0031`：RK3568 rev0 HS400/HS400ES TXCLK tap 固定 `0x8`（`0x29000008`），HS200 路径不变；
- `0002`：板级 DTS 汇总中，`&sdhci` 增加 `mmc-hs400-1_8v`、`mmc-hs400-enhanced-strobe`，`max-frequency` 保持 200MHz；
- STRBIN 保持默认 `0x09000004`，RXCLK 保持 `0x28000000`，CMDOUT 保持 0；
- 验证：100MHz A/B/A、200MHz HS200/HS400ES 单次、200MHz TXCLK 0x04–0x10 扫描、200MHz STRBIN 4/6/8 扫描均完成；tap 0x04–0x0C 稳定，0x0E/0x10 出现 DATA_CRC；
- 生产选择 `0x8`，因为写入吞吐最高且位于稳定窗口中心。

注意：不要再删除或绕过 TXCLK tap；仅加回 `mmc-hs400-1_8v` 而不带 `0031` 会重现早期写入 I/O error。

## 3. WiFi SDIO（已对齐：1.8V / 200MHz SDR104）

原厂：

```dts
max-frequency = <200000000>;
sd-uhs-sdr104;
```

原厂 DTS 同时把 `vccio_sd`（RK809 LDO5，供 `vccio3` / SDMMC1 IO）固定为 3.3V，且 SDIO 节点没有 `vqmmc-supply`。mainline 不能直接照搬：RTL8822CS 在 1.8V 下仍错误地把 R4 响应的 S18A 置 1，内核于是发送 CMD11；CMD11 实际没有完成，最终回落 50MHz。

### 根因

```text
dwmmc_rockchip fe2c0000.mmc: card claims to support voltages below defined range
dwmmc_rockchip fe2c0000.mmc: Unexpected CMD11 timeout
mmc_host mmc1: Timeout sending command (cmd 0x10202000 arg 0x0 status 0x90202000)
mmc1: new high speed SDIO card at address 0001
```

`cmd 0x10202000` 就是 `VOLT_SWITCH | UPD_CLK | PRV_DAT_WAIT`。RTL8822CS 在不该置位时报告 S18A=1，导致内核执行一次无意义的 CMD11 1.8V 电压切换。

### 最终方案

1. 板级 DTS 把 SDMMC1 的实际 IO 电源固定为 1.8V，并让 `vqmmc` 指向同一路电源：

```dts
vccio_sd: LDO_REG5 {
	regulator-min-microvolt = <1800000>;
	regulator-max-microvolt = <1800000>;
};

&sdmmc1 {
	max-frequency = <200000000>;
	sd-uhs-sdr104;
	vqmmc-supply = <&vccio_sd>;
};
```

2. 内核补丁 `0014-z96a-sdio-uhs-cmd11.patch`：
   - 当 host 已经处于 1.8V 时跳过 CMD11（对应上游 2026-10 的 RTL8822CS 修复）；
   - 如果 UHS 初始化（tuning）失败，回退到 high-speed，而不是让整张卡初始化失败。

3. 上述 DTS 改动已并入 `0002-z96a-board-dts.patch`。

> 上游 pinned commit（`0211cf630ee3`）已经声明 `sd-uhs-sdr104`，但用的是 `vqmmc = <&vcca1v8_pmu>` 且没有 `max-frequency`。那只是软件上“假装 1.8V”，实际 `vccio3` 仍由 `vccio_sd` 3.3V 供电；本补丁把电源和 `vqmmc` 改成一致的 1.8V，并显式设置 200MHz。

### 实测结果（2026-11-12，`.84` USB Devuan 7.2.12）

正常 U-Boot 引导（非 kexec）下：

```text
mmc_host mmc1: Bus speed = 200000000Hz (req 200000000Hz, actual 200000000HZ div = 0)
dwmmc_rockchip fe2c0000.mmc: Successfully tuned phase to 122
mmc1: new UHS-I speed SDR104 SDIO card at address 0001
```

`/sys/kernel/debug/mmc1/ios`：

```text
clock: 200000000 Hz
timing spec: 6 (sd uhs SDR104)
signal voltage: 1 (1.80 V)
```

| 项目 | XFL（2.4G, 2462MHz） | XFL_5G（5G, 5745MHz） | SDR104 后 XFL_5G |
|---|---|---|---|
| 关联速率 | 78/13 Mbit/s | 780/585 Mbit/s | 468–650 Mbit/s |
| 局域网下行 | ~2.2 MB/s | ~8.2 MB/s | **~16.6–18.0 MB/s（133–144 Mbit/s）** |
| ping | 无丢包，avg 11.5ms | 无丢包，avg 2.0ms | 50/50 无丢包，avg 4.2ms |
| SDIO 总线 | 50MHz high speed | 50MHz high speed | **200MHz SDR104** |

结论：

- SDIO 吞吐从约 66 Mbit/s 提升到约 133–144 Mbit/s，约 2 倍；与上游 NanoPi R2S Plus 的实测（123/125 Mbit/s）同一量级。
- 当前瓶颈已回到 5G 链路/空口，而不是 SDIO。
- `vccio_sd` 固定 1.8V 后，`vccio3`（SDMMC1 IO）也固定 1.8V；本板的 SD 卡接口未启用，所以没有副作用。如果以后要启用 3.3V SD 卡，需要重新评估这路电源。
- 50MHz 配置仍保留为回退路径；补丁 0014 的 UHS 失败回退保证 tuning 失败时 WiFi 不会消失。

**2026-11-13 WiFi 实测（iperf3，XFL_5G 5745MHz / 80MHz，RSSI -48dBm）：**

```text
SDIO: 200MHz / 4bit / SDR104 / signal 1.80V
WiFi link: RX 526.6Mbps VHT-MCS6 80MHz NSS2
           TX 292.5Mbps VHT-MCS7 80MHz NSS1

第一次未绑定接口，ip route 走 eth0，得到 310/325Mbps —— 那是有线 USB 以太网，不是 WiFi，作废。
绑定源地址+设备后（`-B 192.168.31.134%wlan0`，wlan0 计数器同步增长）：
  board -> host: 45–49 Mbps
  host -> board: 95–139 Mbps（单流最好约 135–139）
  4 streams:     上行 ~49 Mbps / 下行 ~95–104 Mbps
```

因此当前实际 WiFi 吞吐约 **上行 45–49Mbps / 下行 95–139Mbps**。SDIO 仍是 SDR104/1.8V，不是 SDR50；瓶颈在 rtw88/空口/AP 侧，不在 SDIO 电压或模式。

旧文档里的 `16.6–18.0 MB/s（133–144Mbit/s）` 是早期测试路径的结果；本次绑定 wlan0 的下行 139Mbps 与其同一量级。

旧的 `0002-z96a-wifi-power-rail.patch.old` 中间产物已清理。

## 4. 充电器 / 电池（高优先级，安全）

原厂 `sc8886@6b`（`southchip,sc8886`）带：

```text
ti,charge-current = 1A
ti,max-charge-voltage = 8.4V（2S）
ti,max-input-voltage / max-input-current
SDP/DCP/CDP 输入电流
ti,minimum-sys-voltage
OTG 电压/电流
NTC 表 + io-channels
```

当前 mainline：

```text
charger@6b compatible southchip,sc8886s
input-current-limit-microamp = 3A
monitored-battery
simple-battery（1A、8.4V、OCV 表）
```

差异：充电电压/电流、NTC 保护、输入限流策略。需要：

1. 确认内核使用的 charger 驱动是 `sc8886s` 还是 `sc8886`；若驱动只支持前者，先补 DTS 属性（如果驱动消费这些属性）。
2. 对照原厂把 charge current/voltage/NTC/输入限流写入 DTS 或驱动默认值。
3. 结合现有 `0012-bq257xx-input-reset.patch` 检查是否与 SC8886 路径冲突。
4. 在真实电池上验证充电电流/终止电压/温度保护。

这一项涉及安全，建议单独评审，不要只改 DTS 就宣称对齐。

- **SC8886 NTC**：2026-11-13 已实现内核侧充电保护。`bq257xx_charger`
  每 5 秒读取 `battery-thermal`（与托盘显示同一个 SARADC ch4），
  低于 0°C 或高于 43°C 时置 `CHRG_INHIBIT`，回到 1–41°C 自动恢复。
  真机强制 20°C 截止测试通过（`charging inhibited` / `Not charging`，
  恢复后 `charging enabled`）。补丁 `0028`/`0029`。
- **Type-C switch**：`usb-switch` 的 `gpio-sbu-mux` 使用与 vendor
  `switch-ctl-gpios` 相同的 GPIO4_D2，已对齐；PDO 保留
  `DUAL_ROLE | DATA_SWAP`，不改成 vendor 的 `USB_COMM` 单标志，避免
  破坏 source/OTG。

### 电池计量：RK817 PMIC 库仑计（2026-11-13）

**本机电池规格（用户确认）**：SHT 3585130-2S / **5000mAh / 37Wh / 8.4V（2S）**。
原厂 DTS 的 `design_capacity=5125mAh`、`design_qmax=5500mAh` 是 BSP 标定值，
不是本机规格；mainline `simple-battery` 应按 5000mAh、8.4V 设置，OCV 表沿用原厂 21 点。

完整证据、原厂驱动源码快照和补丁方案见：

```text
rea-z97a/docs/BATTERY-GAUGE-MEMORY.md
rea-z97a/analysis/vendor/rk817_battery.c
```

原厂电量不是用 SC8886 的电压 OCV，而是 RK809 PMIC 下的：

```dts
battery {
	compatible = "rk817,battery";
	ocv_table = <...>;
	design_capacity = <5125mAh>;
	design_qmax = <...>;
	bat_res = <150mΩ>;
	sleep_enter_current = <300>;
	sleep_filter_current = <100>;
	io-channels = <&saradc 5>;
};
```

也就是 **RK817 Gas Gauge / 库仑计**，再配合 OCV 表校准。

mainline 现状：

- 有 `drivers/power/supply/rk817_charger.c`（RK817 库仑计驱动），会注册 `rk817-battery` 和 `rk817-charger`；
- 但驱动 probe 要求 PMIC 下有名为 **`charger`** 的子节点；当前 DTS 没有，所以驱动未绑定；
- 实际显示的电量来自 `bq257xx-fgu`，它走 `adc_battery_helper` + `power_supply_batinfo_ocv2cap()`，是**电压查 OCV 表模拟容量**，因此不准确。

已在 `0002-z96a-board-dts.patch` 中加入：

```dts
charger {
	monitored-battery = <&battery>;
	rockchip,resistor-sense-micro-ohms = <10000>;
	rockchip,sleep-enter-current-microamp = <300000>;
	rockchip,sleep-filter-current-microamp = <100000>;
};
```

验证状态：

- 实测（2026-11-13）：`rk817_charger` 已成功绑定，`rk817-battery` 出现，
  `current_avg ≈ 549mA`（与 `bq257xx-charger` 的 640mA 同量级），说明库仑计电流路径正常。
- 但 `rk817-battery/capacity = 1%`、`voltage_avg = 3.997V`，而实际电池约 8.32V。
  原因：mainline `rk817_charger.c` 是 **RK817 单节**实现，使用 RK817 校准常数
  (`2300..4025mV`) 和 4.45V 上限；本板是 **RK809 + 2S + 140/20 分压**，需要：
  1. RK809 校准常数（vendor 用 `600..1050mV`）；
  2. 按 `bat_res_up/bat_res_down` 做分压还原；
  3. 2S 电压范围（最大 8.404V）的 sanity check 和 OCV 初始化；
  4. 充电状态用库仑计电流方向判断（外部充电走 SC8886，PMIC charger 状态不可靠）。
- 2026-11-13 已验证（`.84`，未再重启）：
  - 已安装 `0021 + 0024` 编出的 `rk817_charger.ko`（vermagic `7.2.12 SMP preempt mod_unload aarch64`）；
  - DTB 为基于当前 `f06d` 的 `...-gauge-v2.dtb`（带 `charger`、140/20、5000mAh）；
  - `rk817-battery`：`present=1`、`status=Full`、`capacity=100`、
    `voltage_avg=8.387V`、`current_avg≈69–75mA`、`charge_full=5Ah`；
  - `bq257xx-charger` 仍在充电（约 64mA）；`bq257xx-fgu`（电压 OCV）已 unbind
    并在 `/etc/modprobe.d/blacklist-bq257xx-fgu.conf` 中永久 blacklist；
  - upower 只剩一块 `battery_rk817_battery`：**100% / 42.02Wh / 8.387V**，
    不再把两块“电池”叠加成 83Wh / 99%。
  - 补丁 `0024-z96a-rk809-battery-present.patch` 修复 RK809 `BAT_EXS` 不可靠
    （vendor 对 RK809 直接返回有电池）；否则满电校准不跑，容量会停在 5%。
  - 仍需一个完整充放电周期观察库仑计长期漂移；当前满电数据已正确。
- 首次启动会用 NVRAM/设计容量做初始 SOC，之后库仑计累积；需要几个充放电周期观察精度。

## 5. Type-C / USB-PD（中优先级）

**2026-11-13 核对结论：switch 已对齐，无需改代码。**

原厂 HUSB311：

```text
switch-ctl-gpios
source-pdos/sink-pdos = 0x40190c8
```

当前 mainline：

```text
usb-switch (onnn,fsusb43l10x / gpio-sbu-mux) 使用同一 GPIO4_D2
source-pdos/sink-pdos = 0x220190c8
```

- vendor `switch-ctl-gpios` 的 GPIO 与当前 `usb-switch/select-gpios`
  是同一个引脚（GPIO4_D2，RK_PD2），只是 vendor 写在 HUSB311 节点里、
  mainline 用 `gpio-sbu-mux` 标准绑定。实测 Type-C `port_type=dual`，
  `data_role=host` / `power_role=source`，USB3 5Gbps 正常。
- PDO 差异：vendor `0x40190c8` 只带 `USB_COMM`，当前
  `0x220190c8` 带 `DUAL_ROLE | DATA_SWAP`。当前值保留，因为 source/OTG
  和 data-role swap 需要这些标志；改成 vendor 值会去掉 dual-role，
  可能破坏 source/OTG。除非后续有 PD 设备实测确认，否则不改。

## 6. NPU（中优先级，功能缺失）

原厂 `npu@fde40000` status okay，带 `npu-opp-table`、`rknpu-supply`；当前 mainline DTB **没有 NPU 节点**。

需要：

- 确认内核是否包含 RKNPU 驱动（`CONFIG_ROCKCHIP_RKNPU` 等）；
- 若有驱动，补 DTS 节点/供电/OPP；
- 若没有，先移植驱动，属于较大工程，不建议与本次对齐混在一起。

## 7. CPU/GPU OPP、PVTM、GPU power-model（中优先级）

电源/频率对齐的当前状态、已完成项和需驱动移植项见
`POWER-ALIGNMENT.md`。本仓库已加：

- `/etc/default/governor`：`schedutil`（原 base image 默认 `performance`）；
- `0002-z96a-board-dts.patch`：补原厂 `cpu-sleep` idle state 与 CPU/GPU OPP 电压对齐。

PVTM/leakage 选压仍需内核驱动支持；只补 DTS 无效。

原厂 CPU OPP 带：

```text
rockchip,pvtm-voltage-sel
nvmem-cells = leakage/pvtm/mbist-vmin
rockchip,thermal-zone
low-temp 调整
```

当前 mainline 使用相同频率档位（408M–1992M），但固定电压，无 PVTM/leakage 选择；GPU 无 `simple-power-model`。

影响：高负载电压/频率策略更保守或更耗电，性能/温度表现可能与原厂不同。需要内核 OPP/PVTM 支持；若只补 DTS 而驱动不消费，等于无效。

## 8. 其他低优先级差异

- **SPI flash**：原厂 `sfc@fe300000` okay；mainline disabled。确认板上 SPI NOR 是否被 EC/恢复使用；当前启动不依赖。
- **背光亮度曲线**：原厂 0–255；mainline 20–220 + 200 级插值。PWM 周期同为 25kHz，同亮度值占空比不同。
- **eDP**：原厂有 `spdif` 时钟、`sunniwell,rh218`、双 backlight；mainline 用 aux-bus/EDID、单 backlight。显示已可用。
- **音频**：原厂 2 个 `ES7202_PDM_ADC_*`；mainline 3 个 `everest,es7202`。需按实际麦克风数量核对。

## 9. 验证清单

镜像仓库改完后至少验证：

1. `files/boot/uboot/z96a-v2/idbloader.bin` = `35c368f3...`；`u-boot.bin` = `3dd68203...`。
2. 重新构建的 u-boot deb 内文件哈希一致。
3. 新镜像启动后 eMMC `dmesg` 为 `HS400 Enhanced strobe`，200MHz / 8-bit / 1.8V，TXCLK 实际为 `0x29000008`。
4. eMMC 写入测试（小文件 dd 读回）通过。
5. WiFi `dmesg` 显示 200MHz/SDR104（若启用该补丁）。
6. 充电器在真实电池上按预期电流/电压充电，NTC 保护有效。
7. USB-C PD/OTG 行为与预期一致。

## 10. 优先级建议

1. 替换 precompiled U-Boot（1560 + P1）——直接对齐 live。
2. 删除 HS400 补丁——修复 eMMC 写入可靠性。
3. WiFi SDR104——性能对齐，测试后启用。
4. 充电器/PD——安全相关，单独评审。
5. NPU/OPP/SPI/背光/eDP——按需求逐步处理；音频已完成 mic-in-differential 对齐。

## 11. 音频对齐（2026-11-12）

### 已对齐 / 已验证

- 原厂与 mainline 的 I2S1 引脚、格式、MCLK 比例一致；`rk809-sound` 使用 `i2s1_8ch` + RK809 codec。
- 耳机检测：原厂 `rk-headset`（GPIO3_C2）与 mainline `simple-audio-card,hp-det-gpios` 使用同一 GPIO，pinctrl 均为 `pull-none`。
- 功放：原厂 `spk-ctl-gpios`（GPIO3_A6，active-high，pull-up）与 mainline `spk_amp`（`simple-audio-amplifier`）使用同一 GPIO/pinctrl；实测播放时 GPIO 拉高。
- 原厂 RK809 codec 节点带 `rockchip,mic-in-differential`；mainline 已补上同样的 codec 子节点。实测 PMIC regmap `0x27 = 0xf0`（bit7 已置位）。
- 实测：`rk817_ext` 播放 OK；ES7202 6ch 采集 OK；RK809 模拟 MIC 2ch 采集可打开；耳机 jack 输入设备存在；扬声器功放 GPIO 正常。

### 有意保留的差异

- **PDM / ES7202**：原厂只声明 2 个 codec（0x30/0x32）、3 个 PDM 引脚、`path-map = <1 3 0 2>`；mainline 使用 3 个 codec（0x30/0x31/0x32）、`pdmm0_sdi1/2/3`、`path-map = <1 2 3 0>`，并配合补丁 0011 提供原生 6ch。实测 6ch 全部有数据（ch0/1 MIC、ch2/3 AEC、ch4/5 headset/loopback），这是有意的功能增强，不回退到原厂 2ch 配置。
- **RK809 功放/音量属性**：原厂 `use-ext-amplifier`、`spk-use-aw8737s`、`spk-ctl-gpios`、`hp-volume`、`spk-volume` 是 Rockchip 厂商 codec 驱动私有属性；mainline `rk817-codec` 不解析这些，改由 `simple-audio-amplifier` + `simple-audio-card` routing 实现同等功能，不能原样照搬。
- **SPDIF / bt-sound**：原厂使能 `spdif-sound` 和 `bt-sound`（i2s2 + bt-sco）；mainline 未启用 SPDIF，蓝牙音频走 BlueZ/HCI SCO。当前板子的扬声器/耳机/HDMI 不依赖 SPDIF，未贸然启用。
- **HDMI mclk-fs**：已对齐。`&hdmi_sound` 覆盖 `simple-audio-card,mclk-fs = <128>`，与厂内 vendor HDMI card 的 128 一致（补丁 0017）；仍需接 HDMI sink 实测音频。
- 声卡名称：mainline 为 `rk817_ext` / `es7202-mic`，与原厂不同，仅命名差异。

### 对应补丁

- `0002-z96a-board-dts.patch`：给 RK809 PMIC 增加 `codec { rockchip,mic-in-differential; }`，并给 `&hdmi_sound` 设置 `simple-audio-card,mclk-fs = <128>`。
