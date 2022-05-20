import std/options
import std/asyncdispatch
import vulkan
import vulkan/objects/tools

import ./safetyhandles {.all.}

type
  QueueFamily*[QF: static QueueFlags] = object
    index*: Option[uint32]
  ClCommandPool*[QF: static QueueFlags] = distinct CommandPool
  ClQueue*[QF: static QueueFlags] = distinct Queue

type
  ClCommandPoolCreateInfo* = object
    sType* {.constant: (StructureType.commandPoolCreateInfo).}: StructureType
    pNext* {.optional.}: pointer
    flags* {.optional.}: CommandPoolCreateFlags # Command pool creation flags

proc destroy*[QF](handle: var Heap[QueueFamily[QF]]) = impl_destroy(handle):
  discard
func device*[QF](handle: Weak[QueueFamily[QF]]): Weak[Device] = handle.getParentAs typeof result
template parent*[QF](handle: Weak[QueueFamily[QF]]): Weak[Device] = handle.device

proc destroy*[QF](handle: var Heap[ClCommandPool[QF]]) = impl_destroy(handle):
  destroyCommandPool handle.castHeapParent(QueueFamily[QF]).castParent(Device), handle.mHandle.CommandPool
func queueFamily*[QF](handle: Weak[ClCommandPool[QF]]): Weak[QueueFamily[QF]] = handle.getParentAs typeof result
template parent*[QF](handle: Weak[ClCommandPool[QF]]): Weak[QueueFamily[QF]] = handle.queueFamily


{.push discardable, inline.}
proc assembleQueueFamily*[QF: static QueueFlags](parent: Weak[Device]; handle: var Uniq[QueueFamily[QF]]; index: uint32): Result {.discardable.} = parent.impl_create(handle):
  handle.mrHeap.mHandle.index = some index
  success

proc createCommandPool*[QF](parent: Weak[QueueFamily[QF]]; handle: var Uniq[ClCommandPool[QF]]; createInfo: ClCommandPoolCreateInfo): Result = parent.impl_create(handle):
  var CI: CommandPoolCreateInfo
  copyMem addr CI, unsafeAddr createInfo, sizeof ClCommandPoolCreateInfo
  CI.queueFamilyIndex = parent[].index.get
  parent.device[].createCommandPool(addr CI, nil, cast[ptr CommandPool](addr handle.mrHeap.mHandle))
template create*[QF](parent: Weak[QueueFamily[QF]]; handle: var Uniq[ClCommandPool[QF]]; createInfo: ClCommandPoolCreateInfo): Result =
  createCommandPool(parent, handle, createInfo)
{.pop.} # discardabl, inlinee

proc getQueue*[QF1, QF2](qfamily: Weak[QueueFamily[QF1]]; queue: var ClQueue[QF2]; queueIdx: uint32 = 0) =
  when QF2 notin QF1:
    {.error: &"the QueueFlags of target queue must be contained in {QF1} of queueFamily".}
  qfamily.device[].getDeviceQueue(qfamily[].index.get, queueIdx, cast[ptr Queue](addr queue))
template get*[QF1, QF2](qfamily: Weak[QueueFamily[QF1]]; queue: var ClQueue[QF2]; queueIdx: uint32 = 0) =
  qfamily.getQueue(queue, queueIdx)
# proc `[]`*[QF](qFamily: Weak[QueueFamily[QF]]; i: uint32): Queue =
#   qFamily.getQueue(result, i)


{.push discardable, inline.}
proc queueWaitIdle*[QF](queue: ClQueue[QF]): Result =
  queueWaitIdle(cast[Queue](queue))
template waitIdle*[QF](queue: ClQueue[QF]): Result =
  queueWaitIdle queue

proc queueSubmit*[QF](queue: ClQueue[QF]; submitCount: uint32; pSubmits: ptr SubmitInfo; fence = default(Fence)): Result =
  cast[Queue](queue).queueSubmit(submitCount, pSubmits, fence)
template submit*[QF](queue: ClQueue[QF]; submitCount: uint32; pSubmits: ptr SubmitInfo; fence = default(Fence)): Result =
  queue.queueSubmit(submitCount, pSubmits, fence)

proc queueSubmit*[QF](queue: ClQueue[QF]; submits: openArray[SubmitInfo]; fence = default(Fence)): Result =
  queue.queueSubmit(submits.len.uint32, unsafeAddr submits[0], fence)
template submit*[QF](queue: ClQueue[QF]; submits: openArray[SubmitInfo]; fence = default(Fence)): Result =
  queue.queueSubmit(submits, fence)

proc queueSubmit*[QF](queue: ClQueue[QF]; submits: SubmitInfo; fence = default(Fence)): Result =
  queue.queueSubmit(1, unsafeAddr submits, fence)
template submit*[QF](queue: ClQueue[QF]; submits: SubmitInfo; fence = default(Fence)): Result =
  queue.queueSubmit(submits, fence)

proc queuePresentKHR*[QF](queue: ClQueue[QF]; presentInfo: PresentInfoKHR): Result =
  cast[Queue](queue).queuePresentKHR(unsafeAddr presentInfo)
template present*[QF](queue: ClQueue[QF]; presentInfo: PresentInfoKHR): Result =
  queue.queuePresentKHR(presentInfo)

{.pop.} # Ddiscardable, inline