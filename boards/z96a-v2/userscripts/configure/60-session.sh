# configure/60-session.sh — z96a binaries, LXQt config, launchers, menus, elogind
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	for line in GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx SDL_IM_MODULE=fcitx; do
		key=${line%%=*}
		if grep -q "^${key}=" /etc/environment 2>/dev/null; then
			sed -i "s#^${key}=.*#${line}#" /etc/environment

		else
			echo "${line}" >> /etc/environment
		fi
	done
	chown -R user:user /home/user/.xinputrc /home/user/.config/fcitx5 /home/user/.config/autostart /home/user/.config/WindInput /home/user/.config/z96a
	install -m 0755 /opt/z96a/hotkeys/z96a-hotkey /usr/local/bin/z96a-hotkey
	install -m 0755 /opt/z96a/window/z96a-window-tile /usr/local/bin/z96a-window-tile
	install -m 0755 /opt/z96a/desktop/z96a-desktop-shortcut /usr/local/bin/z96a-desktop-shortcut
	install -m 0755 /opt/z96a/desktop/z96a-system-tray /usr/local/bin/z96a-system-tray
	install -m 0755 /opt/z96a/desktop/z96a-desktop-trust /usr/local/bin/z96a-desktop-trust
	install -m 0755 /opt/z96a/desktop/z96a-volume-feedback /usr/local/bin/z96a-volume-feedback
	install -d -m 0755 /usr/local/lib/z96a/desktop /usr/local/bin /home/user/.config/autostart
	install -m 0755 /opt/z96a/desktop/z96a-theme /usr/local/lib/z96a/desktop/z96a-theme
	cp -a /opt/z96a/desktop/profiles /usr/local/lib/z96a/desktop/
	install -d -m 0755 /home/user/.config/lxqt
	install -m 0644 /opt/z96a/session/lxqt/lxqt-powermanagement.conf /home/user/.config/lxqt/lxqt-powermanagement.conf
	install -m 0644 /opt/z96a/session/lxqt/power.conf /home/user/.config/lxqt/power.conf
	install -m 0644 /opt/z96a/session/lxqt/session.conf /home/user/.config/lxqt/session.conf
	install -m 0644 /opt/z96a/session/lxqt/globalkeyshortcuts.conf /home/user/.config/lxqt/globalkeyshortcuts.conf
	ln -sf /usr/local/lib/z96a/desktop/z96a-theme /usr/local/bin/z96a-theme
	install -m 0755 /opt/z96a/session/lxqt/services /usr/local/bin/z96a-lxqt-services
	install -m 0644 /opt/z96a/session/lxqt/z96a-services.desktop /home/user/.config/autostart/z96a-services.desktop
	install -d -m 0755 /usr/local/share/sounds/z96a
	install -m 0644 /opt/z96a/sounds/z96a-volume-preview.wav /usr/local/share/sounds/z96a/volume-preview.wav
	install -d -m 0755 /home/user/Desktop /home/user/.config/pcmanfm-qt/z96a /home/user/.config/qterminal.org
	install -m 0755 /opt/z96a/session/desktop/z96a-control-center.desktop /home/user/Desktop/z96a-control-center.desktop
	install -m 0755 /opt/z96a/session/desktop/z96a-network.desktop /home/user/Desktop/z96a-network.desktop
	install -m 0755 /opt/z96a/session/desktop/z96a-terminal.desktop /home/user/Desktop/z96a-terminal.desktop
	install -m 0755 /opt/z96a/session/desktop/z96a-file-manager.desktop /home/user/Desktop/z96a-file-manager.desktop
	install -m 0755 /opt/z96a/session/desktop/z96a-browser.desktop /home/user/Desktop/z96a-browser.desktop
	# UseTrash=false means PCManFM-Qt no longer creates the Trash desktop icon; ship a static one.
	install -m 0755 /opt/z96a/session/desktop/trash-can.desktop /home/user/Desktop/trash-can.desktop
		rm -f /usr/local/bin/z96a-brightness-tray
	rm -f /usr/share/applications/debian-xterm.desktop /usr/share/applications/debian-uxterm.desktop /usr/share/applications/qterminal-drop.desktop /usr/share/applications/lxterminal.desktop
	rm -f /usr/share/applications/org.chromium.Thorium.desktop /usr/share/applications/thorium-shell.desktop \
		/usr/share/applications/fcitx5-configtool.desktop /usr/share/applications/org.fcitx.Fcitx5.desktop \
		/usr/share/applications/fcitx5-wayland-launcher.desktop /usr/share/applications/org.fcitx.fcitx5-qt5-gui-wrapper.desktop \
		/usr/share/applications/gcr-prompter.desktop /usr/share/applications/gcr-viewer.desktop \
		/usr/share/applications/org.gnome.Zenity.desktop /usr/share/applications/python3.13.desktop \
		/usr/share/applications/openbox.desktop /usr/share/applications/lxqt-panel.desktop \
		/usr/share/applications/notification-daemon.desktop \
		/usr/share/applications/xdg-desktop-portal-gtk.desktop /usr/share/applications/pcmanfm-desktop-pref.desktop \
		/usr/share/applications/lxqt-hibernate.desktop /usr/share/applications/lxqt-leave.desktop \
		/usr/share/applications/lxqt-logout.desktop
	# Start menu power entries: no "离开" level, no hibernate/logout, and the
	# fixed order 锁屏 → 挂起 → 关机 → 重启.
	lxqt_menu=/etc/xdg/menus/lxqt-applications.menu
	if [ -f "$lxqt_menu" ]; then
		python3 - "$lxqt_menu" <<'LXQTMENUEOF'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

