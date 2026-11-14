# RTL8822CS / rtw88 参数调优实测

日期：2026-11-14。设备 `.84`，Linux 7.2.12，驱动保持主线 `rtw88_8822cs`，未换驱动、未重启。

## 当前最终状态

```text
country: CN (DFS-FCC)
channel: 149 / 5745MHz / 80MHz
txpower: 20 dBm
power_save: off
rtw88_core.disable_lps_deep: Y
rtw88_core.support_bf: Y

RPS:
  rx-0/rps_cpus = 0
  rx-0/rps_flow_cnt = 0
  net.core.rps_sock_flow_entries = 32768
IRQ:
  dw-mci IRQ 73 affinity = f
TCP:
  rmem_max = 8388608
  wmem_max = 8388608
  tcp_rmem = 4096 87380 8388608
  tcp_wmem = 4096 65536 8388608
```

## 实测过的参数组合

### 1. country / AP / BSSID

| 组合 | 下行 | 上行 |
|---|---|---|
| country 00，AP 149，auto BSSID | 95–139Mbps | 45–49Mbps |
| country CN，AP 149，txpower 33 | 52–94Mbps | 18–42Mbps |
| country CN，AP 161（08:9b:4b:12:d2:c3） | ~98Mbps | ~37Mbps |
| country CN，强制 AP 149 BSSID 00:03:7f:12:2d:2d | 86Mbps | 10Mbps |

结论：`country CN` 把 5GHz 5725–5850 的允许功率从 20dBm 提到 33dBm，但本机实际 `txpower` 仍显示 20–33dBm 波动，吞吐没有稳定提升；AP/BSSID/空口干扰影响更大。

### 2. RPS / IRQ affinity

尝试：

```sh
echo b > /sys/class/net/wlan0/queues/rx-0/rps_cpus   # CPU0/1/3
echo 4096 > /sys/class/net/wlan0/queues/rx-0/rps_flow_cnt
echo 32768 > /proc/sys/net/core/rps_sock_flow_entries
echo 4 > /proc/irq/73/smp_affinity                   # dw-mci -> CPU2
```

在 AP 149 上实测下行约 86Mbps、上行约 18Mbps，**低于不开 RPS 的基线**。已回滚：

```sh
echo 0 > /sys/class/net/wlan0/queues/rx-0/rps_cpus
echo 0 > /sys/class/net/wlan0/queues/rx-0/rps_flow_cnt
echo f > /proc/irq/73/smp_affinity
```

`rps_sock_flow_entries` 和 TCP 缓冲保留。

### 3. power_save / 深度省电

```sh
iw dev wlan0 set power_save off
```

`rtw88_core.disable_lps_deep=Y` 已在 `/etc/modprobe.d/rtw88.conf`。关闭后下行从 52Mbps 提到约 94Mbps（同一 AP、同一轮测试），是本次唯一比较正向的单项。

### 4. TCP 缓冲

已设置 8MB 上限。单次测试中没有明显回退，保留。

## 受控矩阵结果（AP149，5s iperf3）

### RPS 掩码（IRQ 保持 f）

| rps_cpus | 下行 | 上行 |
|---|---|---|
| 0 | 138Mbps | 23.0Mbps |
| 1 (CPU0) | 113Mbps | 24.8Mbps |
| 2 (CPU1) | 140Mbps | 25.0Mbps |
| 4 (CPU2) | 112Mbps | 23.1Mbps |
| 8 (CPU3) | 128Mbps | 失败/无结果 |
| f (全部) | 150Mbps | 20.1Mbps |

### IRQ affinity（RPS f）

| smp_affinity | 下行 | 上行 |
|---|---|---|
| 1 (CPU0) | 144Mbps | 24.6Mbps |
| 2 (CPU1) | 143Mbps | 17.5Mbps |
| 4 (CPU2) | 122Mbps | 23.7Mbps |
| 8 (CPU3) | 152Mbps | 23.0Mbps |
| f (全部) | 139Mbps | 29.5Mbps |

最终选择了：

```text
rps_cpus = f
rps_flow_cnt = 4096
dw-mci IRQ 73 affinity = 8 (CPU3)
power_save = off
```

3 次复测：下行 125 / 153 / 123Mbps，上行 24.7 / 27.7 / 18.0Mbps。最好 153Mbps，但波动仍然明显；没有稳定 30% 提升。

## 结论

- 参数调优不能稳定复现“下行 170–210Mbps”：本机实际在 52–139Mbps 之间大幅波动。
- 主要变量是 AP/空口/速率控制，不是 CPU 软中断或 TCP 缓冲。
- RPS + IRQ affinity 在本机没有收益，已回滚；`power_save off` 有正向作用。
- 没有使用 vendor `8822cs.ko`、没有换驱动、没有重启。
- 需要长期稳定，优先：
  1. `power_save off`；
  2. 选 80MHz 5GHz AP/BSSID，避开拥塞信道；
  3. country 按实际区域设置；
  4. 不要盲目开 RPS/IRQ 分散。

## 回滚

```sh
iw reg set 00
iw dev wlan0 set power_save on
nmcli connection modify XFL_5G 802-11-wireless.bssid ""
cat /proc/sys/net/core/rmem_max   # 需要恢复原值
```

（TCP 缓冲当前值已记录；如需恢复原值，先查发行版默认。）
