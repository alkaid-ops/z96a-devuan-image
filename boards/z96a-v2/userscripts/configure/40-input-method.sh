# configure/40-input-method.sh — WindInput packaging and Fcitx5 profile
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	chown -R user:user /home/user/.config/gtk-3.0
	chown user:user /home/user/.gtkrc-2.0
	fc-cache -f


	# WindInput (清风输入法) on Fcitx5
	install_required_deb /opt/z96a/packages/WindInput-0.128.0-linux-arm64.deb
	install -d -m 0755 /home/user/.config/fcitx5 /home/user/.config/autostart
	cat > /home/user/.xinputrc <<'XINPUTEOF'
run_im fcitx5
XINPUTEOF
	cat > /home/user/.config/autostart/fcitx5.desktop <<'AUTOSTARTEOF'
[Desktop Entry]
Type=Application
Name=Fcitx 5
Exec=fcitx5 -d
Icon=fcitx
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Phase=Applications
AUTOSTARTEOF
	cat > /home/user/.config/fcitx5/profile <<'FCITXPROFILEEOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=windinput

[Groups/0/Items/0]
Name=windinput
Layout=

[GroupOrder]
0=Default
FCITXPROFILEEOF
