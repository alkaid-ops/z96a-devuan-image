#!/bin/bash
# Phase 0 device smoke test / baseline collector.
#
# Runs read-only checks over SSH against a booted Z96A device and prints
# PASS/FAIL. With --save it also writes a baseline JSON snapshot.
#
# Usage:
#   boards/z96a-v2/tests/smoke-device.sh
#   boards/z96a-v2/tests/smoke-device.sh --host user@192.168.31.84 --save
#
# Env:
#   Z96A_HOST   default user@192.168.31.84
#   Z96A_SSH_OPTS  extra ssh options
set -uo pipefail

HOST=${Z96A_HOST:-user@192.168.31.84}
SAVE=0
fail=0

while [ $# -gt 0 ]; do
    case "$1" in
        --host) HOST=${2:?}; shift 2 ;;
        --save) SAVE=1; shift ;;
        --help|-h) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
BASELINE="$ROOT/boards/z96a-v2/tests/baseline.json"

# shellcheck disable=SC2086
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 ${Z96A_SSH_OPTS:-} "$HOST")

if ! "${SSH[@]}" true 2>/dev/null; then
    echo "SKIP  cannot reach $HOST over SSH (keys not configured?)"
    exit 2
fi

REMOTE=$(cat <<'REMOTE_EOF'
export DISPLAY=:0.0 XAUTHORITY=/home/user/.Xauthority XDG_RUNTIME_DIR=/run/user/1000
emit() { printf 'check|%s|%s\n' "$1" "$2"; }
metr() { printf 'metric|%s|%s\n' "$1" "$2"; }
want() { [ "$1" = "$2" ] && emit "$3" PASS || emit "$3" "FAIL(expected $2, got $1)"; }

kernel=$(uname -r)
metr kernel "$kernel"
[ -r /etc/os-release ] && . /etc/os-release && metr os "$PRETTY_NAME"

mesa=$(glxinfo -B 2>/dev/null | sed -n 's/^OpenGL version string: //p')
renderer=$(glxinfo -B 2>/dev/null | sed -n 's/^OpenGL renderer string: //p')
metr mesa "$mesa"
metr renderer "$renderer"
case "$renderer" in *Panfrost*|*Mali*) emit "gpu renderer" PASS ;; *) emit "gpu renderer" "FAIL(got $renderer)" ;; esac

# H3 GLX acceleration: direct rendering enabled on the Panfrost renderer.
direct=$(glxinfo -B 2>/dev/null | sed -n 's/^direct rendering: *//p' | head -1)
metr direct_rendering "${direct:-unknown}"
case "$direct" in
    Yes)
        case "$renderer" in
            *Panfrost*|*Mali*) emit "glx acceleration" PASS ;;
            *) emit "glx acceleration" "FAIL(renderer $renderer)" ;;
        esac
        ;;
    *) emit "glx acceleration" "FAIL(direct rendering ${direct:-unknown})" ;;
esac

[ -e /dev/dri/renderD128 ] && emit "/dev/dri/renderD128" PASS || emit "/dev/dri/renderD128" FAIL
lsmod | grep -q panfrost && emit "panfrost module" PASS || emit "panfrost module" FAIL

if command -v vulkaninfo >/dev/null 2>&1; then
    conf=$(vulkaninfo --summary 2>/dev/null | sed -n '/Mali-G52/,/conformance/ p' | sed -n 's/.*conformanceVersion *= *//p' | head -1)
    metr vulkan_conformance "$conf"
    if [ "$conf" = "1.3.0.0" ]; then
        emit "vulkan conformance" PASS
    else
        emit "vulkan conformance" "FAIL(expected 1.3.0.0, got ${conf:-none})"
    fi
else
    emit "vulkan conformance" "FAIL(vulkaninfo missing)"
fi

pgrep -x lxqt-panel >/dev/null && emit "lxqt-panel running" PASS || emit "lxqt-panel running" FAIL
pgrep -x pcmanfm-qt >/dev/null && emit "pcmanfm-qt running" PASS || emit "pcmanfm-qt running" FAIL
pgrep -x Xorg >/dev/null && emit "Xorg running" PASS || emit "Xorg running" FAIL
pgrep -x nm-applet >/dev/null && emit "nm-applet running" PASS || emit "nm-applet running" FAIL

# H2 display: the panel must run 1920x1080 at 60.02Hz (40.02 would cap video).
if command -v xrandr >/dev/null 2>&1; then
    active=$(xrandr 2>/dev/null | grep '\*' | head -1)
    mode=$(printf '%s\n' "$active" | awk '{print $1}')
    rate=$(printf '%s\n' "$active" | tr ' ' '\n' | grep '\*' | head -1 | tr -d '*+')
    metr display_mode "$mode"
    metr display_rate "$rate"
    if [ "$mode" = "1920x1080" ] && [ -n "$rate" ] && \
       awk -v r="$rate" 'BEGIN { exit !(r >= 59.9 && r <= 60.2) }'; then
        emit "display mode" PASS
    else
        emit "display mode" "FAIL(expected 1920x1080@60.02, got ${mode:-unknown}@${rate:-unknown})"
    fi
