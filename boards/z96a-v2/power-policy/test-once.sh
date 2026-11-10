#!/bin/sh
set -eu
bin=${1:-./z96a-power-policy}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/power/bat" "$tmp/status" "$tmp/runtime"
printf 'Battery\n' > "$tmp/power/bat/type"
printf '1\n' > "$tmp/power/bat/present"
printf '42\n' > "$tmp/power/bat/capacity"
printf 'Discharging\n' > "$tmp/power/bat/status"

Z96A_BATTERY_PRESENT=1 Z96A_POWER_SUPPLY_DIR="$tmp/power" Z96A_STATUS_DIR="$tmp/status" \
    "$bin" --once --test-mode --config /etc/z96a/power-policy.conf >/tmp/z96a-once.out
grep -q 'source=BATTERY profile=BATTERY battery=42% status=Discharging' /tmp/z96a-once.out
grep -q '^POWER_SOURCE=BATTERY$' "$tmp/status/status"
grep -q '^BATTERY_PERCENT=42$' "$tmp/status/status"

mkdir -p "$tmp/power/ac"
printf 'USB\n' > "$tmp/power/ac/type"
printf '1\n' > "$tmp/power/ac/online"
Z96A_BATTERY_PRESENT=1 Z96A_POWER_SUPPLY_DIR="$tmp/power" Z96A_STATUS_DIR="$tmp/status" \
    "$bin" --once --test-mode --config /etc/z96a/power-policy.conf >/tmp/z96a-once-ac.out
grep -q 'source=AC profile=AC' /tmp/z96a-once-ac.out
grep -q '^PROFILE=AC$' "$tmp/status/status"
echo 'power-policy once tests passed'
