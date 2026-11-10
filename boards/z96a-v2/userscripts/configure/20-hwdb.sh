# configure/20-hwdb.sh — udev hwdb compile and ldconfig
# Sourced in order by boards/z96a-v2/userscripts/uscripts.
# Phase 2 module split: content and execution order unchanged.

	glib-compile-schemas /usr/share/glib-2.0/schemas || true

	# Compile the hwdb, otherwise /etc/udev/hwdb.d rules are ignored and the
