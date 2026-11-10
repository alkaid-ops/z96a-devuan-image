# Z96A Chinese input method (WindInput)

The image uses Fcitx5 with WindInput (清风输入法) as the default Chinese input
method.

## Installed components

- `fcitx5`
- `fcitx5-frontend-gtk3`
- `fcitx5-frontend-qt5`
- `fcitx5-config-qt`
- `windinput` 0.128.0 ARM64
- WindInput package SHA256:
  `4a1f0c563081454fbab349fe2361d4f63d472c507c478488e627120c34492386`

## Defaults

- Fcitx5 profile: only `windinput` is enabled; the separate English keyboard and
  standalone Fcitx Pinyin engines are not added to the input-method list.
- WindInput schema: `active = "pinyin"`.
- Left and right Shift toggle WindInput between its Chinese Pinyin and English
  modes. Switching to English commits the current unconverted Pinyin text.
- GTK/Qt/IM environment: `fcitx`.
- Login autostart: `~/.config/autostart/fcitx5.desktop`.
- `im-config` selection: Fcitx5.

WindInput ships Wubi as its factory schema. Without the user-level
`~/.config/WindInput/config.toml` override (`active = "pinyin"`), typing pinyin
will be treated as Wubi input. Do not omit that file.

## Verification

A GTK test entry was typed with `nihao`, space and Enter, producing `你好`.
Manual toggle: left or right Shift. Configuration GUI: `fcitx5-config-qt`.
