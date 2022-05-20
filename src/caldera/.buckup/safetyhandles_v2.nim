import std/macros
import std/strutils

import vulkan
import vulkan/commands/extensions {.all.}
from vulkan/tools/glfw import glfwCreateWindowSurface, GLFWWindow

import ./uniformedhandlectrl

# <Core>
const SafetyHandleHooksActivated* = true
type HandleNotAliveDefect* = object of NilAccessDefect

template memaddr(x): untyped = cast[uint64](unsafeaddr x).toHex
type
  Heap*[HandleType] = object
    mpParent: pointer
    mRawhandle: HandleType
    mWeakcnt: uint8
  Weak*[HandleType] = object
    mpHeap: ptr Heap[HandleType]
  Unique*[HandleType] = object
    mWeak: Weak[HandleType]

proc `=destroy`[T](handle: var Weak[T]) =
  if handle.mpHeap != nil:
    dec handle.mpHeap.mWeakcnt
    if handle.mpHeap.mWeakcnt == 0:
      dealloc handle.mpHeap
proc `=copy`[T](dst: var Weak[T]; src: Weak[T]) =
  if src.mpHeap != nil:
    copymem addr dst, unsafeAddr src, sizeof Weak[T]
    inc dst.mpHeap.mWeakcnt
proc `=destroy`[T](handle: var Unique[T])

proc destroy[T](handle: var Heap[T])

proc `=destroy`[T](handle: var Unique[T]) =
  when defined traceHook:
    echo "# END LIFE: ", T, " @", memaddr handle
  if handle.mWeak.mpHeap != nil:
    if handle.mWeak.mpHeap.mRawhandle.isDestroyable:
      destroy handle.mWeak.mpHeap[]
    `=destroy` handle.mWeak
    when defined traceHook:
      echo "# DONE DESTROY : ", T, " @", memaddr handle


template impl_create(body): Result =
  template HandleType: untyped = typeof(handle).HandleType
  var heap: Heap[HandleType]
  if handle.mWeak.mpHeap == nil:
    handle.mWeak.mpHeap = cast[ptr Heap[HandleType]](alloc sizeof Heap[HandleType])
    handle.mWeak.mpHeap.mWeakcnt = 1
  else:
    if handle.mWeak.mpHeap.mRawhandle.isDestroyable:
      heap = handle.mWeak.mpHeap[]
  body
template impl_create(parent: untyped; body): Result =
  template HandleType: untyped = typeof(handle).HandleType
  var heap: Heap[HandleType]
  if handle.mWeak.mpHeap == nil:
    handle.mWeak.mpHeap = cast[ptr Heap[HandleType]](alloc sizeof Heap[HandleType])
    handle.mWeak.mpHeap.mWeakcnt = 1
  else:
    if handle.mWeak.mpHeap.mRawhandle.isDestroyable:
      heap = handle.mWeak.mpHeap[]
  handle.mWeak.mpHeap.mpParent = cast[pointer](parent.mpHeap)
  body
# </Core>

# <Destructor-Overrides>
{.push, used, inline.}
template castHeapParent[T](handle: pointer; Type: typedesc[T]): Heap[T] =
  cast[ptr Heap[T]](handle)[]
template castParent[T](handle: pointer; Type: typedesc[T]): T =
  handle.castHeapParent(Type).mRawhandle
#   <Handle>
proc destroy(handle: var Instance; parent: pointer) =
  destroyInstance handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var Device; parent: pointer) =
  destroyDevice handle
  zeroMem addr handle, sizeof handle
#   </Handle>
#   <Non-Dispatchable-Handle>
proc destroy(handle: var Buffer; parent: pointer) =
  destroyBuffer parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var Semaphore; parent: pointer) =
  destroySemaphore parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var CommandPool; parent: pointer) =
  destroyCommandPool parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var CommandBuffer; parent: pointer) =
  let grandparent = parent.castHeapParent(CommandPool).mpParent.castParent(Device)
  let parent = parent.castParent(CommandPool)
  grandparent.freeCommandBuffers(parent, 1, unsafeAddr handle)
  zeroMem addr handle, sizeof handle
