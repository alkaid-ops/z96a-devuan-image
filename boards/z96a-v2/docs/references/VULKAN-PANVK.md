# Vulkan / PanVK on Mali-G52（Bifrost v7）

最后更新：2026-11-09。全部在 `.84` 实机验证。

## 结论

| 项 | 状态 |
|---|---|
| PanVK（Mesa 26.1.6） | ✅ 可用，需 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` |
| wgpu 29（OxideTerm） | ✅ 可用（有 conformance layer，无需改应用） |
| LocalSend Next | ✅ 用 OpenGL/FemtoVG，不依赖 Vulkan 栈 |
| GLES 3.1 | ✅ 不受影响 |
| V4L2 Request 硬解 | ✅ 不受影响 |

## 为什么需要两样东西

### 1. PanVK 对 Bifrost 默认拒绝加载

`src/panfrost/vulkan/panvk_physical_device.c`：

```c
case 6: case 7: case 14:
    if (!os_get_option("PAN_I_WANT_A_BROKEN_VULKAN_DRIVER")) {
        return VK_ERROR_INCOMPATIBLE_DRIVER;
    }
```

→ 必须设置 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`，已写入 `/etc/environment`。

### 2. Mesa 对 v7 上报 conformanceVersion 0.0.0.0

同一文件：

```c
static VkConformanceVersion get_conformance_version(void) {
   if (PAN_ARCH == 10) return (VkConformanceVersion){1,4,5,2};
   return (VkConformanceVersion){0,0,0,0};   /* v6/v7 永远 0 */
}
```

26.2.6、26.3(main) 都是这样。wgpu 见 `major == 0` 就会：

```
Adapter is not Vulkan compliant, hiding adapter: Mali-G52 r1 MC1
```

→ 用 Vulkan layer 把该字段抬到 `1.3.0.0`。

## 组件

```
/opt/vk-layer/conformance_layer.c     源码
/opt/vk-layer/libconformance.so       aarch64 预编译
/opt/vk-layer/VkLayer_conformance.json
/opt/vk-layer/build.sh                重新编译用
/usr/share/vulkan/implicit_layer.d/VkLayer_conformance.json   全局 implicit
```

layer 只改 `VkPhysicalDeviceDriverProperties::conformanceVersion`，且仅当原值为 0；
合规驱动（llvmpipe 等）不受影响。

重新编译：

```sh
sudo apt install gcc-aarch64-linux-gnu libvulkan-dev:arm64
cd /opt/vk-layer && CC=aarch64-linux-gnu-gcc ./build.sh
```

## 验证

```sh
# 1. PanVK 出现
PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 vulkaninfo --summary | grep -A2 panvk

# 2. wgpu 能看到 Mali（默认 flags，不需要 ALLOW_UNDERLYING_...）
#    用最小 wgpu 30 程序 enumerate_adapters 应列出 Mali-G52 r1 MC1

# 3. 应用是否真的用了 GPU：看是否打开 /dev/dri/renderD128
ls -l /proc/<pid>/fd | grep dri
```

注意：llvmpipe 不会打开 `/dev/dri/*`，GPU 频率也不会升到 800MHz。
这两个是判断"真 GPU"还是"软件回退"的可靠指标。

## 应用状态

| 应用 | 后端 | 备注 |
|---|---|---|
| OxideTerm | Vulkan (wgpu 29) | 启动器 `/usr/local/bin/oxideterm` 设 `OXIDETERM_GPU_BACKEND=vulkan` |
| LocalSend Next | OpenGL/FemtoVG | `/usr/local/bin/localsend-next`；stock wgpu 在 PanVK 上不可用，因此改用官方 `backend-femtovg` 构建 |
| Thorium | Vulkan/GL | card0 + renderD128 |
| mpv | GLES (v4l2request) | 不受影响 |

OxideTerm 的 GL 路径在这颗芯片上仍不可用（无 `EGL_EXT_create_context_robustness`，
GPUI 走非 robust 上下文后画面全黑 alpha=0）。需要临时回退软件时：

```sh
OXIDETERM_FORCE_GL=1 oxideterm
```

## 镜像构建

`boards/z96a-v2/userscripts/uscripts` 的 `run_function2` 做了：

1. 从 `excalibur-backports` 升级 Mesa 套件（26.1.x）。
2. `/etc/environment` 写入 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`。
3. overlay 提供 layer 与启动器。

## 已知坑

- 别从 Debian **sid** 装 Mesa：会连带 glibc 2.41→2.43，等于半系统升级。
  用 `excalibur-backports`。
- 写 Vulkan layer 时 `pfnGetDeviceProcAddr` 不能一律返回 NULL，
  否则应用调到空指针（`SIGSEGV pc=0`）。应设为 NULL 让 loader 处理。
- 隐式层 manifest **必须**带 `disable_environment`（本仓库用
  `DISABLE_Z96A_CONFORMANCE_LAYER=1`）。缺少时新版 loader 会直接跳过该层并打印
  `doesn't contain required layer object disable_environment`，conformance 仍是
  `0.0.0.0`。`vulkaninfo --summary` 应能看到该层且 Mali 的
  `conformanceVersion = 1.3.0.0`。
- `MESA_VK_VERSION_OVERRIDE=1.3.354` 只改上报的 apiVersion，不改 conformance，
  单靠它不足以让 wgpu 接受 PanVK。
