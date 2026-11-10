# mpv X11 下 4K / 1080p HEVC 硬件解码播放实测报告

板端：`z96a-devuan`（RK3568，Devuan 6 / excalibur，Linux 7.2.12，X11 + openbox + slim，eDP 1920×1080@60）

## 1. 结论摘要

| 场景 | 媒体推进 | 呈现 fps | 结论 |
|---|---|---|---|
| 1080p60 H.264 | 1.000x | **60.0** | 达标，0 丢帧 |
| 1080p60 H.265 | 1.001x（Thorium 对照） | 60.3 | 达标 |
| 4K60 HEVC，默认参数 | 0.497x | 6.8 | ❌ 不实时 |
| 4K60 HEVC，`--gpu-dumb-mode=yes` | **1.007x** | **40.6** | ✅ 不漂移，约 40fps 呈现 |
| Thorium 播同一 4K 文件 | 0.482x | 31.8 | 比 mpv 更差 |

要点：

1. **决定性选项是 `--gpu-dumb-mode=yes`**。它把 mpv 从“两趟全屏 GPU pass”降为近似单趟，4K 从 0.497x 提到 1.007x。
2. **不要加 `--opengl-swapinterval=0`**：在同一 4K 用例上实测把呈现从 40.6 掉到 25.8。
3. 1080p h264/265 已经完全达标（60fps、0 丢帧）。
4. 4K60 的 60fps 呈现在这条 X11 + GPU 合成路径上**做不到**：mpv 约 40fps，Thorium 约 32fps。要真 4K60 必须走硬件视频平面（DRM/KMS 直出），不属于本方案。
5. **RGA 集成可以取消**：该内核的 RGA（V4L2 M2M）不支持 DMABUF 导入，无法零拷贝；且 4K 的瓶颈不在缩放。

## 2. 环境

| 项 | 值 |
|---|---|
| 内核 | 7.2.12（上一版为 7.2.11） |
| GPU | Mali-G52 r1（Panfrost），Mesa 25.0.7（本报告实测时；当前镜像已升级到 26.1.6） |
| X11 | DRI3 + Present 可用；无合成器（仅 openbox） |
| 显示 | eDP-1 1920×1080@60.02 |
| V4L2 解码器 | `hantro-vpu`（H.264，S264）、`rkvdec`（HEVC，S265） |
| RGA | `rockchip-rga` / card `rga2` |

注意：`/dev/video*` 的序号**重启后会变**（本次 RGA 由 `video1` 变为 `video0`，`video1` 变成 hantro）。任何实现都必须按驱动名枚举，不能硬编码索引。

## 3. 软件栈（隔离部署，未改动系统包）

- FFmpeg **n9.0.2** + LibreELEC 补丁集（固定提交 `a1d24cae66825c22ba2d6c6013886347a9f66081`）：postproc、V4L2 Request、VC-1、HEVC ext SPS。
- mpv **0.41.0** + `philipl/mpv` V4L2 Request 提交 `1800573999b29a145de3eb303a0b51d840a6b3de`、`beb3771179b45096702c0b15704bf5b0ca5f9d61`；另加 Meson 条件使其在非 DRM VO 构建下仍编译 `hwdec_drmprime`。
- 部署位置：`/opt/mpv-rga`（`/usr/bin/mpv` 与系统包未动）。
- 运行时确认：`hwdec-current=v4l2request`、`hwdec-interop=drmprime,v4l2request`、`VO: [gpu] … drm_prime[nv12]`。

## 4. 实测数据

均为手机器空闲时测得；早期存在并发负载的数据已废弃（见第 6 节）。

### 4.1 纯解码吞吐（FFmpeg + v4l2request，无显示）

| 用例 | 硬解设备 | 结果 |
|---|---|---|
| 4K HEVC | `rkvdec` (7.2.12) | **76.3 fps**（300 帧 / 3.934 s） |
| 1080p H.264 | `hantro-vpu` (7.2.12) | **72.9 fps**（300 帧 / 4.117 s） |
| 4K HEVC（软件解码对照） | — | 14.3 fps |

结论：解码不是瓶颈，4K60 有余量。

### 4.2 呈现 / GPU 微基准（同一 EGL/X11 路径）

