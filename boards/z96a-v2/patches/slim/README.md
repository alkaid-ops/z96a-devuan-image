# Z96A slimlock patches

The image uses SLiM 1.4.1. Build from the matching Devuan source tree:

1. Apply `0001-z96a-power-status-1.4.1.patch` for the power status line and
   lock-ready marker.
2. Apply `0002-z96a-lock-controls-1.4.1.patch` for mouse controls, confirmed
   power actions, and reliable keyboard/pointer capture.
3. Build with `-DUSE_CONSOLEKIT=no`; Devuan 6 uses elogind in this image and
   the build image does not provide the old ConsoleKit development package.
   `0003-z96a-disable-consolekit-1.4.1.patch` makes that package-build choice
   explicit.

The `.84` development USB uses Devuan 5 / SLiM 1.4.0. Apply its existing
base state and `0002-z96a-lock-controls-1.4.0.patch`; do not install the 1.4.1
package there.

The patches do not replace PAM authentication or add another locker. Power
actions invoke `loginctl` as the active local user and still require the narrow
polkit rule in `/etc/polkit-1/rules.d/50-z96a-power-policy.rules`.
