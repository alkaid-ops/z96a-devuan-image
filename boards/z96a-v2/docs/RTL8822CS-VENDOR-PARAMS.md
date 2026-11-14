# RTL8822CS vendor 模块参数与 40 字节 config

日期：2026-11-14。素材来自 Android 固件 `z96a_full_no_userdata_20260818.img` 的
`vendor` 动态分区。

## Vendor 预编译模块

```text
vendor/lib/modules/8822cs.ko
version: v5.14.0.3-0-g4c549b2.20230512_COEX20211210-2727
vermagic: 4.19.232+ SMP preempt modversions aarch64
alias: sdio:c07v024CdC822*, sdio:c07v024CdD821*
```

**不能加载到 Linux 7.2.12**，只用于静态分析/参数参考。

## Vendor firmware / config

```text
vendor/etc/firmware/rtl8822cs_fw      74808 bytes  sha256 35c6a8058ec818685371a5d60aa568b45fd4457214db61ca613b1ea6eb94c0da
vendor/etc/firmware/rtl8822cs_config    40 bytes
```

`rtl8822cs_fw` 是 vendor fullmac firmware，与 rtw88 的
`rtw8822c_fw.bin`（202600 bytes，`Realtech` 头不同）不兼容。

### 40 字节 config

```text
00000000: 55 ab 23 87 22 00 0c 00 10 02 80 92 04 50 c5 ea  U.#."........P..
00000010: 19 e1 1b fd af 5f 01 a4 0b f3 00 01 00 f4 00 08  ....._..........
00000020: 01 00 81 90 00 00 12 80                          ........
```

- `0x00..0x03` = `55 ab 23 87`，Realtek config magic `0x8723AB55`；
- 其余字段没有公开格式；它**不是 efuse map**（vendor 的 efuse map 至少 256 字节），
  也不是 rtw88 firmware；
- vendor 预编译模块字符串里**没有** `rtl8822cs_config` 文件名，只有
  `/lib/firmware/`、`rtw_phy_file_path`、`PHY_ConfigRFWithParaFile` 等，
  因此这个文件是否被这版模块读取不能确认；它更像是 Android 侧遗留/预置配置。
- 没有找到 `wifi_efuse_88x2cs.map`；只有 vendor 内核里的字符串路径。

## Vendor 模块全部参数（134 项）

以下是 `modinfo -F parm 8822cs.ko` 的完整列表，可作为调优参考；这些参数只适用于
vendor 驱动，rtw88 不读取。

