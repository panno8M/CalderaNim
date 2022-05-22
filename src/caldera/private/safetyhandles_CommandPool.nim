import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Pac

{.push discardable, inline.}
proc destroy*(handle: var Pac[CommandPool]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyCommandPool device, handle.mHandle

proc createCommandPool*(parent: Weak[Device]; handle: var Uniq[CommandPool]; createInfo: CommandPoolCreateInfo): Result = parent.impl_create(handle):
  parent[].createCommandPool unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[CommandPool]; createInfo: CommandPoolCreateInfo): Result = parent.createCommandPool handle, createInfo

func device*(handle: Weak[CommandPool]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[CommandPool]): Weak[Device] = handle.device
{.pop.} # discardable, inline