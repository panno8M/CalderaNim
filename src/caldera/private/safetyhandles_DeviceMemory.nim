import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[DeviceMemory]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  freeMemory device, handle.mHandle

proc allocateMemory*(parent: Weak[Device]; handle: var Uniq[DeviceMemory]; allocateInfo: MemoryAllocateInfo): Result = parent.impl_create(handle):
  parent[].allocateMemory unsafeAddr allocateInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[DeviceMemory]; allocateInfo: MemoryAllocateInfo): Result = parent.allocateMemory handle, allocateInfo

func device*(handle: Weak[DeviceMemory]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[DeviceMemory]): Weak[Device] = handle.device
{.pop.} # discardable, inline