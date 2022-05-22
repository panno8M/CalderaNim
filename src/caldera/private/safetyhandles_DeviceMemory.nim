import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Pac

{.push discardable, inline.}
proc destroy*(handle: var Pac[DeviceMemory]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  freeMemory device, handle.mHandle

proc allocateMemory*(parent: Weak[Device]; handle: var Uniq[DeviceMemory]; allocateInfo: MemoryAllocateInfo): Result = parent.impl_create(handle):
  parent[].allocateMemory unsafeAddr allocateInfo, nil, addr handle.mrPac.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[DeviceMemory]; allocateInfo: MemoryAllocateInfo): Result = parent.allocateMemory handle, allocateInfo

func device*(handle: Weak[DeviceMemory]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[DeviceMemory]): Weak[Device] = handle.device

proc mapMemory*(memory: Weak[DeviceMemory];
      offset: DeviceSize;
      size: DeviceSize;
      flags = default(MemoryMapFlags);
      ppData: ptr pointer;
    ): Result =
  mapMemory(memory.device[], memory[], offset, size, flags, ppData)
template map*(memory: Weak[DeviceMemory]; offset: DeviceSize; size: DeviceSize; flags = default(MemoryMapFlags); ppData: ptr pointer;): Result =
  mapMemory(memory, offset, size, flags, ppData)

proc unmapMemory*(memory: Weak[DeviceMemory]) =
  unmapMemory(memory.device[], memory[])
template unmap*(memory: Weak[DeviceMemory]) =
  unmapMemory(memory)
{.pop.} # discardable, inline