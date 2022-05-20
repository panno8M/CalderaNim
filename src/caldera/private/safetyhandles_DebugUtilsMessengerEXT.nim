import std/importutils
import vulkan
import vulkan/commands/extensions {.all.}
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Heap

{.push discardable, inline.}
proc destroy*(handle: var Heap[DebugUtilsMessengerExt]) = impl_destroy(handle):
  template instance: Instance = handle.castParent(Instance)
  if destroyDebugUtilsMessengerEXT_RAW == nil: instance.loadCommand destroyDebugUtilsMessengerEXT
  destroyDebugUtilsMessengerEXT instance, handle.mHandle

proc createDebugUtilsMessengerEXT*(parent: Weak[Instance]; handle: var Uniq[DebugUtilsMessengerExt]; createInfo: DebugUtilsMessengerCreateInfoEXT): Result = parent.impl_create(handle):
  if createDebugUtilsMessengerEXT_RAW == nil: parent[].loadCommand vulkan.createDebugUtilsMessengerEXT
  parent[].createDebugUtilsMessengerEXT unsafeAddr createInfo, nil, addr handle.mrHeap.mHandle
template create*(parent: Weak[Instance]; handle: var Uniq[DebugUtilsMessengerExt]; createInfo: DebugUtilsMessengerCreateInfoEXT): Result = parent.createDebugUtilsMessengerEXT handle, createInfo

func instance*(handle: Weak[DebugUtilsMessengerEXT]): Weak[Instance] = handle.getParentAs typeof result
template parent*(handle: Weak[DebugUtilsMessengerEXT]): Weak[Instance] = handle.instance
{.pop.} # discardable, inline