```text
rtw_8822c_xcap_overwrite: (uint)
rtw_scan_interval_thr:Threshold used to judge if scan request comes from scan UI, unit is ms. (uint)
rtw_rrsr_value: (int)
rtw_en_dyn_rrsr: (int)
rtw_ch_switch_offload: (int)
rtw_iqk_fw_offload: (int)
rtw_en_gro: (int)
rtw_napi_threshold: (int)
rtw_en_napi: (int)
rtw_halrf_ability: (uint)
rtw_phydm_ability: (uint)
rtw_trx_share_mode:TRx FIFO Shared (int)
rtw_recvbuf_nr:Preallocated number of struct recv_buf (int)
rtw_decrypt_phy_file:Enable Decrypt PHY File (int)
rtw_load_phy_file:PHY File Bit Map (int)
rtw_phy_file_path:The path of phy parameter (charp)
rtw_nbi_en:0:Disable, 1:Enable Narrow Band Interference (int)
rtw_tsf_update_restore_factor:num of bcn intervals to stay TSF update restore status (int)
rtw_tsf_update_pause_factor:num of bcn intervals to stay TSF update pause status (int)
rtw_antenna_gain:Antenna gain in mBi. 0x7FFF: unspecifed (int)
rtw_target_tx_pwr_5g_d:5G target tx power (unit:dBm) of RF path D for each rate section, should match the real calibrate power, -1: undefined (array of int)
rtw_target_tx_pwr_5g_c:5G target tx power (unit:dBm) of RF path C for each rate section, should match the real calibrate power, -1: undefined (array of int)
rtw_target_tx_pwr_5g_b:5G target tx power (unit:dBm) of RF path B for each rate section, should match the real calibrate power, -1: undefined (array of int)
rtw_target_tx_pwr_5g_a:5G target tx power (unit:dBm) of RF path A for each rate section, should match the real calibrate power, -1: undefined (array of int)
rtw_target_tx_pwr_2g_d:2.4G target tx power (unit:dBm) of RF path D for each rate section, should match the real calibrate power, -1: undefined (array of int)
rtw_target_tx_pwr_2g_c:2.4G target tx power (unit:dBm) of RF path C for each rate section, should match the real calibrate power, -1: undefined (array of int)
rtw_target_tx_pwr_2g_b:2.4G target tx power (unit:dBm) of RF path B for each rate section, should match the real calibrate power, -1: undefined (array of int)
rtw_target_tx_pwr_2g_a:2.4G target tx power (unit:dBm) of RF path A for each rate section, should match the real calibrate power, -1: undefined (array of int)
rtw_tx_pwr_lmt_enable:0:Disable, 1:Enable, 2: Depend on efuse (int)
rtw_tx_pwr_by_rate:0:Disable, 1:Enable, 2: Depend on efuse (int)
rtw_pll_ref_clk_sel:force pll_ref_clk_sel, 0xF:use autoload value (uint)
rtw_rxgain_offset_5gh: (uint)
rtw_rxgain_offset_5gm:default RF Gain 5GL Offset value:0 (uint)
rtw_rxgain_offset_5gl:default RF Gain 5GL Offset value:0 (uint)
rtw_rxgain_offset_2g:default RF Gain 2G Offset value:0 (uint)
rtw_FileMaskEfuse:default drv Mask Efuse value:0 (uint)
rtw_OffEfuseMask:default open Efuse Mask value:0 (uint)
rtw_TxBBSwing_5G:default init value:0xFF (uint)
rtw_TxBBSwing_2G:default init value:0xFF (uint)
rtw_GLNA_type:default init value:0 (uint)
rtw_powertracking_type:default init value:64 (uint)
rtw_RFE_type:default init value:64 (uint)
rtw_amplifier_type_5g:BIT6:5G ext-PA, BIT7:5G ext-LNA (uint)
rtw_amplifier_type_2g:BIT3:2G ext-PA, BIT4:2G ext-LNA (uint)
rtw_amsdu_mode:0:non-spp, 1:spp, 2:all drop (uint)
rtw_dfs_region_domain:0:NONE, 1:FCC, 2:MKK, 3:ETSI (uint)
rtw_adaptivity_th_edcca_hl_diff:th_edcca_hl_diff for Adaptivity (int)
rtw_adaptivity_th_l2h_ini:th_l2h_ini for Adaptivity (int)
rtw_adaptivity_mode:0:normal, 1:carrier sense (uint)
rtw_adaptivity_en:0:disable, 1:enable, 2:auto (uint)
rtw_hiq_filter:0:allow all, 1:allow special, 2:deny all (uint)
rtw_notch_filter:0:Disable, 1:Enable, 2:Enable only for P2P (uint)
rtw_advnace_ota: (int)
rtw_max_roaming_times:The max roaming times to try (uint)
rtw_check_hw_status: (int)
rtw_hw_wps_pbc: (int)
rtw_hwpwrp_detect: (int)
rtw_hwpdn_mode: (int)
rtw_enusbss: (int)
rtw_switch_usb_mode: (int)
rtw_single_ant_path: (int)
rtw_drv_ant_band_switch: (int)
rtw_antdiv_type: (int)
rtw_antdiv_cfg: (int)
rtw_full_ch_in_p2p_handshake: (int)
rtw_wifi_spec: (int)
rtw_low_power: (int)
rtw_smart_ps: (int)
rtw_power_mgnt: (int)
rtw_beamform_cap: (int)
rtw_quick_addba_req: (int)
rtw_tx_ampdu_amsdu: (int)
rtw_rx_ampdu_amsdu: (int)
rtw_rx_stbc: (int)
rtw_ampdu_enable: (int)
rtw_bw_mode: (int)
rtw_ht_enable: (int)
rtw_busy_thresh: (int)
rtw_vcs_type: (int)
rtw_vrtl_carrier_sense: (int)
rtw_wmm_smart_ps: (int)
rtw_uapsd_ac_enable: (int)
rtw_uapsd_max_sp: (int)
rtw_wmm_enable: (int)
rtw_mp_mode: (int)
rtw_channel: (int)
rtw_network_mode: (int)
rtw_lbkmode: (int)
rtw_rfintfs: (int)
rtw_chip_version: (int)
rtw_initmac: (charp)
rtw_pwrtrim_enable: (int)
rtw_wowlan_sta_mix_mode: (int)
rtw_ap_fwd_b2u_flags: (int)
rtw_ap_src_b2u_flags: (int)
rtw_sel_p2p_iface: (int)
if2name:The default name to allocate for second interface (charp)
ifname:The default name to allocate for first interface (charp)
rtw_acs: (int)
rtw_acs_auto_scan: (int)
rtw_qos_opt_enable: (int)
rtw_pci_dynamic_aspm_linkctrl: (int)
rtw_ant_num:Antenna number setting, 0:by efuse (int)
rtw_btcoex_enable:BT co-existence on/off, 0:off, 1:on, 2:by efuse (int)
rtw_excl_chs:exclusive channel array (array of uint)
rtw_channel_plan:The default chplan ID when rtw_alpha2 is not specified or valid (uint)
rtw_country_code:The default country code (in alpha2) (charp)
rtw_active_tpc_report:Active TPC report, 0:incapable, 1:capable, 2:auto enable (int)
rtw_rx_nss: (int)
rtw_tx_nss: (int)
rtw_rx_path_lmt: (int)
rtw_tx_path_lmt: (int)
rtw_trx_path_bmp: (int)
rtw_vht_rx_mcs_map:VHT RX MCS map (uint)
rtw_vht_24g_enable: (int)
rtw_vht_enable: (int)
rtw_stbc_cap: (int)
rtw_rx_ampdu_sz_limit_4ss:RX AMPDU size limit for 4SS link of each BW, 0xFF: no limitation (array of uint)
rtw_rx_ampdu_sz_limit_3ss:RX AMPDU size limit for 3SS link of each BW, 0xFF: no limitation (array of uint)
rtw_rx_ampdu_sz_limit_2ss:RX AMPDU size limit for 2SS link of each BW, 0xFF: no limitation (array of uint)
rtw_rx_ampdu_sz_limit_1ss:RX AMPDU size limit for 1SS link of each BW, 0xFF: no limitation (array of uint)
rtw_tx_bw_mode:The max tx bw for 2.4G and 5G. format is the same as rtw_bw_mode (uint)
rtw_tx_aclt_conf_ap_m2u:device TX AC queue lifetime config for AP mode M2U status (array of uint)
rtw_tx_aclt_conf_default:device TX AC queue lifetime config for default status (array of uint)
rtw_tx_aclt_flags:device TX AC queue packet lifetime control flags (uint)
rtw_drv_log_level:set log level when insert driver module, default log level is _DRV_INFO_ = 4 (uint)
rtw_dynamic_agg_enable: (int)
rtw_usb_rxagg_mode: (int)
rtw_max_bss_cnt: (int)
rtw_lps_chk_by_tp: (int)
rtw_lps_1t1r:The default LPS 1T1R setting (int)
rtw_lps_level:The default LPS level (int)
rtw_ips_mode:The default IPS mode (int)
rtw_wireless_mode: (int)
```

## 对主线的意义

- rtw88 没有对应的外部 PHY/efuse config 接口；不能把这 40 字节直接转换成
  rtw88 可读格式。
- 如果未来要参考 vendor 参数，需要先在 vendor 驱动/模块里确认它们分别对应
  txpower、antenna、AMPDU/AMSDU、LPS、NAPI 等哪一项，再通过 rtw88 的模块参数、
  debugfs 或驱动代码实现。
- 这次只做 host 侧解包/反编译记录，没有对 `.84` 写入。
