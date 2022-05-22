import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Pac

{.push discardable, inline.}
proc destroy*(handle: var Pac[Buffer]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyBuffer device, handle.mHandle

proc createBuffer*(parent: Weak[Device]; handle: var Uniq[Buffer]; createInfo: BufferCreateInfo): Result = parent.impl_create(handle):
  parent[].createBuffer unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[Buffer]; createInfo: BufferCreateInfo): Result = parent.createBuffer handle, createInfo

func device*(handle: Weak[Buffer]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[Buffer]): Weak[Device] = handle.device

proc getBufferMemoryRequirements*(buffer: Weak[Buffer];
      memoryRequirements: var MemoryRequirements;
    ) =
  getBufferMemoryRequirements(buffer.device[], buffer[], addr memoryRequirements)
template get*(buffer: Weak[Buffer]; memoryRequirements: var MemoryRequirements) =
  getBufferMemoryRequirements(buffer, memoryRequirements)
{.pop.} # discardable, inline