| 测试 | 条件 | fps |
|---|---|---|
| 裸交换（无绘制） | 1080p，swapinterval=1 / 0 | 60.0 / 124.4 |
| 全屏四边形采样 1080p RGB | interval=0 / 1 | 74.2 / 50.4 |
| 全屏四边形采样 1080p 两平面 YUV | interval=0 | 59.7 |
| 全屏采样 4K 纹理 → 1080p 输出 | interval=0 | 50.7 |

| EGLImage 操作 | 耗时 |
|---|---|
| 4K NV12 dma-buf create+destroy | 0.026 ms/帧 |
| 1080p NV12 dma-buf create+destroy | 0.025 ms/帧 |
| 复用 + glEGLImageTargetTexture2DOES | 0.001 ms/帧 |

结论：X11 呈现与 EGLImage 导入都不是瓶颈；瓶颈是 GPU 的采样/合成吞吐。

### 4.3 1080p60 真实播放（20 秒采样）

| 配置 | 媒体推进 | 呈现 fps | 丢帧 | CPU |
|---|---|---|---|---|
| 默认 | 1.000x | 60.0 | 0 | 54% |
| + bilinear | 1.000x | 60.0 | 0 | 56% |
| + bilinear + `--swapchain-depth=1` | 1.000x | 60.0 | 0 | 54% |

### 4.4 4K60 HEVC 真实播放（目标文件 `/home/user/Test Jellyfin 4K HEVC 8bit 60M.mp4`）

| 配置 | 媒体推进 | 呈现 fps | CPU |
|---|---|---|---|
| 默认 | 0.497x ❌ | 6.8 | 32% |
| `--gpu-dumb-mode=yes` | **1.007x** ✅ | **40.6** | 84% |
| + `--dither=no` | 1.004x | 40.4 | 87% |
| + `--swapchain-depth=1` | 1.002x | 39.9 | 81% |
| + bilinear 缩放 | 1.008x | 38.4 | 88% |
| `vo=gpu-next` + dumb | 1.001x | 37.5 | 78% |
| + `--opengl-early-flush=yes` | 1.005x | 39.6 | 90% |
| + `--opengl-swapinterval=0` | 0.984x ❌ | 25.8 | 61% |

### 4.5 Thorium 对照（同一文件、同一机器）

| 用例 | 媒体推进 | 呈现 | 丢帧 | `video.error` |
|---|---|---|---|---|
| 1080p60 H.264 | 1.002x | 60.1 fps | 20/10s | null |
| 1080p60 H.265 | 1.001x | 60.3 fps | 30/10s | null |
| **4K60 HEVC** | **0.482x** | 31.8 fps | 2/10s | null |

Thorium（156.0.8078.28）日志确认走 **V4L2 stateless 硬解**（`media/gpu/v4l2`，fourcc S264/S265，NV12，`V4L2 import path` 零拷贝），与我们的 FFmpeg/mpv 用的是同一套内核 API。

日志中除 `dbus` 噪声外，唯一的媒体相关 `ERROR` 是 `media/base/status.h:570 DecoderStatus::0`（状态码 0 = OK，属日志级别瑕疵），**无 `MEDIA_ERR_*` / `PIPELINE_ERROR`**。

## 5. RGA 调查结论（已否掉）

- 该内核的 RGA 只暴露 V4L2 M2M，**没有** `/dev/rga`，也没有 librga。
- MMAP 队列可用、`VIDIOC_EXPBUF` 导出正常；但 **`V4L2_MEMORY_DMABUF` 导入失败**：
  - rkvdec 解出的 dma-buf：`VIDIOC_QBUF` → `EINVAL`
  - `dma-heap/system` 分配的 dma-buf：同样 `EINVAL`
  - 单平面提交同样 `EINVAL`
  - 对照：同队列 `V4L2_MEMORY_MMAP` 提交 `QBUF` 成功
- 调试中发现并确认了 vb2 的一条校验：带 `data_offset` 的平面，`bytesused/length` 必须包含偏移量（total extent），否则 `EINVAL`。修正后仍 `EINVAL`，说明是队列/驱动层不接受 DMABUF 导入。
- 因此 4K→1080p 零拷贝缩放不可行；若强行用 MMAP 需每帧 12.4MB CPU 拷贝，且 4K 瓶颈本来就不在缩放（dumb 模式下 4K 与 1080p 输入差异很小）。

**结论：不投入 RGA 集成。**

## 6. 数据可信度说明（重要）

