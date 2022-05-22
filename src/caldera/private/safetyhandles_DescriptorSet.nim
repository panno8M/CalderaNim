import std/importutils
import vulkan
import ./safetyhandles {.all.}
import ./safetyhandles_DescriptorPool
privateAccess Uniq
privateAccess Weak
privateAccess Pac

{.push discardable, inline.}
proc destroy*(handle: var Pac[DescriptorSet]) = impl_destroy(handle):
  template device: Device = handle.castPacParent(DescriptorPool).castParent(Device)
  template descriptorPool: DescriptorPool = handle.castParent(DescriptorPool)
  discard freeDescriptorSets(device, descriptorPool, 1, unsafeAddr handle.mHandle)
proc destroy*[I](handle: var Pac[array[I,DescriptorSet]]) = impl_destroy(handle):
  template device: Device = handle.castPacParent(DescriptorPool).castParent(Device)
  template descriptorPool: DescriptorPool = handle.castParent(DescriptorPool)
  discard freeDescriptorSets(device, descriptorPool, handle.mHandle.len.uint32, unsafeAddr handle.mHandle[0])

proc createDescriptorSet*(parent: Weak[DescriptorPool]; handle: var Uniq[DescriptorSet]; layout: Weak[DescriptorSetLayout]): Result = parent.impl_create(handle):
  var createInfo = DescriptorSetAllocateInfo{
    descriptorPool: parent[],
    descriptorSetCount: 1,
    pSetLayouts: unsafeAddr layout[],
    }
  parent.device[].allocateDescriptorSets addr createInfo, addr handle.mrPac.mHandle
template create*(parent: Weak[DescriptorPool]; handle: var Uniq[DescriptorSet]; layout: Weak[DescriptorSetLayout]): Result = parent.createDescriptorSet handle, layout
proc createDescriptorSets*[I: static int](parent: Weak[DescriptorPool]; handle: var Uniq[array[I, DescriptorSet]]; layout: Weak[array[I, DescriptorSetLayout]]): Result = parent.impl_create(handle):
  var createInfo = DescriptorSetAllocateInfo{
    descriptorPool: parent[],
    descriptorSetCount: uint32 I,
    pSetLayouts: unsafeAddr layout.mrPac.mHandle[0],
    }
  parent.device[].allocateDescriptorSets addr createInfo, addr handle.mrPac.mHandle[0]
template create*[I](parent: Weak[DescriptorPool]; handle: var Uniq[array[I, DescriptorSet]]; layout: Weak[array[I, DescriptorSetLayout]]): Result = parent.createDescriptorSets handle, layout

func descriptorPool*(handle: Weak[RenderPass]): Weak[DescriptorPool] = handle.getParentAs typeof result
template parent*(handle: Weak[RenderPass]): Weak[DescriptorPool] = handle.descriptorPool
{.pop.} # discardable, inline