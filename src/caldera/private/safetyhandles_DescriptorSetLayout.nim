import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[DescriptorSetLayout]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyDescriptorSetLayout device, handle.mHandle

proc createDescriptorSetLayout*(parent: Weak[Device]; handle: var Uniq[DescriptorSetLayout]; createInfo: DescriptorSetLayoutCreateInfo): Result = parent.impl_create(handle):
  parent[].createDescriptorSetLayout unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[DescriptorSetLayout]; createInfo: DescriptorSetLayoutCreateInfo): Result = parent.createDescriptorSetLayout handle, createInfo

func device*(handle: Weak[DescriptorSetLayout]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[DescriptorSetLayout]): Weak[Device] = handle.device
{.pop.} # discardable, inline