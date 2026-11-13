# RTL8822CS 驱动对比：rtw88 与 Realtek out-of-tree

日期：2026-11-14。设备：`.84`，RK3568，Linux 7.2.12，SDIO SDR104 / 1.8V。

## 基线：主线 rtw88_8822cs

绑定 `wlan0`（`-B <wlan0-ip>%wlan0`，并核对 wlan0 计数器）后：

```text
SDIO: 200MHz / 4bit / SDR104 / signal 1.80V
WiFi: XFL_5G 5745MHz / 80MHz / RSSI -48..-50
iperf3:
  上行 45–49 Mbps
  下行 95–139 Mbps（单流最好约 135–139）
  4 流下行约 95–104 Mbps
```

## 编译 Realtek out-of-tree `rtl88x2cs`

源码：

```text
https://github.com/jethome-iot/rtl88x2cs
commit e12226b (tune_for_jethub, 含 kernel 7.4 修复)
```

编译：

```sh
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     KSRC=/home/hsy/project/debian-image-builder-z96a/sources/linux -j4
```

结果：

```text
88x2cs.ko  4.3MB
version v5.9.0.7_37128.20200812_COEX20200103-1717
license GPL
depends cfg80211
vermagic 7.2.12 SMP preempt mod_unload aarch64
alias sdio:c07v024CdD821*, sdio:c07v024CdC822*
```

SDIO 设备 `024c:c822` 匹配；驱动使用内嵌 firmware 数组，不依赖 rtw88 的
`rtw8822c_fw.bin`。编译无 warning/error。

## 真机加载与测试

在不重启、不写 `/lib/modules`、不 blacklist 的前提下：

```sh
nmcli device disconnect wlan0
modprobe -r rtw88_8822cs rtw88_sdio rtw88_8822c rtw88_core
insmod /home/user/88x2cs.ko
nmcli connection up XFL_5G
```

驱动 probe 成功，`wlan0` 出现，`iw link` 显示 5GHz/5745/80MHz，tx bitrate
最高 867Mbps。但 iperf3 不稳定且明显低于 rtw88：

```text
上行: 55.7 / 63.4 / 3.1 Mbps
下行: 47.1 / 38.8 / 43.9 / 22.5 Mbps
4 流下行: 24–31 Mbps
```

## 结论

- `rtl88x2cs` 能在 7.2.12 编译、加载、连接，但当前实测性能**不如**主线
  `rtw88_8822cs`，且波动很大（上下行都有掉到个位数到几十 Mbps 的情况）。
- 驱动日志提示 `Driver 'rtl88x2cs' needs updating - please use bus_type methods`；
  很可能 RX 聚合/NAPI/旧 API 路径在 7.2 下没有完全适配，或缺少厂商 efuse/PHY
  参数文件（`/system/etc/wifi/wifi_efuse_88x2cs.map` 等）。
- 因此**不替换默认 rtw88**；厂商驱动仅作为实验产物，未安装到
  `/lib/modules`，未写 blacklist，未重启。

## 回滚/当前状态

测试后已：

1. `modprobe -r 88x2cs`
2. 重新 `modprobe rtw88_8822cs`
3. `nmcli connection up XFL_5G`

当前恢复主线 rtw88，复测：

```text
上行 47.6 Mbps / 下行 133 Mbps
```

`/home/user/88x2cs.ko` 已删除；源码和构建产物保留在 host 的
`/home/hsy/project/rtl88x2cs/`，未写入镜像仓库。
