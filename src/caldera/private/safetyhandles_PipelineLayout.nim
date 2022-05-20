import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[PipelineLayout]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyPipelineLayout dEvice, handle.mHandle

proc createPipelineLayout*(parent: Weak[Device]; handle: var Uniq[PipelineLayout]; createInfo: PipelineLayoutCreateInfo): Result = parent.impl_create(handle):
  parent[].createPipelineLayout unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[PipelineLayout]; createInfo: PipelineLayoutCreateInfo): Result = parent.createPipelineLayout handle, createInfo

func device*(handle: Weak[PipelineLayout]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[PipelineLayout]): Weak[Device] = handle.device
{.pop.} # discardable, inline