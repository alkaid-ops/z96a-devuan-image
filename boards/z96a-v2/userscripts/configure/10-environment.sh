# configure/10-environment.sh — video/Vulkan environment variables
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.



	for line in \
		LIBVA_DRIVER_NAME=v4l2stateless \
		LIBVA_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
		VDPAU_DRIVER=va_gl \
		PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1; do
		key=${line%%=*}
		if grep -q "^${key}=" /etc/environment 2>/dev/null; then
			sed -i "s#^${key}=.*#${line}#" /etc/environment
		else
			echo "${line}" >> /etc/environment
		fi
	done
