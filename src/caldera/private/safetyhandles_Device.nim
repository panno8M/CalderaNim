import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[Device]) = impl_destroy(handle):
  destroyDevice handle.mhandle
proc createDevice*(parent: PhysicalDevice; handle: var Uniq[Device]; createInfo: DeviceCreateInfo): Result = impl_create(handle):
  handle.mrHeap.mpParent = cast[pointer](parent)
  parent.createDevice unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: PhysicalDevice; handle: var Uniq[Device]; createInfo: DeviceCreateInfo): Result = parent.createDevice handle, createInfo

func physicalDevice*(handle: Weak[Device]): PhysicalDevice = cast[PhysicalDevice](handle.mrHeap.mpParent)
template parent*(handle: Weak[Device]): PhysicalDevice = handle.physicalDevice
{.pop.} # discardable, inline