text = text.replace(
    '<Menuname show_empty="false">X-Leave</Menuname>',
    '<Menuname show_empty="false" inline="true">X-Leave</Menuname>',
)
text = text.replace(
    '<Menuname show_empty="false" inline="true">X-Leave</Menuname>\n'
    '\t\t<Menuname show_empty="false" inline="true">Screensaver</Menuname>',
    '<Menuname show_empty="false" inline="true">Screensaver</Menuname>\n'
    '\t\t<Menuname show_empty="false" inline="true">X-Leave</Menuname>',
)
old_leave = """\t\t\t<And>
\t\t\t\t<Category>X-Leave</Category>
\t\t\t</And>
\t\t</Include>
\t</Menu>\t <!-- End Leave -->"""
new_leave = """\t\t\t<And>
\t\t\t\t<Category>X-Leave</Category>
\t\t\t</And>
\t\t</Include>
\t\t<Layout>
\t\t\t<Filename>lxqt-suspend.desktop</Filename>
\t\t\t<Filename>lxqt-shutdown.desktop</Filename>
\t\t\t<Filename>lxqt-reboot.desktop</Filename>
\t\t</Layout>
\t</Menu>\t <!-- End Leave -->"""
text = text.replace(old_leave, new_leave)

open(path, "w", encoding="utf-8").write(text)
LXQTMENUEOF
	fi
	install -m 0644 /opt/z96a/session/config/pcmanfm-qt/z96a/settings.conf /home/user/.config/pcmanfm-qt/z96a/settings.conf
	install -m 0644 /opt/z96a/session/config/pcmanfm-qt/z96a/desktop-items-0.conf /home/user/.config/pcmanfm-qt/z96a/desktop-items-0.conf
	install -m 0644 /opt/z96a/session/config/qterminal/qterminal.ini /home/user/.config/qterminal.org/qterminal.ini
	install -m 0644 /opt/z96a/session/config/user-dirs.dirs /home/user/.config/user-dirs.dirs
	chown -R user:user /home/user/Desktop /home/user/.config/pcmanfm-qt /home/user/.config/qterminal.org /home/user/.config/user-dirs.dirs
	install -d -m 0755 /etc/elogind/logind.conf.d
	cat > /etc/elogind/logind.conf.d/99-z96a-power-key.conf <<'ELOGINDEOF'
[Login]
# LXQt's powermanager handles the desktop power/suspend keys through
# lxqt-globalkeys. Its logind Inhibit() call is denied by polkit on this image,
# so elogind must keep ignoring these keys to avoid double actions.
# The fallback outside an LXQt session is deliberately "no action".
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
ELOGINDEOF
