# install/10-base.sh — VA-API/Mesa/PanVK stack and runtime packages
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	# Z96A VA-API / video compatibility stack
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		libva2 libva-drm2 libgbm1 libegl1 libgl1-mesa-dri \
		libvdpau-va-gl1 \
		locales xclip libnotify4 libnss3 libxss1 libxtst6 libsecret-1-0

	# Z96A GPU: Vulkan/PanVK on Bifrost v7 (Mali-G52) only works with Mesa >= 26.1.
	# GLES stays fully compatible; this only upgrades the Mesa userspace stack.
	# MESA_BACKPORTS_PIN (optional) pins the exact backports version so two
	# builds do not silently pick different Mesa releases.
	mesa_target=()
	if [ -n "${MESA_BACKPORTS_PIN:-}" ]; then
		mesa_target=("$(printf 'libgl1-mesa-dri=%s' "$MESA_BACKPORTS_PIN")")
	fi
	# Detect backports from the apt sources, not `apt-cache policy`: with
	# `set -o pipefail` a non-zero apt-cache exit fails the pipeline even when
	# grep matches, which silently skipped the upgrade in one build.
	mesa_backports=0
	if grep -rqs 'excalibur-backports' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
		mesa_backports=1
	fi
	if [ "$mesa_backports" -eq 1 ]; then
		# Backports defaults to priority 100 and loses to main (500), so -t alone
		# does not upgrade an already-installed Mesa. Pin it explicitly.
		cat > /etc/apt/preferences.d/99-z96a-mesa <<'MESAEOF'
Package: mesa-vulkan-drivers libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgbm1 mesa-libgallium mesa-va-drivers mesa-vdpau-drivers
Pin: release n=excalibur-backports
Pin-Priority: 900
MESAEOF
		DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
			${mesa_target[@]+"${mesa_target[@]}"} \
			mesa-vulkan-drivers libgl1-mesa-dri libglx-mesa0 libegl-mesa0 \
			libgbm1 mesa-libgallium mesa-va-drivers mesa-vdpau-drivers
	else
		echo "WARNING: excalibur-backports not available; keeping distro Mesa" >&2
	fi
	# Record the Mesa actually installed and fail loudly if PanVK cannot work.
	mesa_version=$(dpkg-query -W -f='${Version}' libgl1-mesa-dri 2>/dev/null || echo unknown)
	install -d -m 0755 /etc/z96a
	printf '%s\n' "$mesa_version" > /etc/z96a/mesa-version
	case "$mesa_version" in
		2[6-9].*|3[0-9].*) : ;;
		*) if [ "$mesa_backports" -eq 1 ]; then
			echo "ERROR: Mesa ${mesa_version} < 26.1 despite backports; PanVK would be unusable" >&2
			exit 1
		else
			echo "WARNING: Mesa ${mesa_version} < 26.1 (no backports); PanVK falls back" >&2
		fi
		;;
	esac

	if [ -f /opt/z96a/runtime-packages.txt ]; then
		xargs -r env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends < /opt/z96a/runtime-packages.txt
	fi
