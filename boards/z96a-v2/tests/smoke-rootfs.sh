#!/bin/bash
# Phase 0 rootfs smoke test.
#
# Checks a built root filesystem (mounted image partition or output tree):
# expected packages/binaries, desktop configuration, services and desktop
# launchers. File checks run unprivileged; --chroot adds dpkg/apt checks and
# requires root.
#
# Usage:
#   boards/z96a-v2/tests/smoke-rootfs.sh <rootfs-dir>
#   sudo boards/z96a-v2/tests/smoke-rootfs.sh <rootfs-dir> --chroot
set -uo pipefail

ROOTFS=${1:-}
CHROOT=0
fail=0

[ -n "$ROOTFS" ] || { echo "usage: $0 <rootfs-dir> [--chroot]" >&2; exit 2; }
[ "$ROOTFS" = "--help" ] && { sed -n '2,10p' "$0"; exit 0; }
shift || true
for arg in "$@"; do
    case "$arg" in
        --chroot) CHROOT=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

[ -d "$ROOTFS" ] || { echo "not a directory: $ROOTFS" >&2; exit 2; }

ok()  { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }
need() {
    if [ -e "$ROOTFS$1" ] || [ -L "$ROOTFS$1" ]; then ok "file: $1"; else bad "missing: $1"; fi
}

echo "== base system"
need /etc/os-release
need /etc/passwd
need /bin/sh
[ -L "$ROOTFS/usr/bin/x-terminal-emulator" ] || [ -x "$ROOTFS/usr/bin/x-terminal-emulator" ] \
    && ok "x-terminal-emulator" || bad "x-terminal-emulator missing"

echo "== desktop stack"
for f in /usr/bin/lxqt-panel /usr/bin/lxqt-session /usr/bin/pcmanfm-qt \
         /usr/bin/qterminal /usr/bin/openbox /usr/bin/nm-applet \
         /usr/bin/slimlock /usr/local/bin/z96a-hotkey /usr/local/bin/z96a-theme \
         /usr/local/bin/z96a-window-tile /usr/local/bin/z96a-desktop-trust; do
    need "$f"
done

echo "== desktop configuration"
for f in /home/user/.config/pcmanfm-qt/z96a/settings.conf \
         /home/user/.config/lxqt/panel.conf \
         /home/user/.config/lxqt/globalkeyshortcuts.conf \
         /home/user/.config/qterminal.org/qterminal.ini \
         /home/user/.xinitrc; do
    need "$f"
done
need /home/user/Desktop/z96a-browser.desktop
need /home/user/Desktop/trash-can.desktop
need /usr/share/z96a/wallpapers/windows10.png
need /usr/share/icons/Windows-10/index.theme
need /usr/share/vulkan/implicit_layer.d/VkLayer_conformance.json

echo "== services"
for f in /etc/init.d/z96a-network-up /etc/init.d/z96a-charge-led \
         /etc/init.d/z96a-bt-after-wifi /etc/init.d/z96a-ssh-hostkeys; do
    need "$f"
done
need /home/user/.config/autostart/z96a-services.desktop

echo "== media / input"
need /usr/bin/mpv
need /usr/bin/fcitx5
need /home/user/.config/WindInput/config.toml
need /usr/lib/aarch64-linux-gnu/dri/v4l2stateless_drv_video.so

echo "== packaged applications"
for deb in /opt/z96a/packages/thorium-browser_*.deb; do
    [ -e "$ROOTFS$deb" ] || true
done
for f in /usr/bin/thorium-browser /usr/local/bin/z96a-thorium /usr/local/bin/localsend-next \
         /usr/local/bin/oxideterm /usr/bin/wechat /usr/bin/qq; do
    if [ -e "$ROOTFS$f" ]; then ok "app: $f"; else printf 'SKIP  app not present: %s\n' "$f"; fi
done

if [ "$CHROOT" -eq 1 ]; then
    echo "== chroot package checks (root)"
    if [ "$(id -u)" -ne 0 ]; then
        bad "--chroot requires root"
    else
        mount --bind /proc "$ROOTFS/proc" 2>/dev/null || true
        mount --bind /dev "$ROOTFS/dev" 2>/dev/null || true
        if chroot "$ROOTFS" /bin/sh -c 'dpkg --audit' >/tmp/z96a-dpkg-audit.log 2>&1; then
            ok "dpkg --audit"
        else
            bad "dpkg --audit (see /tmp/z96a-dpkg-audit.log)"
        fi
        if chroot "$ROOTFS" /bin/sh -c 'apt-get check' >/tmp/z96a-apt-check.log 2>&1; then
            ok "apt-get check"
        else
            bad "apt-get check (see /tmp/z96a-apt-check.log)"
        fi
        umount "$ROOTFS/dev" 2>/dev/null || true
        umount "$ROOTFS/proc" 2>/dev/null || true
    fi
else
    echo "== chroot checks skipped (pass --chroot)"
fi

[ "$fail" -eq 0 ] && { echo "ROOTFS SMOKE: PASS"; exit 0; }
echo "ROOTFS SMOKE: FAIL ($fail)"; exit 1
