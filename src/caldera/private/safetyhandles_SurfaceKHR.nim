import std/importutils
import vulkan
import ./safetyhandles {.all.}
privateAccess Uniq
privateAccess Weak
privateAccess Pac
from vkfw import glfwCreateWindowSurface, GLFWWindow

{.push discardable, inline.}
proc destroy*(handle: var Pac[SurfaceKHR]) = impl_destroy(handle):
  template instance: Instance = handle.castParent(Instance)
  destroySurfaceKHR instance, handle.mHandle

proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; window: GLFWWindow): Result = parent.impl_create(handle):
  parent[].glfwCreateWindowSurface window, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: DisplaySurfaceCreateInfoKHR): Result = parent.impl_create(handle):
  parent[].createDisplayPlaneSurfaceKHR unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: XlibSurfaceCreateInfoKHR): Result = parent.impl_create(handle):
  parent[].createXlibSurfaceKHR unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: XcbSurfaceCreateInfoKHR): Result = parent.impl_create(handle):
  parent[].createXcbSurfaceKHR unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: WaylandSurfaceCreateInfoKHR): Result = parent.impl_create(handle):
  parent[].createWaylandSurfaceKHR unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: AndroidSurfaceCreateInfoKHR): Result = parent.impl_create(handle):
  parent[].createAndroidSurfaceKHR unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: Win32SurfaceCreateInfoKHR): Result = parent.impl_create(handle):
  parent[].createWin32SurfaceKHR unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: IOSSurfaceCreateInfoMVK): Result = parent.impl_create(handle):
  parent[].createIOSSurfaceMVK unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: MacOSSurfaceCreateInfoMVK): Result = parent.impl_create(handle):
  parent[].createMacOSSurfaceMVK unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: MetalSurfaceCreateInfoEXT): Result = parent.impl_create(handle):
  parent[].createMetalSurfaceEXT unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: HeadlessSurfaceCreateInfoEXT): Result = parent.impl_create(handle):
  parent[].createHeadlessSurfaceEXT unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: DirectFBSurfaceCreateInfoEXT): Result = parent.impl_create(handle):
  parent[].createDirectFBSurfaceEXT unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: ViSurfaceCreateInfoNN): Result = parent.impl_create(handle):
  parent[].createViSurfaceNN unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: ScreenSurfaceCreateInfoQNX): Result = parent.impl_create(handle):
  parent[].createScreenSurfaceQNX unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: ImagePipeSurfaceCreateInfoFUCHSIA): Result = parent.impl_create(handle):
  parent[].createImagePipeSurfaceFUCHSIA unsafeAddr createInfo, nil, addr handle.mrPac.mHandle
proc create*(parent: Weak[Instance]; handle: var Uniq[SurfaceKHR]; createInfo: StreamDescriptorSurfaceCreateInfoGGP): Result = parent.impl_create(handle):
  parent[].createStreamDescriptorSurfaceGGP unsafeAddr createInfo, nil, addr handle.mrPac.mHandle

func instance*(handle: Weak[SurfaceKHR]): Weak[Instance] = handle.getParentAs typeof result
template parent*(handle: Weak[SurfaceKHR]): Weak[Instance] = handle.instance
{.pop.} # discardable, inline