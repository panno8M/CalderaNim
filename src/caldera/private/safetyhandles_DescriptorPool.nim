import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Pac

{.push discardable, inline.}
proc destroy*(handle: var Pac[DescriptorPool]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyDescriptorPool device, handle.mHandle

proc createDescriptorPool*(parent: Weak[Device]; handle: var Uniq[DescriptorPool]; createInfo: DescriptorPoolCreateInfo): Result = parent.impl_create(handle):
  parent[].createDescriptorPool unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[DescriptorPool]; createInfo: DescriptorPoolCreateInfo): Result = parent.createDescriptorPool handle, createInfo

func device*(handle: Weak[DescriptorPool]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[DescriptorPool]): Weak[Device] = handle.device
{.pop.} # discardable, inline