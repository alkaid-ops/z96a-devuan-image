# 充电灯事件驱动（eudev + SysV）

Z96A 的 C 口充电灯策略：

| 条件 | `green:charging` | `red:charging` |
|---|---|---|
| AC online，capacity ≥ 90% | 1 | 0 |
| AC online，capacity < 90% | 0 | 1 |
| AC offline | 0 | 0 |

`white:power` 是系统运行灯，保持 `default-on` 常亮，不参与充电状态。

## 数据路径

```text
rk817_charging_monitor（每 8 秒采样，驱动原有节奏）
  └─ rk817_read_props() 更新 soc / charge_status
       └─ 只有「整数 capacity」或「charge_status」变化时
            power_supply_changed(bat_ps)        ← 0025 新增
                 └─ 内核 KOBJ_CHANGE uevent
                      └─ eudev 读取 99-z96a-charge-led.rules
                           └─ 执行一次 /usr/local/sbin/z96a-charge-led --once
                                └─ 读 sysfs、写 LED brightness、退出
```

插拔路径由 `rk817_plug_in_isr` / `rk817_plug_out_isr` 和
`bq257xx-charger` 的 IRQ 直接调用 `power_supply_changed`，不依赖 8 秒采样。

**不要比较原始 `soc`**：`soc` 的分辨率是 0.001%，放电时每 8 秒必然变化，
直接比较会让 udev 每 8 秒执行一次，退化成 8 秒轮询。0025 比较的是
`(soc + 500) / 1000`（也就是 `capacity` 属性同款整数）。

Devuan 6 使用 **eudev 3.2.14 + SysV init**，不是 systemd；`RUN+=` 由
eudev 的 `udevd` 执行，不需要 `.service` / `.timer` / systemd-udevd。

## 2026-11-13 真机记录（`.84` eMMC 夜间镜像）

把 0021+0022+0024+0025 模块热替换进内核后：

```text
present=1  status=Full  capacity=100  voltage_avg=8.389V
charge_now=5000000  charge_full=5000000
upower 只剩 battery_rk817_battery
```

放电实测（临时诊断规则记录到 `/run/z96a-ps-events.log`）：

```text
03:51:58  bq257xx-charger  online=0
03:52:02  rk817-battery    cap=100  status=Discharging
03:54:04  rk817-battery    cap=99   status=Discharging   ← 1% 事件
03:57:29  rk817-battery    cap=98   status=Discharging   ← 1% 事件
03:59:31  bq257xx-charger  online=1
03:59:32  rk817-battery    cap=100  status=Full
03:59:40  rk817-battery    cap=100  status=Charging
```

- 100→99 与 99→98 之间约 **3 分 25 秒**，与当前放电率约 1%/3.4 分钟一致；
- 满电静置 45 秒 `udevadm monitor` 没有周期性事件；
- 期间充电器拔掉，99%/98% 时两灯灭；03:59:31 插回后恢复绿灯；
- 红灯路径用 `Z96A_CHARGE_LED_THRESHOLD=101 --once` 验证：`green=0 red=1`；
- 离线路径用 `online=0` 的假 `Z96A_CHG` 节点验证：两灯灭。

诊断用的 `/etc/udev/rules.d/98-z96a-ps-debug.rules` 和
`/usr/local/sbin/z96a-ps-log` 在验证后已移除，只保留正式规则。

## 相关文件

| 文件 | 作用 |
|---|---|
| `patches/git/z96a-v2/linux-add_sunniwell_z96a/0025-z96a-rk817-charge-led-events.patch` | 驱动侧按整数 capacity/status 门控 `power_supply_changed` |
| `files/rootfs-overlay/z96a-v2/etc/udev/rules.d/99-z96a-charge-led.rules` | eudev 规则，`RUN+=... --once` |
| `files/rootfs-overlay/z96a-v2/usr/local/sbin/z96a-charge-led` | one-shot 策略脚本；`--watch` 仅供调试 |
| `files/rootfs-overlay/z96a-v2/etc/init.d/z96a-charge-led` | 启动时 one-shot，无常驻 daemon |

## 验证命令

```sh
# 当前 LED 真值
echo "online=$(cat /sys/class/power_supply/bq257xx-charger/online) \
cap=$(cat /sys/class/power_supply/rk817-battery/capacity)"
for l in green:charging red:charging; do echo "$l=$(cat /sys/class/leds/$l/brightness)"; done

# 看事件（满电静置应安静；放电约每 1% 一次）
udevadm monitor --subsystem-match=power_supply --property

# 强制红灯路径（临时阈值），再恢复
Z96A_CHARGE_LED_THRESHOLD=101 /usr/local/sbin/z96a-charge-led --once
/usr/local/sbin/z96a-charge-led --once
```

## 回滚

- 驱动：恢复 `/lib/modules/$(uname -r)/kernel/drivers/power/supply/rk817_charger.ko.before-events`，`depmod -a` 后 unbind/rebind 或 `rmmod`/`modprobe`。
- 用户态：删除 `99-z96a-charge-led.rules`，恢复旧的常驻 2 秒脚本和 init.d。
