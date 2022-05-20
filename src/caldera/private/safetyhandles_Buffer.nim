import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[Buffer]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyBuffer device, handle.mHandle

proc createBuffer*(parent: Weak[Device]; handle: var Uniq[Buffer]; createInfo: BufferCreateInfo): Result = parent.impl_create(handle):
  parent[].createBuffer unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[Buffer]; createInfo: BufferCreateInfo): Result = parent.createBuffer handle, createInfo

func device*(handle: Weak[Buffer]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[Buffer]): Weak[Device] = handle.device
{.pop.} # discardable, inline