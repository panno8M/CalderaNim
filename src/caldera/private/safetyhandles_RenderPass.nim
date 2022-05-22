import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Pac

{.push discardable, inline.}
proc destroy*(handle: var Pac[RenderPass]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyRenderPass device, handle.mHandle

proc createRenderPass*(parent: Weak[Device]; handle: var Uniq[RenderPass]; createInfo: RenderPassCreateInfo): Result = parent.impl_create(handle):
  parent[].createRenderPass unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[RenderPass]; createInfo: RenderPassCreateInfo): Result = parent.createRenderPass handle, createInfo

func device*(handle: Weak[RenderPass]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[RenderPass]): Weak[Device] = handle.device
{.pop.} # discardable, inline