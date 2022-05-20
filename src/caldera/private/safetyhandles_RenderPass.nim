import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[RenderPass]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyRenderPass device, handle.mHandle

proc createRenderPass*(parent: Weak[Device]; handle: var Uniq[RenderPass]; createInfo: RenderPassCreateInfo): Result = parent.impl_create(handle):
  parent[].createRenderPass unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[RenderPass]; createInfo: RenderPassCreateInfo): Result = parent.createRenderPass handle, createInfo

func device*(handle: Weak[RenderPass]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[RenderPass]): Weak[Device] = handle.device
{.pop.} # discardable, inline