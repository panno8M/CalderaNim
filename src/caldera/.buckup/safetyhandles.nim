import std/macros
import std/strutils

import vulkan
import vulkan/commands/extensions {.all.}
from vulkan/tools/glfw import glfwCreateWindowSurface, GLFWWindow

template memaddr(x): untyped = cast[uint64](unsafeaddr x).toHex

type
  HandleNotAliveDefect* = object of NilAccessDefect

type
  Heap*[HandleType] = object
    i_parent: pointer
    i_rawhandle: HandleType
    updcnt: uint8
  Shared*[HandleType] = object
    i_heap: ptr Heap[HandleType]
    updcnt: uint8

func isAlive*[T](handle: Shared[T]): bool =
  handle.i_heap != nil and
  handle.i_heap.i_rawhandle != nil and
  handle.updcnt == handle.i_heap.updcnt

func rawhandle*[T](handle: Shared[T]): lent T =
  if not handle.isAlive:
    raise newException(HandleNotAliveDefect, "This handle has no reference to anywhere. Use unsafeaddr if Nil is acceptable.")
  handle.i_heap.i_rawhandle

{.push, inline.}
func `[]`*[T](handle: Shared[T]): lent T =
  handle.rawhandle
{.pop.}

template getParentAs[T, S](handle: Shared[T]; Type: typedesc[Shared[S]]): Shared[S] =
  if handle.isAlive:
    Shared[S](
      i_heap: cast[ptr Heap[S]](handle.i_heap.i_parent),
      updcnt: cast[ptr Heap[S]](handle.i_heap.i_parent).updcnt
      )
  else:
    raise newException(HandleNotAliveDefect, "This handle has no reference to anywhere. It is possible that the reference has already been destroyed.")

# <Specify>
func parent*(handle: Shared[DebugUtilsMessengerEXT]): Shared[Instance] = handle.getParentAs typeof result
func parent*(handle: Shared[SurfaceKHR]): Shared[Instance] = handle.getParentAs typeof result

func parent*(handle: Shared[Buffer]): Shared[Device] = handle.getParentAs typeof result
func parent*(handle: Shared[ShaderModule]): Shared[Device] = handle.getParentAs typeof result
func parent*(handle: Shared[SwapchainKHR]): Shared[Device] = handle.getParentAs typeof result
func parent*(handle: Shared[DeviceMemory]): Shared[Device] = handle.getParentAs typeof result
func parent*(handle: Shared[Semaphore]): Shared[Device] = handle.getParentAs typeof result
func parent*(handle: Shared[CommandPool]): Shared[Device] = handle.getParentAs typeof result
# </Specify>

template impl_destroyHeap(body) =
  body
  handle.i_rawhandle = cast[typeof(handle).HandleType](nil)
template getParentAs[T,S](handle: var Heap[T]; Type: typedesc[Heap[S]]): Heap[S] =
  cast[ptr Heap[S]](handle.i_parent)[]

# <Specify>
#  <Handle>
proc destroyHeap(handle: var Heap[Instance]) =
  impl_destroyHeap:
    destroyInstance handle.i_rawhandle
proc destroyHeap(handle: var Heap[Device]) =
  impl_destroyHeap:
    destroyDevice handle.i_rawhandle
#  </Handle>
#  <Non-Dispatchable-Handle>
proc destroyHeap(handle: var Heap[Buffer]) =
  template parent: untyped = handle.getParentAs(Heap[Device]).i_rawhandle
  impl_destroyHeap:
    destroyBuffer(parent, handle.i_rawhandle)
proc destroyHeap(handle: var Heap[Semaphore]) =
  template parent: untyped = handle.getParentAs(Heap[Device]).i_rawhandle
  impl_destroyHeap:
    destroySemaphore(parent, handle.i_rawhandle)
proc destroyHeap(handle: var Heap[CommandPool]) =
  template parent: untyped = handle.getParentAs(Heap[Device]).i_rawhandle
  impl_destroyHeap:
    destroyCommandPool(parent, handle.i_rawhandle)
