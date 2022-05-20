import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[ShaderModule]) = impl_destroy(handle):
  template device: Device = handle.castParent(Device)
  destroyShaderModule device, handle.mHandle

proc createShaderModule*(parent: Weak[Device]; handle: var Uniq[ShaderModule]; createInfo: ShaderModuleCreateInfo): Result = parent.impl_create(handle):
  parent[].createShaderModule unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Device]; handle: var Uniq[ShaderModule]; createInfo: ShaderModuleCreateInfo): Result = parent.createShaderModule handle, createInfo

func device*(handle: Weak[ShaderModule]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[ShaderModule]): Weak[Device] = handle.device
{.pop.} # discardable, inline