# configure/96-ownership.sh — system ownership, network tray, Vulkan, LocalSend
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	chmod 0755 /etc/init.d/z96a-ssh-hostkeys
	update-rc.d z96a-ssh-hostkeys defaults 01 >/dev/null 2>&1 || true
	update-rc.d ssh defaults >/dev/null 2>&1 || true

	chmod 0755 /usr/local/sbin/z96a-bt-after-wifi /etc/init.d/z96a-bt-after-wifi
	update-rc.d z96a-bt-after-wifi defaults 99 01 >/dev/null 2>&1 || true
	chmod 0600 /etc/NetworkManager/system-connections/*.nmconnection
	chmod 0755 /usr/local/sbin/z96a-network-up /etc/init.d/z96a-network-up
	update-rc.d z96a-network-up defaults 99 01 >/dev/null 2>&1 || true
	chmod 0755 /usr/local/sbin/z96a-charge-led /etc/init.d/z96a-charge-led
	update-rc.d z96a-charge-led defaults 20 01 >/dev/null 2>&1 || true


	# BSP files copied with ownership preservation must become system-owned.
	chown root:root /usr/lib/aarch64-linux-gnu/dri/v4l2stateless_drv_video.so
	chmod 0644 /usr/lib/aarch64-linux-gnu/dri/v4l2stateless_drv_video.so
	chown -R root:root /opt/z96a/packages

	# Network tray is nm-applet (network-manager-gnome), not nm-tray:
	# nm-applet exposes wired/Wi-Fi lists, available/hidden networks and VPN.
	# Purge nm-tray here so a stale dependency cannot bring it back.
	DEBIAN_FRONTEND=noninteractive apt-get purge -y nm-tray nm-tray-l10n 2>/dev/null || true
	dependency_guard "network-manager-gnome"

	# Vulkan conformance layer for PanVK (Bifrost v7 reports 0.0.0.0).
	if [ "$ENABLE_VULKAN" = "1" ]; then
		chown -R root:root /opt/vk-layer
		chmod 0755 /opt/vk-layer/build.sh
		chmod 0644 /opt/vk-layer/libconformance.so /opt/vk-layer/conformance_layer.c /opt/vk-layer/VkLayer_conformance.json
		chown root:root /usr/share/vulkan/implicit_layer.d/VkLayer_conformance.json
		chmod 0644 /usr/share/vulkan/implicit_layer.d/VkLayer_conformance.json
	else
		rm -rf /opt/vk-layer /usr/share/vulkan/implicit_layer.d/VkLayer_conformance.json
	fi
