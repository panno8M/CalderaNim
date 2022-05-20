import vulkan

type ClCommandBuffer*[QF: static QueueFlags] = distinct pointer

proc abstract*(commandBuffer: ClCommandBuffer): lent CommandBuffer =
  cast[ptr CommandBuffer](unsafeAddr commandBuffer)[]
proc abstract*(commandBuffer: var ClCommandBuffer): var CommandBuffer =
  cast[ptr CommandBuffer](unsafeAddr commandBuffer)[]
proc abstract*(commandBuffer: ptr ClCommandBuffer): ptr CommandBuffer =
  cast[ptr CommandBuffer](commandBuffer)

proc allocateCommandBuffers*[QF: static QueueFlags](device: Device; allocInfo: ptr CommandBufferAllocateInfo; commandBuffer: arrPtr[ClCommandBuffer[QF]]): Result =
  allocateCommandBuffers(device, allocInfo, commandBuffer.abstract)
