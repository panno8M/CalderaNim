import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Pac

{.push discardable, inline.}
proc destroy*(handle: var Pac[FrameBuffer]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyFrameBuffer device, handle.mHandle

proc createFrameBuffer*(parent: Weak[Device]; handle: var Uniq[FrameBuffer]; createInfo: FrameBufferCreateInfo): Result = parent.impl_create(handle):
  parent[].createFramebuffer unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[FrameBuffer]; createInfo: FrameBufferCreateInfo): Result = parent.createFrameBuffer handle, createInfo

func device*(handle: Weak[FrameBuffer]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[FrameBuffer]): Weak[Device] = handle.device
{.pop.} # discardable, inline