proc destroyHeap(handle: var Heap[CommandBuffer]) =
  template parent: untyped = handle.getParentAs(Heap[CommandPool]).i_rawhandle
  template grandparent: untyped = handle.getParentAs(Heap[CommandPool]).getParentAs(Heap[Device]).i_rawhandle
  impl_destroyHeap:
    grandparent.freeCommandBuffers(parent, 1, addr handle.i_rawhandle)
proc destroyHeap(handle: var Heap[ShaderModule]) =
  template parent: untyped = handle.getParentAs(Heap[Device]).i_rawhandle
  impl_destroyHeap:
    destroyShaderModule(parent, handle.i_rawhandle)
proc destroyHeap(handle: var Heap[DebugUtilsMessengerExt]) =
  template parent: untyped = handle.getParentAs(Heap[Instance]).i_rawhandle
  impl_destroyHeap:
    if destroyDebugUtilsMessengerEXT_RAW == nil: parent.loadCommand destroyDebugUtilsMessengerEXT
    destroyDebugUtilsMessengerEXT parent, handle.i_rawhandle
proc destroyHeap(handle: var Heap[SurfaceKHR]) =
  template parent: untyped = handle.getParentAs(Heap[Instance]).i_rawhandle
  impl_destroyHeap:
    if destroySurfaceKHR_RAW == nil: parent.loadCommand destroySurfaceKHR
    destroySurfaceKHR parent, handle.i_rawhandle
proc destroyHeap(handle: var Heap[SwapchainKHR]) =
  template parent: untyped = handle.getParentAs(Heap[Device]).i_rawhandle
  impl_destroyHeap:
    if destroySwapchainKHR_RAW == nil: parent.loadCommand destroySwapchainKHR
    destroySwapchainKHR parent, handle.i_rawhandle
proc destroyHeap(handle: var Heap[DeviceMemory]) =
  template parent: untyped = handle.getParentAs(Heap[Device]).i_rawhandle
  impl_destroyHeap:
    freeMemory parent, handle.i_rawhandle
#  </Non-Dispatchable-Handle>
# </Specify>

# ============== #
# UNIQUE HANDLES #
# ============== #

type
  Unique*[HandleType] = object
    i_shared: Shared[HandleType]

proc `=destroy`[T](handle: var Unique[T])

template shared[T](handle: Unique[T]): Shared[T] {.used.} = handle.i_shared
template shared[T](handle: Shared[T]): Shared[T] {.used.} = handle
template heap[T](handle: Unique[T]|Shared[T]): ptr Heap[T] {.used.} = handle.shared.i_heap

when not isMainModule:
  converter weak*[T](handle: Unique[T]): lent Shared[T] = handle.i_shared

func isAlive*[T](handle: Unique[T]): bool =
  handle.i_shared.isAlive

func rawhandle*[T](handle: Unique[T]): lent T =
  handle.i_shared.rawhandle
func `[]`*[T](handle: Unique[T]): lent T =
  handle.rawhandle

proc destroy*[T](handle: var Unique[T]) =
  echo "# CALL DESTROY : ", T, " @", memaddr handle
  if handle.isAlive:
    destroyHeap handle.i_shared.i_heap[]
    echo "# DONE DESTROY : ", T, " @", memaddr handle

proc `=destroy`[T](handle: var Unique[T]) =
  echo "# END LIFE: ", T, " @", memaddr handle
  if handle.heap != nil:
    if handle.heap.i_rawhandle != nil:
      destroyHeap handle.heap[]
    dealloc handle.heap
    echo "# DONE DESTROY : ", T, " @", memaddr handle


template impl_create(body): Result =
  template HandleType: untyped = typeof(handle).HandleType
  if handle.heap == nil:
    handle.heap() = cast[ptr Heap[HandleType]](alloc sizeof Heap[HandleType])
    handle.heap.updcnt = 0
  else:
    if handle.heap[].i_rawhandle != nil:
      destroyHeap handle.heap[]
    inc handle.heap.updcnt
    handle.shared.updcnt = handle.heap.updcnt
  body
template impl_create(parent: untyped; body): Result =
  template HandleType: untyped = typeof(handle).HandleType
  if handle.heap == nil:
    handle.heap() = cast[ptr Heap[HandleType]](alloc sizeof Heap[HandleType])
    handle.heap.updcnt = 0
  else:
    if handle.heap[].i_rawhandle != nil:
      destroyHeap handle.heap[]
    inc handle.heap.updcnt
    handle.shared.updcnt = handle.heap.updcnt
  handle.heap.i_parent = cast[pointer](parent.heap)
  body
