import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Pac

import ../seqenumeration
when TraceHook:
  import std/logging
  import std/strformat

{.push discardable, inline.}
proc destroy*(handle: var Pac[SwapchainKHR]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroySwapchainKHR device, handle.mHandle

proc createSwapchainKHR*(parent: Weak[Device]; handle: var Uniq[SwapchainKHR]; createInfo: SwapchainCreateInfoKHR): Result = parent.impl_create(handle):
  parent[].createSwapchainKHR unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[SwapchainKHR]; createInfo: SwapchainCreateInfoKHR): Result = parent.createSwapchainKHR handle, createInfo

func device*(handle: Weak[SwapchainKHR]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[SwapchainKHR]): Weak[Device] = handle.device

proc getSwapchainImagesKHR*(swapchain: Weak[SwapchainKHR]; images: var Weak[seq[Image]]): Result =
  if images.mrPac == nil:
    images.mrPac = new Pac[seq[Image]]
  images.mrPac.mpParent = cast[pointer](swapchain.device.mrPac)
  images.mrPac.mIsAlive = true
  when TraceHook:
    hookLogger.log lvlInfo, &": (manu) GET #{idof(images.mrPac[]):03} : seq[Image]"
  swapchain.device[].getSwapchainImagesKHR(images.mrPac.mHandle, swapchain[])
template get*(swapchain: Weak[SwapchainKHR]; images: var Weak[seq[Image]]): Result = getSwapchainImagesKHR(swapchain, images)
{.pop.} # discardable, inline