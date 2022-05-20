import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[Instance]) = impl_destroy(handle):
  destroyInstance handle.mHandle

proc createInstance*(handle: var Uniq[Instance]; createInfo: InstanceCreateInfo): Result = impl_create(handle):
  createInstance unsafeAddr(createInfo), nil, addr handle.mrHeap.mHandle
template create*(handle: var Uniq[Instance]; createInfo: InstanceCreateInfo): Result = createInstance handle, createInfo
{.pop.} # discardable, inline