# configure/30-locale.sh — Chinese locale, fonts and fontconfig
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	# Z96A keyboard keeps sending KEY_REFRESH instead of KEY_MICMUTE.
	udevadm hwdb --update || true
	ldconfig


	# Chinese locale and desktop font fallback
	sed -i 's/^# *zh_CN\.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
	sed -i 's/^# *en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
	locale-gen
	cat > /etc/default/locale <<'LOCALEEOF'
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LOCALEEOF
	for line in LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh; do
		env_key=${line%%=*}
		if grep -q "^${env_key}=" /etc/environment 2>/dev/null; then
			sed -i "s#^${env_key}=.*#${line}#" /etc/environment
		else
			echo "${line}" >> /etc/environment
		fi
	done
	sed -i '/^LC_ALL=/d' /etc/environment
	install -d -m 0755 /home/user/.config/gtk-3.0
	cat > /home/user/.config/gtk-3.0/settings.ini <<'GTKEOF'
[Settings]
gtk-font-name=Noto Sans CJK SC 10
gtk-double-click-time=700
gtk-double-click-distance=10
GTKEOF
	cat > /home/user/.gtkrc-2.0 <<'GTK2EOF'
gtk-font-name = "Noto Sans CJK SC 10"
gtk-double-click-time = 700
gtk-double-click-distance = 10
GTK2EOF