proc destroy(handle: var ShaderModule; parent: pointer) =
  destroyShaderModule parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var DebugUtilsMessengerExt; parent: pointer) =
  let parent = parent.castParent(Instance)
  if destroyDebugUtilsMessengerEXT_RAW == nil: parent.loadCommand destroyDebugUtilsMessengerEXT
  destroyDebugUtilsMessengerEXT parent, handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var SurfaceKHR; parent: pointer) =
  let parent = parent.castParent(Instance)
  destroySurfaceKHR parent, handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var SwapchainKHR; parent: pointer) =
  let parent = parent.castParent(Device)
  destroySwapchainKHR parent, handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var DeviceMemory; parent: pointer) =
  freeMemory parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var ImageView; parent: pointer) =
  destroyImageView parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var FrameBuffer; parent: pointer) =
  destroyFrameBuffer parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var RenderPass; parent: pointer) =
  destroyRenderPass parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var DescriptorSetLayout; parent: pointer) =
  destroyDescriptorSetLayout parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var DescriptorSet; parent: pointer) =
  discard freeDescriptorSets(
    parent.castHeapParent(DescriptorPool).mpParent.castParent(Device),
    parent.castParent(DescriptorPool),
    1, unsafeAddr handle)
  zeroMem addr handle, sizeof handle
proc destroy(handle: var DescriptorPool; parent: pointer) =
  destroyDescriptorPool parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var PipelineLayout; parent: pointer) =
  destroyPipelineLayout parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
proc destroy(handle: var Pipeline; parent: pointer) =
  destroyPipeline parent.castParent(Device), handle
  zeroMem addr handle, sizeof handle
#   </Non-Dispatchable-Handle>
{.pop.}
# </Destructor-Overrides>

proc destroy[T](handle: var Heap[T]) =
  destroy(handle.mRawhandle, handle.mpParent)

# <Public-Only-Procs>
#   <!--the reason why they are public only is for performance-->
proc setLen*[T](handle: var Unique[seq[T]]; newSize: int) =
  if handle.mWeak.mpHeap == nil:
    handle.mWeak.mpHeap = cast[ptr Heap[seq[T]]](alloc sizeof Heap[seq[T]])
    handle.mWeak.mpHeap.mWeakcnt = 1
  handle.mWeak.mpHeap.mRawhandle.setLen(newSize)

func `[]`*[T](handle: Weak[seq[T]]; i: int): T = handle[][i]


func isAlive*[T](handle: Weak[T]): bool =
  handle.mpHeap != nil and
  handle.mpHeap.mRawhandle.isDestroyable
func isAlive*[T](handle: Unique[T]): bool =
  handle.mWeak.isAlive

func rawhandle*[T](handle: Weak[T]): lent T =
  if not handle.isAlive:
    raise newException(HandleNotAliveDefect, "This handle has no reference to anywhere. Use unsafeaddr if Nil is acceptable.")
  handle.mpHeap.mRawhandle
func rawhandle*[T](handle: Unique[T]): lent T =
  handle.mWeak.rawhandle

func `[]`*[T](handle: Weak[T]): lent T {.inline.} = handle.rawhandle
func `[]`*[T](handle: Unique[T]): lent T {.inline.} = handle.rawhandle

#   <Parent-Getters>
template getParentAs[T, S](handle: Weak[T]; Type: typedesc[Weak[S]]): Weak[S] =
  if handle.isAlive:
    cast[Weak[S]](handle.mpHeap.mpParent)
  else:
    raise newException(HandleNotAliveDefect, "This handle has no reference to anywhere. It is possible that the reference has already been destroyed.")

func physicalDevice*(handle: Weak[Device]): PhysicalDevice = cast[PhysicalDevice](handle.mpHeap.mpParent)
template parent*(handle: Weak[Device]): PhysicalDevice = handle.physicalDevice

func instance*(handle: Weak[DebugUtilsMessengerEXT]): Weak[Instance] = handle.getParentAs typeof result
template parent*(handle: Weak[DebugUtilsMessengerEXT]): Weak[Instance] = handle.instance

func instance*(handle: Weak[SurfaceKHR]): Weak[Instance] = handle.getParentAs typeof result
template parent*(handle: Weak[SurfaceKHR]): Weak[Instance] = handle.instance

func device*(handle: Weak[Buffer]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[Buffer]): Weak[Device] = handle.device

func device*(handle: Weak[ShaderModule]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[ShaderModule]): Weak[Device] = handle.device

func device*(handle: Weak[SwapchainKHR]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[SwapchainKHR]): Weak[Device] = handle.device

func device*(handle: Weak[DeviceMemory]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[DeviceMemory]): Weak[Device] = handle.device

func device*(handle: Weak[Semaphore]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[Semaphore]): Weak[Device] = handle.device

func device*(handle: Weak[CommandPool]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[CommandPool]): Weak[Device] = handle.device

func device*(handle: Weak[ImageView]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[ImageView]): Weak[Device] = handle.device