template impl_overwrite(body): Result =
  template HandleType: untyped = typeof(handle).HandleType
  var heap: Heap[HandleType]
  var needsDestroy: bool
  if handle.heap == nil:
    handle.heap() = cast[ptr Heap[HandleType]](alloc sizeof Heap[HandleType])
    handle.heap.updcnt = 0
  else:
    if handle.heap.i_rawhandle != nil:
      heap = handle.heap[]
      needsDestroy = true
  let result = body
  if needsDestroy: destroyHeap heap
  result
template impl_overwrite(parent: untyped; body): Result =
  template HandleType: untyped = typeof(handle).HandleType
  var heap: Heap[HandleType]
  var needsDestroy: bool
  if handle.heap == nil:
    handle.heap() = cast[ptr Heap[HandleType]](alloc sizeof Heap[HandleType])
    handle.heap.updcnt = 0
  else:
    if handle.heap.i_rawhandle != nil:
      heap = handle.heap[]
      needsDestroy = true
  handle.heap.i_parent = cast[pointer](parent.heap)
  let result = body
  if needsDestroy: destroyHeap heap
  result

# <Specify>
#   <Handle>
#     <Instance>
proc create*(handle: var Unique[Instance]; createInfo: ptr InstanceCreateInfo): Result = impl_create:
  createInstance createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(handle: var Unique[Instance]; createInfo: ptr InstanceCreateInfo): Result = impl_overwrite:
  createInstance createInfo, nil, addr handle.heap.i_rawhandle
#     </Instance>
#     <Device>
proc create*(parent: PhysicalDevice; handle: var Unique[Device]; createInfo: ptr DeviceCreateInfo): Result = impl_create:
  parent.createDevice createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: PhysicalDevice; handle: var Unique[Device]; createInfo: ptr DeviceCreateInfo): Result = impl_overwrite:
  parent.createDevice createInfo, nil, addr handle.heap.i_rawhandle
#     </Device>
#   </Handle>
#   <Non-Dispatchable-Handle>
#     <DebugUtilsMessengerEXT>
proc create*(parent: Shared[Instance]; handle: var Unique[DebugUtilsMessengerExt]; createInfo: ptr DebugUtilsMessengerCreateInfoEXT): Result = parent.impl_create:
  if createDebugUtilsMessengerEXT_RAW == nil: parent[].loadCommand createDebugUtilsMessengerEXT
  parent[].createDebugUtilsMessengerEXT createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[DebugUtilsMessengerExt]; createInfo: ptr DebugUtilsMessengerCreateInfoEXT): Result = parent.impl_overwrite:
  if createDebugUtilsMessengerEXT_RAW == nil: parent[].loadCommand createDebugUtilsMessengerEXT
  parent[].createDebugUtilsMessengerEXT createInfo, nil, addr handle.heap.i_rawhandle
#     </DebugUtilsMessengerEXT>
#     <CommandPool>
proc create*(parent: Shared[Device]; handle: var Unique[CommandPool]; createInfo: ptr CommandPoolCreateInfo): Result = parent.impl_create:
  parent[].createCommandPool createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Device]; handle: var Unique[CommandPool]; createInfo: ptr CommandPoolCreateInfo): Result = parent.impl_overwrite:
  parent[].createCommandPool createInfo, nil, addr handle.heap.i_rawhandle
# proc create*[QF](parent: Shared[Device]; handle: var Unique[ClCommandPool[QF]]; createInfo: ptr CommandPoolCreateInfo): Result = parent.impl_create:
#   parent[].createCommandPool createInfo, nil, addr handle.heap.i_rawhandle.asBasic
# proc overwrite*[QF](parent: Shared[Device]; handle: var Unique[ClCommandPool[QF]]; createInfo: ptr CommandPoolCreateInfo): Result = parent.impl_overwrite:
#   parent[].createCommandPool createInfo, nil, addr handle.heap.i_rawhandle
#     </CommandPool>
#     <ShaderModule>
proc create*(parent: Shared[Device]; handle: var Unique[ShaderModule]; createInfo: ptr ShaderModuleCreateInfo): Result = parent.impl_create:
  parent[].createShaderModule createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Device]; handle: var Unique[ShaderModule]; createInfo: ptr ShaderModuleCreateInfo): Result = parent.impl_overwrite:
  parent[].createShaderModule createInfo, nil, addr handle.heap.i_rawhandle
