import std/macros {.all.}
import vulkan
import vulkan/objects/tools
import queuespecifiedhandles_basic

import ./safetyhandles {.all.}

type
  ClCommandBuffer*[QF: static QueueFlags; LV: static CommandBufferLevel] = distinct CommandBuffer

type
  ClCommandBufferCreateInfo* = object
    sType* {.constant: (StructureType.commandBufferAllocateInfo).}: StructureType
    pNext* {.optional.}: pointer

proc destroy*[QF,LV](handle: var Heap[ClCommandBuffer[QF,LV]]) = impl_destroy(handle):
  template device: Device = handle
    .castHeapParent(ClCommandPool[QF])
    .castHeapParent(QueueFamily[QF])
    .castParent(Device)
  freeCommandBuffers device, handle.castParent(CommandPool), 1, cast[ptr CommandBuffer](unsafeAddr handle.mHandle)
proc destroy*[QF,LV](handle: var Heap[seq[ClCommandBuffer[QF,LV]]]) = impl_destroy(handle):
  template device: Device = handle
    .castHeapParent(ClCommandPool[QF])
    .castHeapParent(QueueFamily[QF])
    .castParent(Device)
  freeCommandBuffers device, handle.castParent(CommandPool), handle.mHandle.len.uint32, cast[ptr CommandBuffer](unsafeAddr handle.mHandle[0])
func commandPool*[QF,LV](handle: Weak[ClCommandBuffer[QF,LV]]): Weak[ClCommandPool[QF]] = handle.getParentAs typeof result
template parent*[QF,LV](handle: Weak[ClCommandBuffer[QF,LV]]): Weak[ClCommandPool[QF]] = handle.commandPool

{.push discardable.}
proc createCommandBuffer*[QF, LV](parent: Weak[ClCommandPool[QF]]; handle: var Uniq[ClCommandBuffer[QF, LV]]; createInfo: ClCommandBufferCreateInfo): Result = parent.impl_create(handle):
  var CI: CommandBufferAllocateInfo
  copyMem addr CI, unsafeAddr createInfo, sizeof ClCommandBufferCreateInfo
  CI.commandPool = parent[].CommandPool
  CI.level = LV
  CI.commandBufferCount = 1
  parent.queueFamily.device[].allocateCommandBuffers(addr CI, cast[ptr CommandBuffer](addr handle.mrHeap.mHandle))
proc createCommandBuffers*[QF, LV](parent: Weak[ClCommandPool[QF]]; handle: var Uniq[seq[ClCommandBuffer[QF, LV]]]; createInfo: ClCommandBufferCreateInfo): Result = parent.impl_create(handle):
  var CI: CommandBufferAllocateInfo
  copyMem addr CI, unsafeAddr createInfo, sizeof ClCommandBufferCreateInfo
  CI.commandPool = parent[].CommandPool
  CI.level = LV
  CI.commandBufferCount = handle.mrHeap.mHandle.len.uint32
  parent.queueFamily.device[].allocateCommandBuffers(addr CI, cast[ptr CommandBuffer](addr handle.mrHeap.mHandle[0]))
template create*[QF,LV](parent: Weak[ClCommandPool[QF]]; handle: var Uniq[ClCommandBuffer[QF,LV]]; createInfo: ClCommandBufferCreateInfo): Result =
  createCommandBuffer(parent, handle, createInfo)
template create*[QF,LV](parent: Weak[ClCommandPool[QF]]; handle: var Uniq[seq[ClCommandBuffer[QF,LV]]]; createInfo: ClCommandBufferCreateInfo): Result =
  createCommandBuffers(parent, handle, createInfo)
template downcast*[QF,LV](clCommandBuffer: ClCommandBuffer[QF,LV]): CommandBuffer =
  cast[ptr CommandBuffer](unsafeAddr clCommandBuffer)[]

# Command Recording
macro checkQueueFlagsMismatch(Proc: proc; queueFlags: QueueFlags): untyped =
  # hint vulkan.cmdCopyBuffer.getCustomPragmaVal(queues).repr
  # hint pq.repr
  let reqqueues = Proc.getImpl.pragma.findChild(it.len > 1 and it[0].eqIdent("queues"))[1]
  quote do:
    when (`reqqueues` * `queueFlags`).len == 0:
      {.error: "To execute the command, the CommandBuffer needs to include any of " & $pq.}
macro checkLevelMismatch(Proc: proc; level: CommandBufferLevel) =
  let reqlvl = Proc.getImpl.pragma.findChild(it.len > 1 and it[0].eqIdent("cmdbufferlevel"))[1]
  quote do:
    when `level` notin `reqlvl`:
      {.error: "To execute the command, the level of CommandBuffer must be " & $Proc.getCustomPragmaVal(cmdbufferlevel).}

proc begin*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV]; beginInfo: CommandBufferBeginInfo): Result =
  beginCommandBuffer(downcast(commandBuffer), unsafeaddr beginInfo)

proc `end`*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];): Result =
  endCommandBuffer(downcast(commandBuffer))