func device*(handle: Weak[FrameBuffer]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[FrameBuffer]): Weak[Device] = handle.device

func device*(handle: Weak[RenderPass]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[RenderPass]): Weak[Device] = handle.device

func device*(handle: Weak[DescriptorSetLayout]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[DescriptorSetLayout]): Weak[Device] = handle.device

func device*(handle: Weak[DescriptorPool]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[DescriptorPool]): Weak[Device] = handle.device

func device*(handle: Weak[PipelineLayout]): Weak[Device] = handle.getParentAs typeof result
template parent*(handle: Weak[PipelineLayout]): Weak[Device] = handle.device
#   </Parent-Getters>

#   <Handle-Creators>
#     <Instance>
proc createInstance*(handle: var Unique[Instance]; createInfo: ptr InstanceCreateInfo): Result = impl_create:
  create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(handle: var Unique[Instance]; createInfo: ptr InstanceCreateInfo): Result = createInstance handle, createInfo
#     </Instance>
#     <Device>
proc createDevice*(parent: PhysicalDevice; handle: var Unique[Device]; createInfo: ptr DeviceCreateInfo): Result = impl_create:
  handle.mWeak.mpHeap.mpParent = cast[pointer](parent)
  parent.create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: PhysicalDevice; handle: var Unique[Device]; createInfo: ptr DeviceCreateInfo): Result = parent.createDevice handle, createInfo