#     </ShaderModule>
#     <Buffer>
proc create*(parent: Shared[Device]; handle: var Unique[Buffer]; createInfo: ptr BufferCreateInfo): Result = parent.impl_create:
  parent[].createBuffer createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Device]; handle: var Unique[Buffer]; createInfo: ptr BufferCreateInfo): Result = parent.impl_overwrite:
  parent[].createBuffer createInfo, nil, addr handle.heap.i_rawhandle
#     </Buffer>
#     <DeviceMemory>
proc create*(parent: Shared[Device]; handle: var Unique[DeviceMemory]; allocateInfo: ptr MemoryAllocateInfo): Result = parent.impl_create:
  parent[].allocateMemory(allocateInfo, nil, addr handle.heap.i_rawhandle)
proc overwrite*(parent: Shared[Device]; handle: var Unique[DeviceMemory]; allocateInfo: ptr MemoryAllocateInfo): Result = parent.impl_overwrite:
  parent[].allocateMemory(allocateInfo, nil, addr handle.heap.i_rawhandle)
#     </DeviceMemory>
#     <Swapchain>
proc create*(parent: Shared[Device]; handle: var Unique[SwapchainKHR]; createInfo: ptr SwapchainCreateInfoKHR): Result = parent.impl_create:
  if createSwapchainKHR_RAW == nil: parent[].loadCommand createSwapchainKHR
  parent[].createSwapchainKHR createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Device]; handle: var Unique[SwapchainKHR]; createInfo: ptr SwapchainCreateInfoKHR): Result = parent.impl_overwrite:
  if createSwapchainKHR_RAW == nil: parent[].loadCommand createSwapchainKHR
  parent[].createSwapchainKHR createInfo, nil, addr handle.heap.i_rawhandle
#     </Swapchain>
#     <Semaphore>
proc create*(parent: Shared[Device]; handle: var Unique[Semaphore]; createInfo: ptr SemaphoreCreateInfo): Result = parent.impl_create:
  parent[].createSemaphore createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Device]; handle: var Unique[Semaphore]; createInfo: ptr SemaphoreCreateInfo): Result = parent.impl_overwrite:
  parent[].createSemaphore createInfo, nil, addr handle.heap.i_rawhandle