else
    emit "display mode" "FAIL(xrandr missing)"
fi

amixer -c rk817ext sget Master >/dev/null 2>&1 && emit "rk817 mixer" PASS || emit "rk817 mixer" FAIL

# H7 audio playback: a short known-good wav must play without error.
wav=/usr/local/share/sounds/z96a/volume-preview.wav
if [ -f "$wav" ] && command -v aplay >/dev/null 2>&1; then
    if timeout 8 aplay -q -D default "$wav" >/dev/null 2>&1; then
        emit "audio playback" PASS
    else
        emit "audio playback" FAIL
    fi
else
    emit "audio playback" "FAIL(wav or aplay missing)"
fi

# H8 microphone: z96a_mic must deliver a non-empty native 6ch WAV.
if command -v arecord >/dev/null 2>&1; then
    mic=$(mktemp /tmp/z96a-mic-XXXXXX.wav)
    if timeout 10 arecord -q -D z96a_mic -c 6 -r 48000 -f S16_LE -d 2 "$mic" >/dev/null 2>&1; then
        size=$(stat -c %s "$mic" 2>/dev/null || echo 0)
        chans=$(python3 - "$mic" <<'WAVEOF' 2>/dev/null
import struct, sys
with open(sys.argv[1], "rb") as handle:
    head = handle.read(64)
if head[:4] != b"RIFF" or head[8:12] != b"WAVE":
    print(0)
else:
    i = 12
    while i + 8 <= len(head):
        cid = head[i:i + 4]
        csize = struct.unpack("<I", head[i + 4:i + 8])[0]
        if cid == b"fmt ":
            print(struct.unpack("<H", head[i + 10:i + 12])[0])
            break
        i += 8 + csize
    else:
        print(0)
WAVEOF
)
        metr mic_channels "${chans:-0}"
        metr mic_wav_bytes "$size"
        if [ "$chans" = "6" ] && [ "$size" -gt 4000 ]; then
            emit "mic capture (6ch)" PASS
        else
            emit "mic capture (6ch)" "FAIL(channels=${chans:-0}, bytes=$size)"
        fi
    else
        emit "mic capture (6ch)" "FAIL(arecord failed)"
    fi
    rm -f "$mic"
else
    emit "mic capture (6ch)" "FAIL(arecord missing)"
fi

# H11 volume/brightness readable and in range (read-only, no changes).
if command -v z96a-hotkey >/dev/null 2>&1; then
    vol=$(z96a-hotkey volume-info 2>/dev/null | cut -d" " -f1)
    case "$vol" in
        ""|*[!0-9]*) emit "volume readable" FAIL ;;
        *) if [ "$vol" -ge 0 ] && [ "$vol" -le 100 ]; then
               emit "volume readable" PASS; metr volume_percent "$vol"
           else emit "volume readable" "FAIL(out of range $vol)"; fi ;;
    esac
else
    emit "volume readable" "FAIL(z96a-hotkey missing)"
fi
bl=/sys/class/backlight/backlight
if [ -r "$bl/brightness" ] && [ -r "$bl/max_brightness" ]; then
    cur=$(cat "$bl/brightness"); max=$(cat "$bl/max_brightness")
    metr brightness "$cur/$max"
    if [ "$max" -gt 0 ] && [ "$cur" -ge 0 ] && [ "$cur" -le "$max" ]; then
        emit "brightness readable" PASS
    else
        emit "brightness readable" FAIL
    fi
else
    emit "brightness readable" "FAIL(backlight sysfs missing)"
fi

# H13 power safety: auto-suspend must stay disabled during remote validation.
# Documented policy: lid/hibernate/idle are ignored by elogind, and LXQt's own
# lid/idleness watchers are disabled. Power/suspend keys stay wired to LXQt.
elog=/etc/elogind/logind.conf.d/99-z96a-power-key.conf
lxqt_pm=/home/user/.config/lxqt/lxqt-powermanagement.conf
power_ok=1
if [ -r "$elog" ]; then
    for key in HandleHibernateKey HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked IdleAction; do
        grep -q "^$key=ignore$" "$elog" || power_ok=0
    done
else
    power_ok=0
fi
if [ -r "$lxqt_pm" ]; then
    for line in enableLidWatcher=false enableIdlenessWatcher=false enableIdlenessBacklightWatcher=false \
                lidClosedAction=-1 idlenessACAction=-1 powerLowAction=-1 hibernateKeyAction=-1; do
        grep -q "^$line$" "$lxqt_pm" || power_ok=0
    done
else
    power_ok=0
fi
if [ "$power_ok" -eq 1 ]; then
    emit "power policy (no auto suspend)" PASS
else
    emit "power policy (no auto suspend)" "FAIL(elogind/LXQt power settings drifted)"
