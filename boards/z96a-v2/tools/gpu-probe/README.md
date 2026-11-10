# GPU / Vulkan 诊断工具

2026-11-09 在 `.84` 上用来定位 Panfrost / PanVK / wgpu 问题的工具，保留以便复现。

## egl_t1t4.c

EGL/GLES/X11 全链路测试（T1 上下文 → T2 着色器 → T3 FBO 回读 → T4 窗口呈现）。

```sh
aarch64-linux-gnu-gcc -O2 -o egl_t1t4 egl_t1t4.c -lEGL -lX11 -lGLESv2
DISPLAY=:0 ./egl_t1t4 5
```

期望：`GL_RENDERER=Mali-G52 r1 MC1 (Panfrost)`，T1–T4 全 OK。

## xcap32.c

抓窗口像素并统计 RGB + **alpha 通道**，用来区分"真渲染"和"透明/黑屏"。

```sh
aarch64-linux-gnu-gcc -O2 -o xcap32 xcap32.c -lX11
DISPLAY=:0 ./xcap32 <window-id>
```

关键指标：
- 真 GPU/软件渲染：`alpha=255`
- GPUI GL 非 robust 上下文故障：`alpha=0`（100%）

配合 `ppmstats.py` 统计 PPM 的颜色分布。

## wgpu30probe

最小 wgpu 30 程序：枚举 Vulkan adapter、请求 device、跑一个离屏 render pass 并回读。

```sh
cargo build --release --target aarch64-unknown-linux-gnu
# 默认：带 ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER
# PROBE_DEFAULT_FLAGS=1：使用 InstanceFlags::default()（验证 conformance layer）
```

判读：
- 只有 llvmpipe → PanVK 没加载（缺 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`）
- 有 Mali 但应用看不到 → conformance layer 未生效
- `RENDER: ... OK` → Vulkan 渲染链路完整

## 判断"是否真的用 GPU"

不要只看画面是否正常，看这两项：

```sh
ls -l /proc/<pid>/fd | grep /dev/dri     # llvmpipe 不会打开
cat /sys/class/devfreq/fde60000.gpu/cur_freq   # 渲染时应升到 800MHz
```
