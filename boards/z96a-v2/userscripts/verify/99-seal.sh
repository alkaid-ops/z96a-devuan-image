# verify/99-seal.sh — package closure check and first-boot credentials
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	if [ "$ENABLE_LOCALSEND" = "1" ]; then
		chown root:root /opt/localsend /opt/localsend/* /usr/local/bin/localsend-next 2>/dev/null || true
		chmod 0755 /opt/localsend/localsendd /opt/localsend/localsend-gui /usr/local/bin/localsend-next 2>/dev/null || true
	else
		rm -rf /opt/localsend /usr/local/bin/localsend-next
	fi


	# Required package and dependency closure must be complete before sealing.
