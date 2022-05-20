import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[Semaphore]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroySemaphore device, handle.mHandle

proc createSemaphore*(parent: Weak[Device]; handle: var Uniq[Semaphore]; createInfo: SemaphoreCreateInfo): Result = parent.impl_create(handle):
  parent[].createSemaphore unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[Semaphore]; createInfo: SemaphoreCreateInfo): Result = createSemaphore(parent, handle, createInfo)

func device*(handle: Weak[Semaphore]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[Semaphore]): Weak[Device] = handle.device
{.pop.} # discardable, inline