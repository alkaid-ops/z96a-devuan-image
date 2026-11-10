# z96a-sysmon

A tiny in-process LXQt panel plugin showing CPU and memory usage on the first
line and network upload/download rates on the second line:

```text
CPU 12%  MEM 45%
↑0.3M  ↓1.2M
```

The plugin does not spawn a daemon or helper process. It samples `/proc`
every 2 seconds from inside `lxqt-panel`, so there is no extra entry in the
process list and no additional tray icon.

## Build

The LXQt panel plugin headers are provided by the installed `lxqt-panel`
package (`/usr/include/lxqt/ilxqtpanelplugin.h`). Build natively on the target
(or an arm64 sysroot) with Qt6:

```sh
sudo apt-get install g++ make cmake qt6-base-dev qt6-base-dev-tools pkg-config
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j2
```

The output is `build/libz96a-sysmon.so`.

## Install

```sh
sudo install -m 0755 build/libz96a-sysmon.so \
    /usr/lib/aarch64-linux-gnu/lxqt-panel/libz96a-sysmon.so
sudo install -m 0644 z96a-sysmon.desktop \
    /usr/share/lxqt/lxqt-panel/z96a-sysmon.desktop
```

Then add `sysmon` to the panel plugin list and a section:

```ini
[sysmon]
alignment=Right
type=z96a-sysmon
```

The prebuilt arm64 `.so` and desktop file are shipped in
`files/rootfs-overlay/z96a-v2/`; building is only needed after changing the
source.

## Notes

- Display is fixed to two lines at 13 px so it fits the 36–50 px panel heights
  used by the Z96A profiles.
- Network rates sum all non-loopback interfaces.
- Hovering shows a tooltip with the full CPU, memory, upload and download
  values.
