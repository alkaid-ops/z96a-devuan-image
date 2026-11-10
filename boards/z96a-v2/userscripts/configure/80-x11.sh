# configure/80-x11.sh — Xresources, .xinitrc and session parity
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	# Basic graphical session parity with the tested USB system
	# The LXQt main menu needs the menu prefix; without it the start button is dead.
	echo /usr/bin/slim > /etc/X11/default-display-manager
	if ! grep -q "^XDG_MENU_PREFIX=" /etc/environment 2>/dev/null; then
		echo "XDG_MENU_PREFIX=lxqt-" >> /etc/environment

	fi
	ln -sfn lxqt-applications.menu /etc/xdg/menus/applications.menu
	[ -f /etc/slim.conf ] || { echo 'SLiM configuration is missing' >&2; exit 1; }
	sed -i -E 's|^xserver_arguments[[:space:]]+.*|xserver_arguments   -dpi 144 -nolisten tcp -deferglyphs 16|' /etc/slim.conf
	sed -i -E '/^[[:space:]]*sessiondir[[:space:]]+/ s|^|#|' /etc/slim.conf
	set_slim_option() {
		local option="$1"
		local value="$2"
		if grep -Eq "^[[:space:]]*${option}[[:space:]]+" /etc/slim.conf; then
			sed -i -E "s|^[[:space:]]*${option}[[:space:]]+.*$|${option} ${value}|" /etc/slim.conf
		else
			printf '%s %s\n' "$option" "$value" >> /etc/slim.conf
		fi
	}
	set_slim_option sessions 'LXQt'
	set_slim_option login_cmd 'exec /bin/bash -login /home/user/.xinitrc %session'
