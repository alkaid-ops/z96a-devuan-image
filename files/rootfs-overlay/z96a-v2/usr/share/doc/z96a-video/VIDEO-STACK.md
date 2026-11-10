# Z96A VA-API / V4L2 video stack

This image runs Devuan 6 Excalibur with the mainline Linux kernel and ships
`v4l2stateless_drv_video.so`, a libva backend that translates VA-API decode
requests into Linux V4L2 Request API operations on RK3568.

## Enabled APIs

- Native V4L2 Request for GStreamer `v4l2codecs` and the bundled mpv/FFmpeg.
- VA-API through `LIBVA_DRIVER_NAME=v4l2stateless`.
- VDPAU compatibility through `VDPAU_DRIVER=va_gl` when available.
- Mesa 25 Panfrost for hardware OpenGL ES 3.1 / OpenGL 3.1.

Desktop applications that require a newer OpenGL profile must use an
application-specific compatibility wrapper. OxideTerm currently uses llvmpipe
and the compatibility render profile on this platform.

## Supported by this RK3568 image

- H.264 Constrained Baseline / Main / High, NV12, 8-bit.
- HEVC Main, NV12, 8-bit.
- MPEG-2 Simple / Main (Hantro).
- VP8 (Hantro).
- JPEG encode and RGA VPP when their V4L2 nodes are present.

## Deliberately not advertised

- H.264 High10 / High422.
- HEVC Main10.
- VP9 and AV1.
- Vulkan Video and OpenMAX.

The current kernel exposes no 10-bit capture format on rkvdec; advertising it
would let clients select a path that cannot produce frames. Unsupported codecs
must fall back to software decoding. PanVK is not enabled because Mali-G52 v7
support is experimental and non-conformant.

## Driver provenance

- Source: https://github.com/pty819/vaapi-v4l2-bridge
- Base commit: `acf7e7a12da4651d2bd136d7cd683efdb527486c`
- Devuan 6 compatibility patch: `boards/z96a-v2/patches/video/0001-z96a-rk3568-profiles-libva22.patch`
- Built against libva 2.22 and the Devuan 6 UAPI headers.
- Installed library: `/usr/lib/aarch64-linux-gnu/dri/v4l2stateless_drv_video.so`
- SHA256: `d0f70cb79e611bcd8faede5925d27db958475c83a60831af7d1b33af0f4708d3`

## Application defaults

- Celluloid: `mpv-options=hwdec=vaapi-copy` (its libmpv prevents zero-copy VA-API).
- Command-line mpv: `/home/user/.config/mpv/mpv.conf` uses native
  `v4l2request` and `vo=gpu`; the bundled mpv includes FFmpeg 9 and exposes the
  V4L2 Request decoders.
- VLC: `avcodec-hw=vaapi`.
- Thorium wrapper: `/usr/local/bin/z96a-thorium` 只补充输入法环境，不再覆盖 GL 后端；Thorium 自带包装脚本设置 `--use-gl=egl` 和 `--hardware-video-device-path`。ANGLE GLES 在本平台无法导入 V4L2 NV12 DMA-BUF，会表现为 MP4 黑屏。

If a browser shows a black picture while FFmpeg decoding works, test:

```sh
V4L2SL_EXPBUF_EXPORT=0
```