本会话早期的一批“真实播放”数据（4K 默认 0.435x、最优 0.836x、1080p 约 44fps 等）是在**另一会话同时占用板子**的情况下测得（板端 `/tmp` 中出现不属于本任务的 `celluloid.log`、`evtest.log`、`qterminal-run.log`、`after-watch-test.png` 等）。这些数字**已废弃**，以第 4 节空闲状态重测值为准。

不受影响的数据：4.1 解码吞吐、4.2 GPU/EGL 微基准（直接测量，对负载不敏感）、第 5 节驱动层结论。

同时需要留意：`/tmp` 可能在会话之间被清理，因此测试工具已固化到 `/opt/mpv-rga/share/bench/`。

## 7. 部署与使用方法

新增文件（均在隔离目录内）：

- `/opt/mpv-rga/etc/mpv/mpv.conf` —— 调优默认值
- `/opt/mpv-rga/bin/mpv-x11` —— 包装脚本，固定 `--config-dir` 指向上述配置
- `/opt/mpv-rga/share/bench/` —— 本次使用的测量工具与 C 源码

`mpv.conf` 内容：

```
hwdec=v4l2request
vo=gpu
gpu-context=x11egl
gpu-dumb-mode=yes
dither=no
```

用法：

```
/opt/mpv-rga/bin/mpv-x11 <file>
```

注意：若额外传 `--no-config` 会忽略上述调优；需要覆盖时直接追加选项即可（后出现的生效）。

端到端验证（经包装脚本 + 配置，4K 目标文件，15 秒）：

```
hw=v4l2request  present=39.7 fps  media=1.007  cpu=92%
```

## 8. 复现方法

工具（板端 `/opt/mpv-rga/share/bench/`）：

| 文件 | 用途 |
|---|---|
| `playcheck.py` | 真实播放采样（经 mpv JSON IPC；输出媒体速度/呈现 fps/丢帧/CPU） |
| `mcap2.py` | `--untimed` 容量测试 |
| `decodebench` | FFmpeg + v4l2request 纯解码吞吐 |
| `cdp_probe.py` | Thorium/Chromium 播放状态与 `getVideoPlaybackQuality()` |
| `eglswapbench` | 裸 EGL/X11 交换速率 |
| `glsamp` | 全屏四边形纹理采样吞吐（需 `LD_LIBRARY_PATH` 指向同目录 `libGLESv2.so.2`） |
| `eglimportbench` | EGLImage dma-buf 导入/销毁耗时（需 root，`dma_heap`） |
| `rgadmabuf` | 解码 dma-buf → RGA M2M 导入/导出验证 |
| `rgaheap` | RGA DMABUF 导入最小验证（`dma_heap`） |

示例：

```
export DISPLAY=:0 XAUTHORITY=/home/user/.Xauthority
python3 /opt/mpv-rga/share/bench/playcheck.py <file> 20 <label> \
    --hwdec=v4l2request --vo=gpu --gpu-context=x11egl --gpu-dumb-mode=yes
LD_LIBRARY_PATH=/opt/mpv-rga/share/bench python3 ...  # glsamp 等
```

1080p60 测试素材可用 host ffmpeg 生成：

```
ffmpeg -f lavfi -i "testsrc2=size=1920x1080:rate=60:duration=30" \
  -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p t1080p60-h264.mp4
ffmpeg -f lavfi -i "testsrc2=size=1920x1080:rate=60:duration=30" \
  -c:v libx265 -preset ultrafast -crf 24 -pix_fmt yuv420p t1080p60-h265.mp4
```

## 9. 边界与后续

- **1080p h264/265：已达标**（60fps、0 丢帧、硬解零拷贝）。
- **4K60 HEVC：媒体不漂移，呈现约 40 fps**（mpv，dumb 模式）。约 1/3 帧被丢弃。
- 若必须 4K60 满帧呈现：需要**硬件视频平面直出**（DRM/KMS plane；旧定制播放器曾达 presented 57fps），或其他能绕开 GPU 全屏合成的呈现方式。X11 + GPU 合成下 Thorium 也只有约 32fps，说明这是平台上限而非 mpv 实现问题。
- 未做：4K 下的进一步调优（更深解码帧池、单趟合成补丁）。若后续要试，优先验证“解码帧池加深是否能减少丢帧抖动”，而不是继续改缩放。