fi
if [ -r /etc/z96a/power-policy.conf ]; then
    emit "power policy config" PASS
else
    emit "power policy config" "FAIL(/etc/z96a/power-policy.conf missing)"
fi

# H16 storage: eMMC present and root filesystem mounted from a block device.
emmc=0
for blk in /sys/block/mmcblk*; do
    [ -e "$blk" ] || continue
    case "$(basename "$blk")" in
        mmcblk*boot*|mmcblk*rpmb*) continue ;;
    esac
    [ -r "$blk/size" ] && [ "$(cat "$blk/size")" -gt 0 ] && emmc=1
done
rootdev=$(findmnt -n -o SOURCE / 2>/dev/null)
metr root_device "${rootdev:-unknown}"
if [ "$emmc" -eq 1 ] && [ -n "$rootdev" ]; then
    emit "storage (emmc + root mount)" PASS
else
    emit "storage (emmc + root mount)" "FAIL(emmc=$emmc root=${rootdev:-none})"
fi

# H12 battery/AC state readable; absent battery is acceptable per policy.
if [ -d /sys/class/power_supply ]; then
    bat_present=0
    for ps in /sys/class/power_supply/*; do
        [ -r "$ps/type" ] || continue
        case "$(cat "$ps/type" 2>/dev/null)" in
            Battery)
                cap=$(cat "$ps/capacity" 2>/dev/null)
                st=$(cat "$ps/status" 2>/dev/null)
                metr battery_capacity "${cap:-none}"
                metr battery_status "${st:-none}"
                case "$cap" in ""|*[!0-9]*) : ;; *) if [ "$cap" -ge 0 ] && [ "$cap" -le 100 ]; then bat_present=1; fi ;; esac
                ;;
            Mains)
                metr ac_online "$(cat "$ps/online" 2>/dev/null || echo none)"
                ;;
        esac
    done
    if [ "$bat_present" -eq 1 ]; then emit "battery state" PASS; else emit "battery state" "FAIL(no valid battery reading)"; fi
else
    emit "battery state" "FAIL(power_supply missing)"
fi

ip -o route get 1.1.1.1 >/dev/null 2>&1 && emit "network default route" PASS || emit "network default route" FAIL

# H9 wired IPv4: an address on eth0 plus a default route.
eth_addr=$(ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | head -1)
metr eth0_ipv4 "${eth_addr:-none}"
if [ -n "$eth_addr" ] && ip -4 route show default 2>/dev/null | grep -q .; then
    emit "wired ipv4" PASS
else
    emit "wired ipv4" "FAIL(no IPv4 address or default route)"
fi
for iface in eth0 wlan0; do
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo missing)
    metr "iface_$iface" "$state"
done

memavail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
metr mem_available_kb "$memavail"
metr uptime_s "$(cut -d. -f1 /proc/uptime)"
for name in lxqt-panel pcmanfm-qt Xorg; do
    pid=$(pgrep -x "$name" | head -1)
    if [ -n "$pid" ]; then
        pss=$(awk '/^Pss:/{print $2}' "/proc/$pid/smaps_rollup" 2>/dev/null)
        [ -n "$pss" ] && metr "pss_${name}_kb" "$pss"
    fi
done

if command -v xwininfo >/dev/null 2>&1; then
    xwininfo -root -tree 2>/dev/null | grep -q '"LXQt Panel"' && emit "panel window" PASS || emit "panel window" FAIL
fi

[ -n "${1:-}" ] && exit 0
REMOTE_EOF
)

out=$(printf '%s\n' "$REMOTE" | "${SSH[@]}" 'bash -s' 2>&1)

echo "$out" | grep -v '^metric|' | while IFS='|' read -r _ name status; do
    [ -n "$name" ] || continue
    printf '%-24s %s\n' "$name" "$status"
done
if echo "$out" | grep -q '^check|.*|FAIL'; then fail=$((fail + 1)); fi

echo "== metrics"
echo "$out" | grep '^metric|' | while IFS='|' read -r _ name value; do
    printf '%-22s %s\n' "$name" "$value"
done

if [ "$SAVE" -eq 1 ]; then
    mkdir -p "$(dirname "$BASELINE")"
    {
        printf '{\n  "collected_at": "%s",\n  "host": "%s",\n' "$(date -Is)" "$HOST"
        first=1
        echo "$out" | grep '^metric|' | while IFS='|' read -r _ name value; do
            value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
            [ "$first" -eq 1 ] && { first=0; printf '  "%s": "%s"' "$name" "$value"; } \
                                || printf ',\n  "%s": "%s"' "$name" "$value"
        done
        printf '\n}\n'
    } > "$BASELINE"
    echo "baseline written: $BASELINE"
fi

if [ "$fail" -eq 0 ]; then echo "DEVICE SMOKE: PASS"; exit 0; fi
echo "DEVICE SMOKE: FAIL"; exit 1