# proc create*(parent: Shared[Device]; handle: var Unique[ClSemaphore[binary]]; pnext= default(pointer)): Result = parent.impl_create:
#   let CI = SemaphoreCreateInfo{ pnext: pnext }
#   parent[].createSemaphore unsafeAddr CI, nil, addr handle.heap.i_rawhandle.asBasic
# proc create*(parent: Shared[Device]; handle: var Unique[ClSemaphore[timeline]]; initialValue= default(uint64); pnext= default(pointer)): Result = parent.impl_create:
#   let typeCI = SemaphoreTypeCreateInfo{
#     pnext: pnext,
#     semaphoreType: SemaphoreType.timeline,
#     initialValue: initialValue,}
#   let CI = SemaphoreCreateInfo{ pnext: unsafeAddr typeCI }
#   parent[].createSemaphore unsafeAddr CI, nil, addr handle.heap.i_rawhandle.asBasic
# proc overwrite*(parent: Shared[Device]; handle: var Unique[ClSemaphore[binary]]; pnext: pointer): Result = parent.impl_overwrite:
#   let CI = SemaphoreCreateInfo{ pnext: pnext }
#   parent[].createSemaphore unsafeAddr CI, nil, addr handle.heap.i_rawhandle.asBasic
# proc overwrite*(parent: Shared[Device]; handle: var Unique[ClSemaphore[timeline]]; initialValue= default(uint64); pnext: pointer): Result = parent.impl_overwrite:
#   let typeCI = SemaphoreTypeCreateInfo{
#     pnext: pnext,
#     semaphoreType: SemaphoreType.timeline,
#     initialValue: initialValue,}
#   let CI = SemaphoreCreateInfo{ pnext: unsafeAddr typeCI }
#   parent[].createSemaphore unsafeAddr CI, nil, addr handle.heap.i_rawhandle.asBasic
#     </Semaphore>
#     <Surface>
proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; window: GLFWWindow): Result = parent.impl_create:
  parent[].glfwCreateWindowSurface window, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; window: GLFWWindow): Result = parent.impl_overwrite:
  parent[].glfwCreateWindowSurface window, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr DisplaySurfaceCreateInfoKHR): Result = parent.impl_create:
  if createDisplayPlaneSurfaceKHR_RAW == nil: parent[].loadCommand createDisplayPlaneSurfaceKHR
  parent[].createDisplayPlaneSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr DisplaySurfaceCreateInfoKHR): Result = parent.impl_overwrite:
  if createDisplayPlaneSurfaceKHR_RAW == nil: parent[].loadCommand createDisplayPlaneSurfaceKHR
  parent[].createDisplayPlaneSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr XlibSurfaceCreateInfoKHR): Result = parent.impl_create:
  if createXlibSurfaceKHR_RAW == nil: parent[].loadCommand createXlibSurfaceKHR
  parent[].createXlibSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr XlibSurfaceCreateInfoKHR): Result = parent.impl_overwrite:
  if createXlibSurfaceKHR_RAW == nil: parent[].loadCommand createXlibSurfaceKHR
  parent[].createXlibSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr XcbSurfaceCreateInfoKHR): Result = parent.impl_create:
  if createXcbSurfaceKHR_RAW == nil: parent[].loadCommand createXcbSurfaceKHR
  parent[].createXcbSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr XcbSurfaceCreateInfoKHR): Result = parent.impl_overwrite:
  if createXcbSurfaceKHR_RAW == nil: parent[].loadCommand createXcbSurfaceKHR
  parent[].createXcbSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr WaylandSurfaceCreateInfoKHR): Result = parent.impl_create:
  if createWaylandSurfaceKHR_RAW == nil: parent[].loadCommand createWaylandSurfaceKHR
  parent[].createWaylandSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr WaylandSurfaceCreateInfoKHR): Result = parent.impl_overwrite:
  if createWaylandSurfaceKHR_RAW == nil: parent[].loadCommand createWaylandSurfaceKHR
  parent[].createWaylandSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr AndroidSurfaceCreateInfoKHR): Result = parent.impl_create:
  if createAndroidSurfaceKHR_RAW == nil: parent[].loadCommand createAndroidSurfaceKHR
  parent[].createAndroidSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr AndroidSurfaceCreateInfoKHR): Result = parent.impl_overwrite:
  if createAndroidSurfaceKHR_RAW == nil: parent[].loadCommand createAndroidSurfaceKHR
  parent[].createAndroidSurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr Win32SurfaceCreateInfoKHR): Result = parent.impl_create:
  if createWin32SurfaceKHR_RAW == nil: parent[].loadCommand createWin32SurfaceKHR
  parent[].createWin32SurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr Win32SurfaceCreateInfoKHR): Result = parent.impl_overwrite:
  if createWin32SurfaceKHR_RAW == nil: parent[].loadCommand createWin32SurfaceKHR
  parent[].createWin32SurfaceKHR createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr IOSSurfaceCreateInfoMVK): Result = parent.impl_create:
  if createIOSSurfaceMVK_RAW == nil: parent[].loadCommand createIOSSurfaceMVK
  parent[].createIOSSurfaceMVK createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr IOSSurfaceCreateInfoMVK): Result = parent.impl_overwrite:
  if createIOSSurfaceMVK_RAW == nil: parent[].loadCommand createIOSSurfaceMVK
  parent[].createIOSSurfaceMVK createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr MacOSSurfaceCreateInfoMVK): Result = parent.impl_create:
  if createMacOSSurfaceMVK_RAW == nil: parent[].loadCommand createMacOSSurfaceMVK
  parent[].createMacOSSurfaceMVK createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr MacOSSurfaceCreateInfoMVK): Result = parent.impl_overwrite:
  if createMacOSSurfaceMVK_RAW == nil: parent[].loadCommand createMacOSSurfaceMVK
  parent[].createMacOSSurfaceMVK createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr MetalSurfaceCreateInfoEXT): Result = parent.impl_create:
  if createMetalSurfaceEXT_RAW == nil: parent[].loadCommand createMetalSurfaceEXT
  parent[].createMetalSurfaceEXT createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr MetalSurfaceCreateInfoEXT): Result = parent.impl_overwrite:
  if createMetalSurfaceEXT_RAW == nil: parent[].loadCommand createMetalSurfaceEXT
  parent[].createMetalSurfaceEXT createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr HeadlessSurfaceCreateInfoEXT): Result = parent.impl_create:
  if createHeadlessSurfaceEXT_RAW == nil: parent[].loadCommand createHeadlessSurfaceEXT
  parent[].createHeadlessSurfaceEXT createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr HeadlessSurfaceCreateInfoEXT): Result = parent.impl_overwrite:
  if createHeadlessSurfaceEXT_RAW == nil: parent[].loadCommand createHeadlessSurfaceEXT
  parent[].createHeadlessSurfaceEXT createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr DirectFBSurfaceCreateInfoEXT): Result = parent.impl_create:
  if createDirectFBSurfaceEXT_RAW == nil: parent[].loadCommand createDirectFBSurfaceEXT
  parent[].createDirectFBSurfaceEXT createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr DirectFBSurfaceCreateInfoEXT): Result = parent.impl_overwrite:
  if createDirectFBSurfaceEXT_RAW == nil: parent[].loadCommand createDirectFBSurfaceEXT
  parent[].createDirectFBSurfaceEXT createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ViSurfaceCreateInfoNN): Result = parent.impl_create:
  if createViSurfaceNN_RAW == nil: parent[].loadCommand createViSurfaceNN
  parent[].createViSurfaceNN createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ViSurfaceCreateInfoNN): Result = parent.impl_overwrite:
  if createViSurfaceNN_RAW == nil: parent[].loadCommand createViSurfaceNN
  parent[].createViSurfaceNN createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ScreenSurfaceCreateInfoQNX): Result = parent.impl_create:
  if createScreenSurfaceQNX_RAW == nil: parent[].loadCommand createScreenSurfaceQNX
  parent[].createScreenSurfaceQNX createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ScreenSurfaceCreateInfoQNX): Result = parent.impl_overwrite:
  if createScreenSurfaceQNX_RAW == nil: parent[].loadCommand createScreenSurfaceQNX
  parent[].createScreenSurfaceQNX createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ImagePipeSurfaceCreateInfoFUCHSIA): Result = parent.impl_create:
  if createImagePipeSurfaceFUCHSIA_RAW == nil: parent[].loadCommand createImagePipeSurfaceFUCHSIA
  parent[].createImagePipeSurfaceFUCHSIA createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr ImagePipeSurfaceCreateInfoFUCHSIA): Result = parent.impl_overwrite:
  if createImagePipeSurfaceFUCHSIA_RAW == nil: parent[].loadCommand createImagePipeSurfaceFUCHSIA
  parent[].createImagePipeSurfaceFUCHSIA createInfo, nil, addr handle.heap.i_rawhandle

proc create*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr StreamDescriptorSurfaceCreateInfoGGP): Result = parent.impl_create:
  if createStreamDescriptorSurfaceGGP_RAW == nil: parent[].loadCommand createStreamDescriptorSurfaceGGP
  parent[].createStreamDescriptorSurfaceGGP createInfo, nil, addr handle.heap.i_rawhandle
proc overwrite*(parent: Shared[Instance]; handle: var Unique[SurfaceKHR]; createInfo: ptr StreamDescriptorSurfaceCreateInfoGGP): Result = parent.impl_overwrite:
  if createStreamDescriptorSurfaceGGP_RAW == nil: parent[].loadCommand createStreamDescriptorSurfaceGGP
  parent[].createStreamDescriptorSurfaceGGP createInfo, nil, addr handle.heap.i_rawhandle
#     </Surface>
#   </Non-Dispatchable-Handle>
# </Specify>

template toRawhandleArray*[I: static int; T](handles: array[I, Shared[T]]): untyped =
  var arr {.gensym.}: array[I, T]
  for i in 0..<I:
    arr[i] = handles[i].unsaferawhandle
  arr