import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[ImageView]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyImageView device, handle.mHandle

proc createImageView*(parent: Weak[Device]; handle: var Uniq[ImageView]; createInfo: ImageViewCreateInfo): Result = parent.impl_create(handle):
  parent[].createImageView unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[ImageView]; createInfo: ImageViewCreateInfo): Result = parent.createImageView handle, createInfo

func device*(handle: Weak[ImageView]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[ImageView]): Weak[Device] = handle.device
{.pop.} # discardable, inline