import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[Pipeline]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyPipeline device, handle.mHandle

proc createGraphicsPipeline*(parent: Weak[Device]; handle: var Uniq[Pipeline]; createInfo: GraphicsPipelineCreateInfo): Result = parent.impl_create(handle):
  parent[].createGraphicsPipelines PipelineCache.none, 1, unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[Pipeline]; createInfo: GraphicsPipelineCreateInfo): Result = parent.createGraphicsPipeline handle, createInfo
{.pop.} # discardable, inline