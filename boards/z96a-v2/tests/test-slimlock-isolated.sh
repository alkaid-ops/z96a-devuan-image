#!/bin/sh
# Run only on the build host; Docker and Xvfb keep PAM and power actions isolated.
set -eu
if [ "${1:-}" != "--inner" ]; then
    exec xvfb-run -a -s '-screen 0 1024x768x24 -ac' "$0" --inner "${1:?build workspace}" "${2:?version}"
fi
work=$2
version=$3
testdir=$(mktemp -d "$work/slim-test-$version-XXXXXX")
underlay_pid=
container_pid=
container_name="z96a-slim-test-$$-$version"
cleanup() {
    [ -z "$underlay_pid" ] || kill "$underlay_pid" 2>/dev/null || true
    if [ -n "$container_pid" ]; then
        docker stop -t 1 "$container_name" >/dev/null 2>&1 || true
        wait "$container_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$testdir/run/z96a-power"
printf '%s\n' 'current_theme default' > "$testdir/slim.conf"
printf '%s\n' 'dpms_standby_timeout 0' 'dpms_off_timeout 0' 'tty_lock 0' 'wrong_passwd_timeout 0' > "$testdir/slimlock.conf"
printf '%s\n' 'auth required pam_unix.so' 'account required pam_unix.so' > "$testdir/pam"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$1" >> /work/test/hotkey-actions' > "$testdir/hotkey"
chmod 755 "$testdir/hotkey"
touch "$testdir/underlay-actions"
/usr/bin/python3 "$(dirname "$0")/test-slimlock-underlay.py" "$testdir/underlay-actions" &
underlay_pid=$!
for i in $(seq 1 100); do
    xwininfo -name 'Z96A lock underlay test' >/dev/null 2>&1 && break
    sleep 0.1
done
xdotool mousemove 80 80 click 1
sleep 0.2
[ "$(wc -l < "$testdir/underlay-actions")" -eq 1 ]
docker run --rm --name "$container_name" --platform linux/arm64 --network none \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "$XAUTHORITY:/tmp/z96a-xauth:ro" \
    -v "$work:/work" -v "$testdir:/work/test" \
    -v "$work/slim-$version/themes:/usr/local/share/slim/themes:ro" \
    -v "$testdir/slim.conf:/etc/slim.conf:ro" \
    -v "$testdir/slimlock.conf:/etc/slimlock.conf:ro" \
    -v "$testdir/pam:/etc/pam.d/slimlock:ro" \
    -v "$testdir/hotkey:/usr/local/bin/z96a-hotkey:ro" \
    -e DISPLAY -e XAUTHORITY=/tmp/z96a-xauth -e USER=root \
    -e XDG_RUNTIME_DIR=/work/test/run -e Z96A_LOCK_ACTION_LOG=/work/test/actions \
    z96a-power-build sh -lc "printf '%s\\n' 'root:z96atest' | chpasswd; exec /work/build-$version/slimlock" \
    >"$testdir/locker.log" 2>&1 &
container_pid=$!
for i in $(seq 1 200); do
    [ -s "$testdir/run/z96a-power/lock-ready" ] && break
    kill -0 "$container_pid" 2>/dev/null || { cat "$testdir/locker.log"; exit 1; }
    sleep 0.1
done
[ -s "$testdir/run/z96a-power/lock-ready" ] || { cat "$testdir/locker.log"; exit 1; }
xdotool mousemove 80 80 click 1
sleep 0.2
[ "$(wc -l < "$testdir/underlay-actions")" -eq 1 ] || { echo 'pointer leaked'; exit 1; }
click() { xdotool mousemove "$1" "$2" click 1; sleep 0.2; }
click 290 666 # poweroff
click 290 666 # repeated click must not confirm
[ ! -e "$testdir/actions" ]
click 290 624 # cancel
[ ! -e "$testdir/actions" ]
click 290 666
click 418 624 # confirm on a different row
grep -qx poweroff "$testdir/actions"
click 418 666
click 418 624
grep -qx suspend "$testdir/actions"
click 546 666
click 418 624
grep -qx reboot "$testdir/actions"
click 290 624
grep -qx volume-down "$testdir/hotkey-actions"
xdotool type 'incorrect'
xdotool key Return
# pam_unix applies its own failed-auth delay independently of
# wrong_passwd_timeout. Type the next password only after the first PAM call
# has returned and its field has been reset, otherwise the test's valid value
# is intentionally cleared before authentication.
sleep 4
kill -0 "$container_pid"
[ -s "$testdir/run/z96a-power/lock-ready" ]
xdotool type 'z96atest'
xdotool key Return
for i in $(seq 1 100); do
    kill -0 "$container_pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$container_pid" 2>/dev/null; then
    echo 'locker did not unlock after valid password'
    cat "$testdir/locker.log"
    exit 1
fi
wait "$container_pid" || { cat "$testdir/locker.log"; exit 1; }
container_pid=
[ ! -e "$testdir/run/z96a-power/lock-ready" ]
echo "slimlock $version isolated test passed: $testdir"