proc cmdBarrier*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
      srcStageMask = default(PipelineStageFlags);
      dstStageMask = default(PipelineStageFlags);
      dependencyFlags = default(DependencyFlags);
      memoryBarrierCount = default(uint32);
      pMemoryBarriers {.length: memoryBarrierCount.}: arrPtr[MemoryBarrier];
      bufferMemoryBarrierCount = default(uint32);
      pBufferMemoryBarriers {.length: bufferMemoryBarrierCount.}: arrPtr[BufferMemoryBarrier];
      imageMemoryBarrierCount = default(uint32);
      pImageMemoryBarriers {.length: imageMemoryBarrierCount.}: arrPtr[ImageMemoryBarrier];
    ): lent typeof commandBuffer =
  commandBuffer.downcast.cmdPipelineBarrier(srcStageMask, dstStageMask, dependencyFlags, memoryBarrierCount, pMemoryBarriers, bufferMemoryBarrierCount, pBufferMemoryBarriers, imageMemoryBarrierCount, pImageMemoryBarriers)
  return commandBuffer

proc cmdBindDescriptorSets*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
      pipelineBindPoint: PipelineBindPoint;
      layout: PipelineLayout;
      firstSet: uint32;
      descriptorSetCount: uint32;
      pDescriptorSets {.length: descriptorSetCount.}: arrPtr[DescriptorSet];
      dynamicOffsetCount = default(uint32);
      pDynamicOffsets {.length: dynamicOffsetCount.}: arrPtr[uint32];
    ): lent typeof commandBuffer =
  checkQueueFlagsMismatch vulkan.cmdBindDescriptorSets, QF
  checkLevelMismatch vulkan.cmdBindDescriptorSets, LV
  commandBuffer.downcast.cmdBindDescriptorSets(pipelineBindPoint, layout, firstSet, descriptorSetCount, pDescriptorSets, dynamicOffsetCount, pDynamicOffsets)
  return commandBuffer

proc cmdBindPipeline*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
      pipelineBindPoint: PipelineBindPoint;
      pipeline: Pipeline;
    ): lent typeof commandBuffer =
  checkQueueFlagsMismatch vulkan.cmdBindPipeline, QF
  checkLevelMismatch vulkan.cmdBindPipeline, LV
  commandBuffer.downcast.cmdBindPipeline(pipelineBindPoint, pipeline)
  return commandBuffer

proc cmdBindIndexBuffer*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
      buffer: Buffer;
      offset: DeviceSize;
      indexType: IndexType;
    ): lent typeof commandBuffer =
  checkQueueFlagsMismatch vulkan.cmdBindIndexBuffer, QF
  checkLevelMismatch vulkan.cmdBindIndexBuffer, LV
  commandBuffer.downcast.cmdBindIndexBuffer(buffer, offset, indexType)
  return commandBuffer

proc cmdBindVertexBuffers*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
      firstBinding: uint32;
      bindingCount: uint32;
      pBuffers {.length: bindingCount.}: arrPtr[Buffer];
      pOffsets {.length: bindingCount.}: arrPtr[DeviceSize];
    ): lent typeof commandBuffer =
  checkQueueFlagsMismatch vulkan.cmdBindVertexBuffers, QF
  checkLevelMismatch vulkan.cmdBindVertexBuffers, LV
  commandBuffer.downcast.cmdBindVertexBuffers(firstBinding, bindingCount, pBuffers, pOffsets)
  return commandBuffer

proc cmdDrawIndexed*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
      indexCount: uint32;
      instanceCount: uint32;
      firstIndex: uint32;
      vertexOffset: int32;
      firstInstance: uint32;
    ): lent typeof commandBuffer =
  checkQueueFlagsMismatch vulkan.cmdDrawIndexed, QF
  checkLevelMismatch vulkan.cmdDrawIndexed, LV
  commandBuffer.downcast.cmdDrawIndexed(indexCount, instanceCount, firstIndex, vertexOffset, firstInstance)
  return commandBuffer

proc cmdCopyBuffer*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
      srcBuffer: Buffer;
      dstBuffer: Buffer;
      regionCount: uint32;
      pRegions {.length: regionCount.}: arrPtr[BufferCopy];
    ): lent typeof commandBuffer =
  checkQueueFlagsMismatch vulkan.cmdCopyBuffer, QF
  checkLevelMismatch vulkan.cmdCopyBuffer, LV
  commandBuffer.downcast.cmdCopyBuffer(srcBuffer, dstBuffer, regionCount, pRegions)
  return commandBuffer

proc cmdBeginRenderPass*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
      beginInfo: RenderPassBeginInfo;
      contents: SubpassContents;
    ): lent typeof commandBuffer =
  checkQueueFlagsMismatch vulkan.cmdBeginRenderPass, QF
  checkLevelMismatch vulkan.cmdBeginRenderPass, LV
  commandBuffer.downcast.cmdBeginRenderPass(unsafeaddr beginInfo, contents)
  return commandBuffer

proc cmdEndRenderPass*[QF,LV](commandBuffer: ClCommandBuffer[QF,LV];
    ): lent typeof commandBuffer =
  checkQueueFlagsMismatch vulkan.cmdEndRenderPass, QF
  checkLevelMismatch vulkan.cmdEndRenderPass, LV
  commandBuffer.downcast.cmdEndRenderPass()
  return commandBuffer
{.pop.} # discardable