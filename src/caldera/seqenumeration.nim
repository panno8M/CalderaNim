import vulkan
import vulkan/commands/extensions {.all.}

{.push, discardable.}
proc enumeratePhysicalDevices*(instance: Instance; ret: var seq[PhysicalDevice]): Result =
  var cnt: uint32
  result = instance.enumeratePhysicalDevices(addr cnt)
  if result != Result.success or cnt == 0: return
  ret.setLen(cnt)
  return instance.enumeratePhysicalDevices(addr cnt, addr ret[0])
proc enumeratePhysicalDevices*[I](instance: Instance; ret: var array[I, PhysicalDevice]; retcnt: var uint32): Result =
  retcnt = ret.len
  return instance.enumeratePhysicalDevices(addr retcnt, addr ret[0])
template enumeratePhysicalDevices*[I](instance: Instance; ret: var array[I, PhysicalDevice]): Result =
  var cnt: uint32
  enumeratePhysicalDevices(instance, ret, cnt)
proc enumeratePhysicalDevices*(instance: Instance; ret: var PhysicalDevice): Result =
  var cnt: uint32 = 1
  return instance.enumeratePhysicalDevices(addr cnt, addr ret)
template enumerate*   (instance: Instance; ret: var   seq[   PhysicalDevice]                    ): Result = enumeratePhysicalDevices(instance, ret        )
template enumerate*[I](instance: Instance; ret: var array[I, PhysicalDevice]; retcnt: var uint32): Result = enumeratePhysicalDevices(instance, ret, retcnt)
template enumerate*[I](instance: Instance; ret: var array[I, PhysicalDevice]                    ): Result = enumeratePhysicalDevices(instance, ret        )
template enumerate*   (instance: Instance; ret: var          PhysicalDevice                     ): Result = enumeratePhysicalDevices(instance, ret        )

proc enumerateInstanceExtensionProperties*(ret: var seq[ExtensionProperties]; layerName = default(cstring)): Result =
  var cnt: uint32
  result = enumerateInstanceExtensionProperties(layerName, addr cnt)
  if result != Result.success or cnt == 0: return
  ret.setLen(cnt)
  return enumerateInstanceExtensionProperties(layerName, addr cnt, addr ret[0])
template enumerate*(ret: var seq[ExtensionProperties]; layerName = default(cstring)): Result = enumerateInstanceExtensionProperties(ret, layerName)

proc enumerateDeviceExtensionProperties*(physicalDevice: PhysicalDevice; ret: var seq[ExtensionProperties]; layerName = default(cstring)): Result =
  var cnt: uint32
  result = physicalDevice.enumerateDeviceExtensionProperties(layerName, addr cnt)
  if result != Result.success or cnt == 0: return
  ret.setLen(cnt)
  return physicalDevice.enumerateDeviceExtensionProperties(layerName, addr cnt, addr ret[0])
template enumerate*(physicalDevice: PhysicalDevice; ret: var seq[ExtensionProperties]; layerName = default(cstring)): Result = enumerateDeviceExtensionProperties(physicalDevice, ret, layerName)

proc enumerateInstanceLayerProperties*(ret: var seq[LayerProperties]): Result =
  var cnt: uint32
  result = enumerateInstanceLayerProperties(addr cnt)
  if result != Result.success or cnt == 0: return
  ret.setLen(cnt)
  return enumerateInstanceLayerProperties(addr cnt, addr ret[0])
template enumerate*(ret: var seq[LayerProperties]): Result = enumerateInstanceLayerProperties(ret)

proc enumerateDeviceLayerProperties*(physicalDevice: PhysicalDevice; ret: var seq[LayerProperties]): Result =
  var cnt: uint32
  result = physicalDevice.enumerateDeviceLayerProperties(addr cnt)
  if result != Result.success or cnt == 0: return
  ret.setLen(cnt)
  return physicalDevice.enumerateDeviceLayerProperties(addr cnt, addr ret[0])
template enumerate*(physicalDevice: PhysicalDevice; ret: var seq[LayerProperties]): Result = enumerateDeviceLayerProperties(physicalDevice, ret)

proc getPhysicalDeviceQueueFamilyProperties*(physicalDevice: PhysicalDevice; ret: var seq[QueueFamilyProperties]): Result =
  var cnt: uint32
  physicalDevice.getPhysicalDeviceQueueFamilyProperties(addr cnt)
  if cnt == 0: return
  ret.setLen(cnt)
  physicalDevice.getPhysicalDeviceQueueFamilyProperties(addr cnt, addr ret[0])
template get*(physicalDevice: PhysicalDevice; ret: var seq[QueueFamilyProperties]): Result = getPhysicalDeviceQueueFamilyProperties(physicalDevice, ret)

proc getPhysicalDeviceSurfaceFormatsKHR*(physicalDevice: PhysicalDevice; ret: var seq[SurfaceFormatKHR]; surface: SurfaceKHR): Result =
  var cnt: uint32
  result = physicalDevice.getPhysicalDeviceSurfaceFormatsKHR(surface, addr cnt)
  if result != Result.success or cnt == 0: return
  ret.setLen(cnt)
  return physicalDevice.getPhysicalDeviceSurfaceFormatsKHR(surface, addr cnt, addr ret[0])
template get*(physicalDevice: PhysicalDevice; ret: var seq[SurfaceFormatKHR]; surface: SurfaceKHR): Result = getPhysicalDeviceSurfaceFormatsKHR(physicalDevice, ret, surface)

proc getPhysicalDeviceSurfacePresentModesKHR*(physicalDevice: PhysicalDevice; ret: var seq[PresentModeKHR]; surface: SurfaceKHR): Result =
  var cnt: uint32
  result = physicalDevice.getPhysicalDeviceSurfacePresentModesKHR(surface, addr cnt)
  if result != Result.success or cnt == 0: return
  ret.setLen(cnt)
  return physicalDevice.getPhysicalDeviceSurfacePresentModesKHR(surface, addr cnt, addr ret[0])
template get*(physicalDevice: PhysicalDevice; ret: var seq[PresentModeKHR]; surface: SurfaceKHR): Result = getPhysicalDeviceSurfacePresentModesKHR(physicalDevice, ret, surface)

proc getSwapchainImagesKHR*(device: Device; ret: var seq[Image]; swapchain: SwapchainKHR): Result =
  if getSwapchainImagesKHR_RAW == nil:
    device.loadCommand vulkan.getSwapchainImagesKHR
  var cnt: uint32
  result = device.getSwapchainImagesKHR(swapchain, addr cnt)
  if result != Result.success or cnt == 0: return
  ret.setLen(cnt)
  return device.getSwapchainImagesKHR(swapchain, addr cnt, addr ret[0])
template get*(device: Device; ret: var seq[Image]; swapchain: SwapchainKHR): Result = getSwapchainImagesKHR(device, ret, swapchain)
{.pop.}