#     </Device>
#     <DebugUtilsMessengerEXT>
proc createDebugUtilsMessengerEXT*(parent: Weak[Instance]; handle: var Unique[DebugUtilsMessengerExt]; createInfo: ptr DebugUtilsMessengerCreateInfoEXT): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Instance]; handle: var Unique[DebugUtilsMessengerExt]; createInfo: ptr DebugUtilsMessengerCreateInfoEXT): Result = parent.createDebugUtilsMessengerEXT handle, createInfo
#     </DebugUtilsMessengerEXT>
#     <CommandPool>
proc createCommandPool*(parent: Weak[Device]; handle: var Unique[CommandPool]; createInfo: ptr CommandPoolCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[CommandPool]; createInfo: ptr CommandPoolCreateInfo): Result = parent.createCommandPool handle, createInfo
#     </CommandPool>
#     <ShaderModule>
proc createShaderModule*(parent: Weak[Device]; handle: var Unique[ShaderModule]; createInfo: ptr ShaderModuleCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[ShaderModule]; createInfo: ptr ShaderModuleCreateInfo): Result = parent.createShaderModule handle, createInfo
#     </ShaderModule>
#     <Buffer>
proc createBuffer*(parent: Weak[Device]; handle: var Unique[Buffer]; createInfo: ptr BufferCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[Buffer]; createInfo: ptr BufferCreateInfo): Result = parent.createBuffer handle, createInfo
#     </Buffer>
#     <DeviceMemory>
proc createDeviceMemory*(parent: Weak[Device]; handle: var Unique[DeviceMemory]; allocateInfo: ptr MemoryAllocateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, allocateInfo
template create*(parent: Weak[Device]; handle: var Unique[DeviceMemory]; allocateInfo: ptr MemoryAllocateInfo): Result = parent.createDeviceMemory handle, allocateInfo
#     </DeviceMemory>
#     <Swapchain>
proc createSwapchainKHR*(parent: Weak[Device]; handle: var Unique[SwapchainKHR]; createInfo: ptr SwapchainCreateInfoKHR): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[SwapchainKHR]; createInfo: ptr SwapchainCreateInfoKHR): Result = parent.createSwapchainKHR handle, createInfo
#     </Swapchain>
#     <Semaphore>
proc create*(parent: Weak[Device]; handle: var Unique[Semaphore]; createInfo: ptr SemaphoreCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
#     </Semaphore>
#     <ImageView>
proc createImageView*(parent: Weak[Device]; handle: var Unique[ImageView]; createInfo: ptr ImageViewCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[ImageView]; createInfo: ptr ImageViewCreateInfo): Result = parent.createImageView handle, createInfo
#     </ImageView>
#     <FrameBuffer>
proc createFrameBuffer*(parent: Weak[Device]; handle: var Unique[FrameBuffer]; createInfo: ptr FrameBufferCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[FrameBuffer]; createInfo: ptr FrameBufferCreateInfo): Result = parent.createFrameBuffer handle, createInfo
#     </FrameBuffer>
#     <RenderPass>
proc createRenderPass*(parent: Weak[Device]; handle: var Unique[RenderPass]; createInfo: ptr RenderPassCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[RenderPass]; createInfo: ptr RenderPassCreateInfo): Result = parent.createRenderPass handle, createInfo
#     </RenderPass>
#     <DescriptorSetLayout>
proc createDescriptorSetLayout*(parent: Weak[Device]; handle: var Unique[DescriptorSetLayout]; createInfo: ptr DescriptorSetLayoutCreateInfo): Result = parent.impl_create:
  parent[].createDescriptorSetLayout createInfo, nil, addr handle.mWeak.mpHeap.mRawhandle
template create*(parent: Weak[Device]; handle: var Unique[DescriptorSetLayout]; createInfo: ptr DescriptorSetLayoutCreateInfo): Result = parent.createDescriptorSetLayout handle, createInfo
#     </DescriptorSetLayout>
#     <DescriptorSet>
proc createDescriptorSet*(parent: Weak[DescriptorPool]; handle: var Unique[DescriptorSet]; layout: Weak[DescriptorSetLayout]): Result = parent.impl_create:
  var createInfo = DescriptorSetAllocateInfo{
    descriptorPool: parent[],
    descriptorSetCount: 1,
    pSetLayouts: unsafeAddr layout[],
    }
  parent.parent[].allocateDescriptorSets addr createInfo, addr handle.mWeak.mpHeap.mRawhandle
template create*(parent: Weak[DescriptorPool]; handle: var Unique[DescriptorSet]; layout: Weak[DescriptorSetLayout]): Result = parent.createDescriptorSet handle, layout
#     </DescriptorSet>
#     <DescriptorPool>
proc createDescriptorPool*(parent: Weak[Device]; handle: var Unique[DescriptorPool]; createInfo: ptr DescriptorPoolCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[DescriptorPool]; createInfo: ptr DescriptorPoolCreateInfo): Result = parent.createDescriptorPool handle, createInfo
#     </DescriptorPool>
#     <PipelineLayout>
proc createPipelineLayout*(parent: Weak[Device]; handle: var Unique[PipelineLayout]; createInfo: ptr PipelineLayoutCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[PipelineLayout]; createInfo: ptr PipelineLayoutCreateInfo): Result = parent.createPipelineLayout handle, createInfo
#     </PipelineLayout>
#     <Pipeline>
proc createGraphicsPipeline*(parent: Weak[Device]; handle: var Unique[Pipeline]; createInfo: ptr GraphicsPipelineCreateInfo): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
template create*(parent: Weak[Device]; handle: var Unique[Pipeline]; createInfo: ptr GraphicsPipelineCreateInfo): Result = parent.createGraphicsPipeline handle, createInfo
#     </Pipeline>
#     <Surface>
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; window: GLFWWindow): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, window
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr DisplaySurfaceCreateInfoKHR): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr XlibSurfaceCreateInfoKHR): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr XcbSurfaceCreateInfoKHR): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr WaylandSurfaceCreateInfoKHR): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr AndroidSurfaceCreateInfoKHR): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr Win32SurfaceCreateInfoKHR): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr IOSSurfaceCreateInfoMVK): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr MacOSSurfaceCreateInfoMVK): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr MetalSurfaceCreateInfoEXT): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr HeadlessSurfaceCreateInfoEXT): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr DirectFBSurfaceCreateInfoEXT): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ViSurfaceCreateInfoNN): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ScreenSurfaceCreateInfoQNX): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ImagePipeSurfaceCreateInfoFUCHSIA): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
proc create*(parent: Weak[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr StreamDescriptorSurfaceCreateInfoGGP): Result = parent.impl_create:
  parent[].create handle.mWeak.mpHeap.mRawhandle, createInfo
#     </Surface>
#   <Handle-Creators>

proc destroy*[T](handle: var Unique[T]) =
  when defined traceHook:
    echo "# CALL DESTROY : ", T, " @", memaddr handle
  if handle.mWeak.isAlive:
    destroy handle.mWeak.mpHeap[]
    when defined traceHook:
      echo "# DONE DESTROY : ", T, " @", memaddr handle

template toRawhandleArray*[I: static int; T](handles: array[I, Weak[T]]): untyped =
  var arr {.gensym.}: array[I, T]
  for i in 0..<I:
    arr[i] = handles[i].unsaferawhandle
  arr

converter weak*[T](handle: Unique[T]): lent Weak[T] =
  inc cast[ptr uint8](unsafeAddr handle.mWeak.mpHeap.mWeakcnt)[]
  handle.mWeak
converter weak*[T](handle: var Unique[T]): var Weak[T] =
  inc handle.mWeak.mpHeap.mWeakcnt
  handle.mWeak

# </Public-Only-Procs>
