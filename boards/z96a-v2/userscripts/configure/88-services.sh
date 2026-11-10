# configure/88-services.sh — service registration, SSH keys/passwords, sshd
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	rm -rf /home/user/.cache/openbox/sessions
	globalkeys=/home/user/.config/lxqt/globalkeyshortcuts.conf
	globalkeys_defaults=/etc/xdg/lxqt/globalkeyshortcuts.conf/globalkeyshortcuts.conf
	for shortcut in 'XF86MonBrightnessDown.4:5%-' 'XF86MonBrightnessUp.5:5%+' 'Shift%2BControl%2BF6.2:5%-' 'Shift%2BControl%2BF7.3:5%+'; do
		section=${shortcut%%:*}
		brightness_step=${shortcut#*:}
		sed -i "/^\\[$section\\]/,/^\\[/ s|^Exec=.*|Exec=brightnessctl, --device=backlight, set, $brightness_step|" "$globalkeys_defaults"
	done
	update-rc.d slim defaults >/dev/null 2>&1 || true

	mv -f /root/z96a-bt-after-wifi /usr/local/sbin/z96a-bt-after-wifi

	install -d -m 0700 /root/.ssh /home/user/.ssh
	printf '%s\n' "$key" > /root/.ssh/authorized_keys
	printf '%s\n' "$key" > /home/user/.ssh/authorized_keys
	chmod 0600 /root/.ssh/authorized_keys /home/user/.ssh/authorized_keys
	chown -R root:root /root/.ssh
	chown -R user:user /home/user/.ssh

	mkdir -p /etc/ssh/sshd_config.d
	if [ -n "${Z96A_ROOT_PASSWORD:-}" ]; then
		printf 'root:%s\n' "$Z96A_ROOT_PASSWORD" | chpasswd
		cat > /etc/ssh/sshd_config.d/99-z96a-root-login.conf <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
EOF
	else
		random_password=$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')
		printf 'root:%s\n' "$random_password" | chpasswd
		unset random_password
		cat > /etc/ssh/sshd_config.d/99-z96a-root-login.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
EOF
	fi
	sed -i 's/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
	sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
	if [ -f /usr/local/bin/credentials ]; then
		sed -i \
			-e '\|^rm -f /etc/ssh/ssh_host_\*$|d' \
			-e '\|^dpkg-reconfigure openssh-server$|d' \
			/usr/local/bin/credentials
		if ! grep -Fxq 'ssh-keygen -A' /usr/local/bin/credentials; then
			sed -i '/^service ssh restart$/i ssh-keygen -A' /usr/local/bin/credentials
		fi
	fi
	cat > /etc/init.d/z96a-ssh-hostkeys <<'SSHKEYSEOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          z96a-ssh-hostkeys
# Required-Start:    $local_fs
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Create missing persistent OpenSSH host keys
### END INIT INFO

case "${1:-}" in
	start)
		/usr/bin/ssh-keygen -A || exit 1
		test -s /etc/ssh/ssh_host_ed25519_key || exit 1
		;;
	stop|restart|reload|force-reload)
		;;
	*)
		exit 2
		;;
esac

exit 0
SSHKEYSEOF
