/*
 * Minimal Vulkan layer: force VkPhysicalDeviceDriverProperties::conformanceVersion
 * to 1.3.0.0 on PanVK/Mali-G52, so wgpu does not hide the adapter as
 * "not Vulkan compliant".
 *
 * Mesa's panvk reports conformanceVersion {0,0,0,0} for Bifrost (PAN_ARCH < 10)
 * even on main, so wgpu (29/30) skips the adapter unless the application passes
 * ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER. This layer is the application-agnostic
 * fix.
 */
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include <string.h>
#include <stdio.h>

static PFN_vkGetInstanceProcAddr g_next_gipa = NULL;
static VkInstance g_instance = VK_NULL_HANDLE;
static PFN_GetPhysicalDeviceProcAddr g_next_gpdpa = NULL;
static PFN_vkGetPhysicalDeviceProperties2 g_next_gpd2 = NULL;
static PFN_vkGetPhysicalDeviceProperties2KHR g_next_gpd2khr = NULL;

static void fix_chain(VkPhysicalDeviceProperties2 *props)
{
    VkBaseOutStructure *s = (VkBaseOutStructure *)props->pNext;
    while (s) {
        if (s->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES) {
            VkPhysicalDeviceDriverProperties *d = (VkPhysicalDeviceDriverProperties *)s;
            /* Only lift drivers that report 0.0.0.0; leave conformant ones alone. */
            if (d->conformanceVersion.major == 0) {
                d->conformanceVersion.major = 1;
                d->conformanceVersion.minor = 3;
                d->conformanceVersion.subminor = 0;
                d->conformanceVersion.patch = 0;
            }
        }
        s = s->pNext;
    }
}

static VKAPI_ATTR void VKAPI_CALL wrap_gpd2(VkPhysicalDevice dev,
                                            VkPhysicalDeviceProperties2 *props)
{
    if (!g_next_gpd2 && g_next_gpdpa && g_instance)
        g_next_gpd2 = (PFN_vkGetPhysicalDeviceProperties2)
            g_next_gpdpa(g_instance, "vkGetPhysicalDeviceProperties2");
    if (g_next_gpd2) {
        g_next_gpd2(dev, props);
        fix_chain(props);
    }
}

static VKAPI_ATTR void VKAPI_CALL wrap_gpd2khr(VkPhysicalDevice dev,
                                               VkPhysicalDeviceProperties2 *props)
{
    if (!g_next_gpd2khr && g_next_gpdpa && g_instance)
        g_next_gpd2khr = (PFN_vkGetPhysicalDeviceProperties2KHR)
            g_next_gpdpa(g_instance, "vkGetPhysicalDeviceProperties2KHR");
    if (g_next_gpd2khr) {
        g_next_gpd2khr(dev, props);
        fix_chain(props);
    }
}

static VKAPI_ATTR VkResult VKAPI_CALL wrap_CreateInstance(
    const VkInstanceCreateInfo *pCreateInfo,
    const VkAllocationCallbacks *pAllocator,
    VkInstance *pInstance)
{
    VkLayerInstanceCreateInfo *chain = (VkLayerInstanceCreateInfo *)pCreateInfo->pNext;
    while (chain && !(chain->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO &&
                      chain->function == VK_LAYER_LINK_INFO))
        chain = (VkLayerInstanceCreateInfo *)chain->pNext;

    if (!chain || !chain->u.pLayerInfo)
        return VK_ERROR_INITIALIZATION_FAILED;

    PFN_vkGetInstanceProcAddr next_gipa = chain->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    PFN_GetPhysicalDeviceProcAddr next_gpdpa = chain->u.pLayerInfo->pfnNextGetPhysicalDeviceProcAddr;
    chain->u.pLayerInfo = chain->u.pLayerInfo->pNext;

    PFN_vkCreateInstance next_create =
        (PFN_vkCreateInstance)next_gipa(NULL, "vkCreateInstance");
    if (!next_create)
        return VK_ERROR_INITIALIZATION_FAILED;

    VkResult r = next_create(pCreateInfo, pAllocator, pInstance);
    if (r == VK_SUCCESS) {
        g_next_gipa = next_gipa;
        g_next_gpdpa = next_gpdpa;
        g_instance = *pInstance;
        g_next_gpd2 = NULL;
        g_next_gpd2khr = NULL;
    }
    return r;
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL layer_gipa(VkInstance instance,
                                                    const char *pName);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL layer_gpdpa(VkInstance inst,
                                                     const char *pName);

VKAPI_ATTR __attribute__((visibility("default"))) PFN_vkVoidFunction VKAPI_CALL
layer_gipa(VkInstance instance, const char *pName)
{
    if (strcmp(pName, "vkGetPhysicalDeviceProperties2") == 0)
        return (PFN_vkVoidFunction)wrap_gpd2;
    if (strcmp(pName, "vkGetPhysicalDeviceProperties2KHR") == 0)
        return (PFN_vkVoidFunction)wrap_gpd2khr;
    if (strcmp(pName, "vkCreateInstance") == 0)
        return (PFN_vkVoidFunction)wrap_CreateInstance;
    return g_next_gipa ? g_next_gipa(instance, pName) : NULL;
}

VKAPI_ATTR __attribute__((visibility("default"))) PFN_vkVoidFunction VKAPI_CALL
layer_gdpa(VkDevice device, const char *pName)
{
    (void)device;
    (void)pName;
    return NULL;
}

VKAPI_ATTR __attribute__((visibility("default"))) PFN_vkVoidFunction VKAPI_CALL
layer_gpdpa(VkInstance inst, const char *pName)
{
    if (strcmp(pName, "vkGetPhysicalDeviceProperties2") == 0)
        return (PFN_vkVoidFunction)wrap_gpd2;
    if (strcmp(pName, "vkGetPhysicalDeviceProperties2KHR") == 0)
        return (PFN_vkVoidFunction)wrap_gpd2khr;
    return NULL;
}

VKAPI_ATTR VkResult VKAPI_CALL
vkNegotiateLoaderLayerInterfaceVersion(VkNegotiateLayerInterface *pVersionStruct)
{
    if (pVersionStruct->loaderLayerInterfaceVersion < 2)
        return VK_ERROR_INITIALIZATION_FAILED;

    pVersionStruct->loaderLayerInterfaceVersion = 2;
    pVersionStruct->pfnGetInstanceProcAddr = layer_gipa;
    pVersionStruct->pfnGetDeviceProcAddr = NULL;
    pVersionStruct->pfnGetPhysicalDeviceProcAddr = layer_gpdpa;
    return VK_SUCCESS;
}
