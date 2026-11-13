# 电源轨与 vendor DTS 差异核实（2026-11-13）

参考：

- `rea-z97a/docs/ANDROID-archive-rk-kernel.dts`
- `rea-z97a/docs/ANDROID-rk-kernel-0.dts`（与 archive 相同）
- `artifacts/android/extracted/boot-kernel.bin` 符号/字符串
- 当前 live DTB 与 `/sys/class/regulator`

## 四处差异的核实结论

| 项目 | vendor DTS | 当前 | 核实结论 |
|---|---|---|---|
| `vccio_sd` | LDO_REG5，3.3V，always-on | 1.8V，enabled | **有意差异**：1.8V 用于 WiFi SDIO SDR104；当前 mmc1 实测 UHS-I SDR104、phase 119。改回 3.3V 会失去当前 16–18MB/s 配置 |
| 前置输入轨 | `dc-12v` 固定 12V，供 `vcc3v3_sys`/`vcc5v0_sys` | `vcc15v_dcin` 固定 15V，供 `vcc3v3_sys`/`vcc5v0_sys` | vendor 的 12V 很可能是 15V VBUS 经前置 buck 后的中间轨；当前直接建模 15V。当前 3.3V/5V buck 工作正常，但**是否应补 12V 中间轨需原理图/实测确认** |
| `vcc_camera` | vendor DTS 没有该 regulator | 当前 `regulator-vcc-camera`，GPIO2_D0，always-on | **mainline 额外补充**；vendor Android 可能由 USB 5V/其他路径供电。当前这台机器没有枚举到 0c45:6368 摄像头，留着无害 |
| `vcc_wifi` | vendor DTS 没有该 regulator；有 `sdio-pwrseq` reset GPIO0_C0、`wifi-enable-h` pinctrl、`vcc3v3_sd` always-on | 当前 `regulator-wifi-power`，GPIO0_A0，3.3V，作为 mmc1 `vmmc-supply` | **mainline 额外补充**；vendor 可能用 `vcc3v3_sd` 常开 + reset 上电。当前 WiFi SDR104 正常，保留；若改回 vendor 拓扑需重新验证 WiFi 上电时序 |

## 已确认一致的主轨

- `vdd_cpu`（TCS4525）、`vdd_logic`、`vdd_gpu`、`vdd_npu`
- `vcc_1v8`、`vcc_3v3`、`vcc_ddr`
- `vcca1v8_image`、`vcca1v8_pmu`、`vcca_1v8`
- `vccio_acodec`、`vcc3v3_pmu`
- `vcc3v3_lcd0_n`、`vcc5v0_usb`、`vcc5v0_usb2_host1/2`、`vcc5v0_usb_keyboard`
- USB host/OTG、LCD、键盘 enable GPIO

## 处理建议

1. **vccio_sd 保持 1.8V**，这是已验证的 WiFi 性能配置，不是漏改。
2. **15V/12V 前置轨**：除非拿到原理图或实测中间轨，否则不改；当前 3.3V/5V 轨输出正常。
3. **vcc_camera / vcc_wifi**：保留为 mainline 上电补充；不影响 vendor 主轨。
4. 若未来要严格按 vendor 拓扑，优先验证 `vcc3v3_sd` 作为 SDIO `vmmc-supply` 的替代方案。
