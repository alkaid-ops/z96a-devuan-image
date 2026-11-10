# configure/85-theme.sh — Z96A themes, desktop shortcuts, brightness keys
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	for slim_theme in /usr/share/slim/themes/default/slim.theme /usr/share/slim/themes/original/slim.theme; do
		[ -f "$slim_theme" ] || continue
		sed -i -E '/^[[:space:]]*(msg_font|input_font|username_font|welcome_font)[[:space:]]+/ s/Verdana/Noto Sans CJK SC/' "$slim_theme"
	done
	cat > /home/user/.Xresources <<'XRESEOF'
Xft.dpi: 144
XRESEOF
	chown user:user /home/user/.Xresources
	install -m 0755 /opt/z96a/session/xinitrc /home/user/.xinitrc
	chown user:user /home/user/.xinitrc
	chown -R user:user /home/user/.config/autostart /home/user/.config/z96a /home/user/.config/lxqt

	# Z96A Win7 LXQt theme: ambiance glass with a Windows-style start orb.
	if [ "$ENABLE_DESKTOP" = "1" ] && [ -d /usr/share/lxqt/themes/ambiance ]; then
		for theme in Win7:start-orb Win10:start-win10; do
			name=Z96A-${theme%%:*}
			logo=${theme#*:}.png
			rm -rf "/usr/share/lxqt/themes/$name"
			cp -a /usr/share/lxqt/themes/ambiance "/usr/share/lxqt/themes/$name"
			install -m 0644 "/usr/share/z96a/icons/$logo" "/usr/share/lxqt/themes/$name/$logo"
			sed -i "s|url(mainmenu.svg)|url($logo)|g" "/usr/share/lxqt/themes/$name/lxqt-panel.qss"
			cat "/opt/z96a/session/config/lxqt-themes/${name}-panel.qss" >> "/usr/share/lxqt/themes/$name/lxqt-panel.qss"
		done
	fi
	runuser -u user -- env HOME=/home/user XDG_CONFIG_HOME=/home/user/.config XDG_STATE_HOME=/home/user/.local/state /usr/local/bin/z96a-theme switch windows7
	runuser -u user -- env HOME=/home/user XDG_CONFIG_HOME=/home/user/.config /usr/local/bin/z96a-desktop-shortcut --all >/dev/null 2>&1 || true
	for entry in geany.desktop:accessories-text-editor htop.desktop:utilities-system-monitor \
		mc.desktop:system-file-manager mcedit.desktop:accessories-text-editor \
		xarchiver.desktop:file-roller \
		org.geeqie.Geeqie.desktop:image-x-generic \
		org.flameshot.Flameshot.desktop:applets-screenshooter; do
		file=${entry%%:*}
		icon=${entry#*:}
		[ -f "/home/user/Desktop/$file" ] && sed -i "s|^Icon=.*|Icon=$icon|" "/home/user/Desktop/$file"
	done
