# configure/70-network.sh — GVfs/PCManFM-Qt protocol integration and menu prefix
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	if [ -n "${Z96A_WIFI_SSID:-}" ] || [ -n "${Z96A_WIFI_PASSKEY:-}" ]; then
		[ -n "${Z96A_WIFI_SSID:-}" ] && [ -n "${Z96A_WIFI_PASSKEY:-}" ] || {
			echo "both Z96A_WIFI_SSID and Z96A_WIFI_PASSKEY are required" >&2
			exit 1
		}
		install -d -m 0700 /etc/NetworkManager/system-connections
		cat > /etc/NetworkManager/system-connections/z96a-wifi.nmconnection <<EOF
[connection]
id=z96a-wifi
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi
autoconnect=true
autoconnect-priority=50

[wifi]
mode=infrastructure
ssid=$Z96A_WIFI_SSID
mac-address-randomization=0

[wifi-security]
key-mgmt=wpa-psk
psk=$Z96A_WIFI_PASSKEY

[ipv4]
method=auto
route-metric=600
may-fail=true

[ipv6]
method=auto
may-fail=true

[proxy]
EOF
		chmod 0600 /etc/NetworkManager/system-connections/z96a-wifi.nmconnection
	fi

	# Use the Z96A compatibility launcher for GPUI on the Panfrost/X11 stack.
	sed -i 's|^Exec=.*|Exec=/usr/local/bin/oxideterm %u|' /usr/share/applications/com.oxideterm.app.desktop
	# WeChat hardcodes /usr/bin/lsblk. Devuan 6 is usrmerged, so
	# only create the compatibility link when it is genuinely absent.
	if [ ! -e /usr/bin/lsblk ] && [ -x /bin/lsblk ]; then
		ln -s /bin/lsblk /usr/bin/lsblk
	fi


	# Integrate common network protocols through GVfs and PCManFM-Qt.
	pcmanfm_desktop=/usr/share/applications/pcmanfm-qt.desktop
	if [ -f "$pcmanfm_desktop" ]; then
		sed -i 's|^MimeType=.*|MimeType=inode/directory;x-scheme-handler/smb;x-scheme-handler/ftp;x-scheme-handler/sftp;x-scheme-handler/dav;x-scheme-handler/davs;x-scheme-handler/nfs;x-scheme-handler/afp;x-scheme-handler/mtp;x-scheme-handler/gphoto2;x-scheme-handler/network;x-scheme-handler/archive;x-scheme-handler/cdda;|' "$pcmanfm_desktop"
		update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
		runuser -u user -- env HOME=/home/user xdg-mime default pcmanfm-qt.desktop inode/directory
		for scheme in smb ftp sftp dav davs nfs afp mtp gphoto2 network archive cdda; do
			runuser -u user -- env HOME=/home/user xdg-mime default pcmanfm-qt.desktop "x-scheme-handler/$scheme"
		done
	fi
