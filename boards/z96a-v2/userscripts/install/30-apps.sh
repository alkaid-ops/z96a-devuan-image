# install/30-apps.sh — bundled ARM64 applications and OxideTerm launcher
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.



	# Locally verified ARM64 applications and custom mpv 0.41
	for pkg in \
		/opt/z96a/packages/OxideTerm_2.2.6_linux_arm64.deb \
		/opt/z96a/packages/thorium-browser_156.0.8078.28_arm64.deb \
		/opt/z96a/packages/deckcraft-0.11.1-linux-aarch64.deb \
		/opt/z96a/packages/gridcraft-0.12.1-linux-aarch64.deb \
		/opt/z96a/packages/wordcraft-0.11.0-linux-aarch64.deb \
		/opt/z96a/packages/WeChatLinux_arm64.deb \
		/opt/z96a/packages/QQ_3.2.34_260924_arm64_01.deb; do
		[ "$ENABLE_APPS" = "1" ] || continue
		install_required_deb "$pkg"
	done
	if [ "$ENABLE_MULTIMEDIA" = "1" ]; then
		install_required_deb /opt/z96a/packages/mpv_0.41.0-2_arm64_bookworm.deb
	fi
	for pkg in \
		/opt/z96a/packages/slim_1.4.1-1devuan1+excalibur2+z96a2_arm64.deb \
		/opt/z96a/packages/z96a-power-policy_1.0.2_arm64.deb; do
		install_required_deb "$pkg"
	done
	if [ ! -x /opt/oxideterm/oxideterm-native ] || [ ! -f /usr/share/applications/com.oxideterm.app.desktop ]; then
		echo "OxideTerm package did not install its native binary or desktop entry" >&2
		exit 1
	fi
