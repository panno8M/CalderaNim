import std/options
import std/sugar
import std/macros
from std/os import fileExists

import caldera
import caldera/safetyhandles {.all.}
import vkfw

# Utilities
proc assign[T](dst: var T, src: sink Option[T]) =
  if src.isSome: dst = src.get
proc clamp(x, a, b: Extent2D): Extent2D = Extent2D(
  width: x.width.clamp(a.width, b.width),
  height: x.height.clamp(a.height, b.height),)

proc search[T](s: openArray[T]; pred: proc(x: T): bool): Option[T] {.inline, effectsOf: pred.} =
  for xs in s:
    if pred(xs): return some xs
macro searchIt[T](s: openArray[T]; pred): Option[T] =
  let it = ident"it"
  quote do: `s`.search(`it` => `pred`)

template cstr(chars: openArray[char]): cstring = cast[cstring](unsafeAddr chars)

# Configuration
const enableValidationLayers =
  not defined(noValidation) and not defined(release)

const winsz = Extent2D(width: 640, height: 480)

when enableValidationLayers:
  const debugLayer = [ "VK_LAYER_KHRONOS_validation" ]
  # Debug callback
  proc debugCallback(
        messageSeverity: DebugUtilsMessageSeverityFlagBitsEXT;
        messageTypes: DebugUtilsMessageTypeFlagsEXT;
        pCallbackData: ptr DebugUtilsMessengerCallbackDataEXT;
        pUserData: pointer;
      ): Bool32 {.cdecl.} =
    echo pCallbackData.pMessage

type
  BufferMemory = object
    memory: Uniq[DeviceMemory]
    buffer: Uniq[Buffer]
    size: DeviceSize

var
  window: GLFWWindow
  instance: Uniq[Instance]
  device: Uniq[Device]
  messenger: Uniq[DebugUtilsMessengerEXT]
  surface: Uniq[SurfaceKHR]
  physicalDevice: PhysicalDevice
  graphicsQueue: Queue
  presentQueue: Queue
  deviceMemoryProperties: PhysicalDeviceMemoryProperties
  semaphore: tuple[ imageAvailable, renderingFinished: Uniq[Semaphore]]

  vertexSource: BufferMemory
  indexSource: BufferMemory
  vertexBindingDescription: VertexInputBindingDescription
  vertexAttributeDescriptions: seq[VertexInputAttributeDescription]

  uniform: tuple[
    handle: BufferMemory,
    data: tuple[
      transformationMatrix: Mat[4,4,float32]
    ]]
  descriptorPool: Uniq[DescriptorPool]
  descriptorSetLayout: Uniq[DescriptorSetLayout]
  descriptorSet: DescriptorSet

  swapchain: Uniq[SwapchainKHR]
  swapchainInfo: tuple[
    extent: Extent2D,
    format: Format,
    images: seq[Image],
    imageViews: seq[Uniq[ImageView]],
    framebuffers: seq[Uniq[Framebuffer]],
  ]

  renderPass: Uniq[RenderPass]
  pipelineLayout: Uniq[PipelineLayout]
  graphicsPipeline: Pipeline

  commandPool: Uniq[CommandPool]
  graphicsCommandBuffers: seq[CommandBuffer]

  graphicsQueueFamily: uint32
  presentQueueFamily: uint32

  mousePos: tuple[ last, current, delta: array[2,float] ]

  matrices = (
    view: (mat: mat4[float32](1), needsUpdate: true),
    proj: (mat: mat4[float32](1), needsUpdate: true),
  )
  camera = newLens(
    fov= 70'deg32.rad,
    aspect= winsz.aspect,
    z= (near: 0.1f, far: 10f))
  modelCoord = newCoords()

camera.coord.point [0f, -3, 1]

# NOTE: support swap chain recreation (not only required for resized windows!)
# NOTE: window resize may not result in Vulkan telling that the swap chain should be recreated, should be handled explicitly!
var windowResized = false
proc onWindowResized(window: GLFWWindow; width, height: int32) {.cdecl.} =
  windowResized = true

func aspect(e: Extent2D): float32 = e.width.float32 / e.height.float32

func sendData[T](memory: Weak[DeviceMemory]; data: ptr T) =
  var devicedata: pointer
  memory.map(DeviceSize(0), DeviceSize sizeof data[], MemoryMapFlags.none, addr devicedata)
  copyMem(devicedata, data, sizeof data[])
  memory.unmap

#  Find device memory that is supported by the requirements (typeBits) and meets the desired properties
func getMemoryType(typeBits: uint32; prop: MemoryPropertyFlagBits; props: PhysicalDeviceMemoryProperties): Option[uint32] =
  for i in 0'u32..<32:
    if (typebits and (1'u32 shl i)) == 0: continue
    if prop in props.memoryTypes[i].propertyFlags:
      return some i

proc allocate*(device: Weak[Device]; sb: var BufferMemory; bufferCI: var BufferCreateInfo; memProp: MemoryPropertyFlagBits) =
  device.create(sb.buffer, bufferCI)
  var memReq: MemoryRequirements
  device[].getBufferMemoryRequirements(sb.buffer[], addr memReq)
  var memAlloc= MemoryAllocateInfo{
    allocationSize: memReq.size,
    memoryTypeIndex: getMemoryType(memReq.memoryTypeBits, memProp, deviceMemoryProperties).get(0)}
  device.create(sb.memory, memAlloc)
  discard device[].bindBufferMemory(sb.buffer[], sb.memory[], DeviceSize(0))
  sb.size = bufferCI.size

proc destroy*(sb: var BufferMemory) =
  destroy sb.buffer
  destroy sb.memory

func cmdCopyBuffer*(commandBuffer: CommandBuffer; src, dst: BufferMemory; regionCount: uint32; pRegions: arrPtr[BufferCopy]) =
  commandBuffer.cmdCopyBuffer(src.buffer[], dst.buffer[], regionCount, pRegions)
func cmdCopyBuffer*(commandBuffer: CommandBuffer; src, dst: BufferMemory) =
  let region = BufferCopy(size: src.size)
  commandBuffer.cmdCopyBuffer(src, dst, 1'u32, unsafeAddr region)

proc updateUniformData =
  uniform.data.transformationMatrix = camera.projection * camera.view * modelCoord.localModel

  uniform.handle.memory.sendData addr uniform.data

proc chooseSurfaceFormat(availables: seq[SurfaceFormatKHR]): SurfaceFormatKHR =
  result = availables[0]

  #  We can either choose any format
  if availables.len == 1 and availables[0].format == Format.undefined:
    return SurfaceFormatKHR{
      format: Format.r8g8b8a8Unorm,
      colorSpace: ColorspaceKHR.srgbNonlinearKHR,}

  #  Or go with the standard format - if available
  result.assign availables.searchIt(it.format == Format.r8g8b8a8Unorm)


proc chooseSwapExtent(surfaceCapabilities: ptr SurfaceCapabilitiesKHR): Extent2D =
  if surfaceCapabilities.currentExtent.width == uint32.high:
    winsz.clamp(
      surfaceCapabilities.minImageExtent,
      surfaceCapabilities.maxImageExtent,)
  else: surfaceCapabilities.currentExtent

proc choosePresentMode(presentModes: seq[PresentModeKHR]): PresentModeKHR =
  #  If mailbox is unavailable, fall back to FIFO (guaranteed to be available)
  if PresentModeKHR.mailboxKHR in presentModes:
    PresentModeKHR.mailboxKHR
  else: PresentModeKHR.fifoKHR

proc create(instance: var Uniq[Instance]): Weak[Instance] {.discardable.} =
  var appInfo = ApplicationInfo{
    pApplicationName: "VulkanClear",
    applicationVersion: uint32 makeApiVersion(0, 1, 0, 0),
    pEngineName: "ClearScreenEngine",
    engineVersion: uint32 makeApiVersion(0, 1, 0, 0),
    apiVersion: apiVersion10,}

  #  Get instance extensions required by GLFW to draw to window
  var glfwExtensionCount: uint32
  let glfwExtensions = glfwGetRequiredInstanceExtensions(addr glfwExtensionCount)

  var extensions = glfwExtensions.cstringArrayToSeq(glfwExtensionCount)

  when enableValidationLayers:
    extensions.add(ExtDebugUtilsExtensionName)

  #  Check for extensions
  var availableExtensionProperties: seq[ExtensionProperties]
  enumerate availableExtensionProperties

  if availableExtensionProperties.len == 0:
    quit "no extensions supported!"
  else:
    echo "supported extensions:"
    for availableExtensionProperty in availableExtensionProperties:
      echo "* ", availableExtensionProperty.extensionName.cstr

  var instanceCI = InstanceCreateInfo{
    pApplicationInfo: addr appInfo,
    enabledExtensionCount: extensions.len.uint32,
    ppEnabledExtensionNames: extensions.allocCStringArray,}

  when enableValidationLayers:
    instanceCI.enabledLayerCount = 1
    instanceCI.ppEnabledLayerNames = debugLayer.allocCStringArray

  #  Initialize Vulkan instance
  if create(instance, instanceCI) != success:
    quit "failed to create instance!"
  instance.weak

proc loadAppCommands(instance: Weak[Instance]): Weak[Instance] {.discardable.} =
  result = instance
  instance[].loadCommands:
    vulkan.getSwapchainImagesKHR
    vulkan.acquireNextImageKHR
    vulkan.queuePresentKHR

proc create(instance: Weak[Instance]; messenger: var Uniq[DebugUtilsMessengerEXT]): Weak[Instance] {.discardable.} =
  result = instance
  when enableValidationLayers:
    var debugUtilsMessengerCI = DebugUtilsMessengerCreateInfoEXT{
    messageSeverity: DebugUtilsMessageSeverityFlagsEXT{errorEXT, warningEXT},
    messageType: DebugUtilsMessageTypeFlagsEXT.all,
    pfnUserCallback: debugCallback,
    }

    if instance.create(messenger, debugUtilsMessengerCI) != success:
      quit "failed to create debug callback"
  else:
    echo "skipped creating debug callback"

proc create(instance: Weak[Instance]; surface: var Uniq[SurfaceKHR]; targetWindow: GLFWWindow): Weak[Instance] {.discardable.} =
  result = instance
  if safetyhandles.create(instance, surface, targetWindow) != success:
    quit "failed to create window surface!"

proc find(instance: Weak[Instance]; physicalDevice: var PhysicalDevice): PhysicalDevice {.discardable.} =
  #  Try to find 1 Vulkan supported device
  #  NOTE: perhaps refactor to loop through devices and find first one that supports all required features and extensions
  if instance[].enumerate(physicalDevice) notin [success, incomplete]:
    quit "enumerating physical devices failed!"
  echo "physical device with vulkan support found"

  #  Check device features
  #  NOTE: will apiVersion >= appInfo.apiVersion? Probably yes, but spec is unclear.
  var deviceProperties: PhysicalDeviceProperties
  var deviceFeatures: PhysicalDeviceFeatures
  physicalDevice.getPhysicalDeviceProperties(addr deviceProperties)
  physicalDevice.getPhysicalDeviceFeatures(addr deviceFeatures)

  let supportedVersion = [
    apiVersionMajor(deviceProperties.apiVersion),
    apiVersionMinor(deviceProperties.apiVersion),
    apiVersionPatch(deviceProperties.apiVersion)
  ]

  echo "physical device supports version ", supportedVersion[0], ".", supportedVersion[1], ".", supportedVersion[2]
  physicalDevice

proc checkSwapChainSupport(physicalDevice: PhysicalDevice): PhysicalDevice =
  result = physicalDevice
  var deviceExtensionProperties: seq[ExtensionProperties]
  physicalDevice.enumerate(deviceExtensionProperties)
  if deviceExtensionProperties.len == 0:
    quit "physical device doesn't support any extensions"

  if deviceExtensionProperties.searchIt($it.extensionName.cstr == KhrSwapchainExtensionName).isSome:
    echo "physical device supports swap chains"
  else:
    quit "physical device doesn't support swap chains"

proc find(physicalDevice: PhysicalDevice; graphicsQueueFamily, presentQueueFamily: var uint32): PhysicalDevice =
  result = physicalDevice
  #  Check queue families
  var queueFamilyCount: uint32
  physicalDevice.getPhysicalDeviceQueueFamilyProperties(addr queueFamilyCount)

  if queueFamilyCount == 0:
    quit "physical device has no queue families!"

  #  Find queue family with graphics support
  #  NOTE: is a transfer queue necessary to copy vertices to the gpu or can a graphics queue handle that?
  var queueFamilies = newSeq[QueueFamilyProperties](queueFamilyCount)
  physicalDevice.getPhysicalDeviceQueueFamilyProperties(addr queueFamilyCount, addr queueFamilies[0])

  echo "physical device has ", queueFamilyCount, " queue families"

  var foundGraphicsQueueFamily: bool
  var foundPresentQueueFamily: bool

  for i in 0'u32..<queueFamilyCount:
    var presentSupport: Bool32
    discard physicalDevice.getPhysicalDeviceSurfaceSupportKHR(i, surface[], addr presentSupport)

    if queueFamilies[i].queueCount > 0 and QueueFlagBits.graphics in queueFamilies[i].queueFlags:
      graphicsQueueFamily = i
      foundGraphicsQueueFamily = true

      if presentSupport == Bool32.true:
        presentQueueFamily = i
        foundPresentQueueFamily = true
        break

    if not foundPresentQueueFamily and presentSupport == Bool32.true:
      presentQueueFamily = i
      foundPresentQueueFamily = true

  if foundGraphicsQueueFamily:
    echo "queue family #", graphicsQueueFamily, " supports graphics"

    if foundPresentQueueFamily:
      echo "queue family #", presentQueueFamily, " supports presentation" else: quit "could not find a valid queue family with present support"
  else:
    quit "could not find a valid queue family with graphics support"

proc create(physicalDevice: PhysicalDevice; device: var Uniq[Device]; graphicsQueueFamily, presentQueueFamily: uint32) =
  #  Greate one graphics queue and optionally a separate presentation queue
  var queuePriority = 1'f32

  let queueCI = [
    DeviceQueueCreateInfo{
      queueFamilyIndex: graphicsQueueFamily,
      queueCount: 1,
      pQueuePriorities: addr queuePriority,},
    DeviceQueueCreateInfo{
      queueFamilyIndex: presentQueueFamily,
      queueCount: 1,
      pQueuePriorities: addr queuePriority,},]

  #  Create logical device from physical device
  #  NOTE: there are separate instance and device extensions!
  var deviceCI = DeviceCreateInfo{
    pQueueCreateInfos: unsafeAddr queueCI[0],
    queueCreateInfoCount:
      if graphicsQueueFamily == presentQueueFamily: 1
      else:                                         2}


  #  Necessary for shader (for some reason)
  var enabledFeatures = PhysicalDeviceFeatures(
    shaderClipDistance: Bool32.true,
    shaderCullDistance: Bool32.true,
  )

  var deviceExtensions = [KhrSwapchainExtensionName]
  deviceCI.enabledExtensionCount = 1
  deviceCI.ppEnabledExtensionNames = deviceExtensions.allocCStringArray
  deviceCI.pEnabledFeatures = addr enabledFeatures

  when enableValidationLayers:
    deviceCI.enabledLayerCount = 1
    deviceCI.ppEnabledLayerNames = debugLayer.allocCStringArray

  if physicalDevice.create(device, deviceCI) != success:
    quit "failed to create logical device"

  #  Get graphics and presentation queues (which may be the same)
  device[].getDeviceQueue(graphicsQueueFamily, 0, addr graphicsQueue)
  device[].getDeviceQueue(presentQueueFamily, 0, addr presentQueue)

  echo "acquired graphics and presentation queues"

  physicalDevice.getPhysicalDeviceMemoryProperties(addr deviceMemoryProperties)

proc createCommandPool =
  #  Create graphics command pool
  var commandPoolCI = CommandPoolCreateInfo{
    queueFamilyIndex: graphicsQueueFamily,}

  if device.create(commandPool, commandPoolCI) != success:
    quit "failed to create command queue for graphics queue family"

proc createVertexBuffer =
  #  Setup vertices
  let vertices = [
    Vertex(pos: vec [-0.5f32, -0.5,  0], color: HEX"FF0000"),
    Vertex(pos: vec [ 0.5f32,  0.5,  0], color: HEX"00FF00"),
    Vertex(pos: vec [-0.5f32,  0.5,  0], color: HEX"0000FF"),
  ] #  Setup indices
  let indices = [0u32, 1, 2]

  var stagingBuffers: tuple[ vertices, indices: BufferMemory]

  block VertexStaging:
    #  First copy vertices to host accessible vertex buffer memory
    var bufferCI = BufferCreateInfo{
      size: DeviceSize vertices.len * sizeof Vertex,
      usage: BufferUsageFlags{transferSrc},
      sharingMode: SharingMode.exclusive,}

    device.allocate(stagingBuffers.vertices, bufferCI, MemoryPropertyFlagBits.hostVisible)
    stagingBuffers.vertices.memory.sendData unsafeAddr vertices

    #  Then allocate a gpu only buffer for vertices
    bufferCI.usage = BufferUsageFlags{vertexBuffer, transferDst}
    device.allocate(vertexSource, bufferCI, MemoryPropertyFlagBits.deviceLocal)

  block IndexStaging:
    #  Next copy indices to host accessible index buffer memory
    var bufferCI = BufferCreateInfo{
      size: DeviceSize indices.len * sizeof uint32,
      usage: BufferUsageFlags{transferSrc},
      sharingMode: SharingMode.exclusive,}

    device.allocate(stagingBuffers.indices, bufferCI, MemoryPropertyFlagBits.hostVisible)
    stagingBuffers.indices.memory.sendData unsafeAddr indices

    #  And allocate another gpu only buffer for indices
    bufferCI.usage = BufferUsageFlags{ indexBuffer, transferDst }
    device.allocate(indexSource, bufferCI, MemoryPropertyFlagBits.deviceLocal)

  #  Allocate command buffer for copy operation
  var copyCommandBuffer: CommandBuffer
  var cmdBufAI = CommandBufferAllocateInfo{
    commandPool: commandPool[],
    level: primary,
    commandBufferCount: 1,}
  discard device[].allocateCommandBuffers(addr cmdBufAI, addr copyCommandBuffer)

  #  Now copy data from host visible buffer to gpu only buffer
  var bufferBeginInfo = CommandBufferBeginInfo{
    flags: CommandBufferUsageFlags{oneTimeSubmit} }

  discard copyCommandBuffer.beginCommandBuffer(addr bufferBeginInfo)
  copyCommandBuffer.cmdCopyBuffer(stagingBuffers.vertices, vertexSource)
  copyCommandBuffer.cmdCopyBuffer(stagingBuffers.indices, indexSource)
  discard copyCommandBuffer.endCommandBuffer

  #  Submit to queue
  var submitInfo = SubmitInfo{
    commandBufferCount: 1,
    pCommandBuffers: addr copyCommandBuffer,}

  discard graphicsQueue.queueSubmit(1, addr submitInfo)
  discard queueWaitIdle graphicsQueue
  device[].freeCommandBuffers(commandPool[], 1, addr copyCommandBuffer)

  echo "set up vertex and index buffers"

  #  Binding and attribute descriptions
  Vertex.sign vertexBindingDescription
  Vertex.sign vertexAttributeDescriptions

proc createUniformBuffer =
  var bufferCI = BufferCreateInfo{
    size: DeviceSize sizeof uniform.data,
    usage: BufferUsageFlags{uniformBuffer},
    sharingMode: SharingMode.exclusive,}

  device.allocate(uniform.handle, bufferCI, MemoryPropertyFlagBits.hostVisible)

  updateUniformData()

proc createSwapChain =
  #  Find surface capabilities
  var surfaceCapabilities: SurfaceCapabilitiesKHR
  if physicalDevice.getPhysicalDeviceSurfaceCapabilitiesKHR(surface[], addr surfaceCapabilities) != success:
    quit "failed to acquire presentation surface capabilities"

  #  Find supported surface formats
  var formatCount: uint32
  if physicalDevice.getPhysicalDeviceSurfaceFormatsKHR(surface[], addr formatCount) != success or formatCount == 0:
    quit "failed to get number of supported surface formats"

  var surfaceFormats = newSeq[SurfaceFormatKHR](formatCount)
  if physicalDevice.getPhysicalDeviceSurfaceFormatsKHR(surface[], addr formatCount, addr surfaceFormats[0]) != success:
    quit "failed to get supported surface formats"

  #  Find supported present modes
  var presentModeCount: uint32
  if physicalDevice.getPhysicalDeviceSurfacePresentModesKHR(surface[], addr presentModeCount) != success or presentModeCount == 0:
    quit "failed to get number of supported presentation modes"

  var presentModes = newSeq[PresentModeKHR](presentModeCount)
  if physicalDevice.getPhysicalDeviceSurfacePresentModesKHR(surface[], addr presentModeCount, addr presentModes[0]) != success:
    quit "failed to get supported presentation modes"

  #  Determine number of images for swap chain
  var imageCount: uint32 = surfaceCapabilities.minImageCount + 1
  if surfaceCapabilities.maxImageCount != 0 and imageCount > surfaceCapabilities.maxImageCount:
    imageCount = surfaceCapabilities.maxImageCount

  echo "using ", imageCount, " images for swap chain"

  #  Select a surface format
  var surfaceFormat = chooseSurfaceFormat(surfaceFormats)

  #  Select swap chain size
  swapchainInfo.extent = chooseSwapExtent(addr surfaceCapabilities)
  camera.aspect = swapchainInfo.extent.aspect

  #  Determine transformation to use (preferring no transform)
  var surfaceTransform =
    if SurfaceTransformFlagBitsKHR.identityKHR in surfaceCapabilities.supportedTransforms:
      SurfaceTransformFlagBitsKHR.identityKHR
    else:
      surfaceCapabilities.currentTransform

  #  Choose presentation mode (preferring MAILBOX ~= triple buffering)
  var presentMode = choosePresentMode(presentModes)

  #  Finally, create the swap chain
  var swapchainCI = SwapchainCreateInfoKHR{
    surface: surface[],
    minImageCount: imageCount,
    imageFormat: surfaceFormat.format,
    imageColorSpace: surfaceFormat.colorSpace,
    imageExtent: swapchainInfo.extent,
    imageArrayLayers: 1,
    imageUsage: ImageUsageFlags{colorAttachment},
    imageSharingMode: SharingMode.exclusive,
    queueFamilyIndexCount: 0,
    pQueueFamilyIndices: nil,
    preTransform: surfaceTransform,
    compositeAlpha: CompositeAlphaFlagBitsKHR.opaqueKHR,
    presentMode: presentMode,
    clipped: Bool32.true,
    oldSwapchain: try: swapchain[] except HandleNotAliveDefect: SwapchainKHR.none,}

  if device.create(swapchain, swapchainCI) != success:
    quit "failed to create swap chain"

  swapchainInfo.format = surfaceFormat.format

  #  Store the images used by the swap chain
  #  NOTE: these are the images that swap chain image indices refer to
  #  NOTE: actual number of images may differ from requested number, since it's a lower bound
  var actualImageCount: uint32
  if device[].getSwapchainImagesKHR(swapchain[], addr actualImageCount) != success or actualImageCount == 0:
    quit "failed to acquire number of swap chain images"

  swapchainInfo.images.setLen(actualImageCount)

  if device[].getSwapchainImagesKHR(swapchain[], addr actualImageCount, addr swapchainInfo.images[0]) != success:
    quit "failed to acquire swap chain images"

  echo "acquired swap chain images"

proc createRenderPass =
  var attachmentDescription = AttachmentDescription{
    format: swapchainInfo.format,
    samples: SampleCountFlagBits.e1, loadOp: AttachmentLoadOp.clear,
    storeOp: AttachmentStoreOp.store,
    stencilLoadOp: AttachmentLoadOp.dontCare,
    stencilStoreOp: AttachmentStoreOp.dontCare,
    initialLayout: ImageLayout.presentSrcKHR,
    finalLayout: ImageLayout.presentSrcKHR,}

  #  NOTE: hardware will automatically transition attachment to the specified layout
  #  NOTE: index refers to attachment descriptions array
  var colorAttachmentReference = AttachmentReference{
    attachment: 0,
    layout: ImageLayout.colorAttachmentOptimal,}

  #  NOTE: this is a description of how the attachments of the render pass will be used in this sub pass
  #  e.g. if they will be read in shaders and/or drawn to
  var subPassDescription = SubpassDescription{
    pipelineBindPoint: PipelineBindPoint.graphics,
    colorAttachmentCount: 1,
    pColorAttachments: addr colorAttachmentReference,}

  #  Create the render pass
  var renderPassCI = RenderPassCreateInfo{
    attachmentCount: 1,
    pAttachments: addr attachmentDescription,
    subpassCount: 1,
    pSubpasses: addr subPassDescription,}

  if device.create(renderPass, renderPassCI) != success:
    quit "failed to create render pass"

proc createImageViews =
  swapchainInfo.imageViews.setLen(swapchainInfo.images.len)

  var swapchainCI = ImageViewCreateInfo{
    viewType: ImageViewType.e2D,
    image: Image.none,
    format: swapchainInfo.format,
    components: ComponentMapping(),
    subresourceRange: ImageSubresourceRange(
      aspectMask: ImageAspectFlags{coLor},
      baseMipLevel: 0,
      levelCount: 1,
      baseArrayLayer: 0,
      layerCount: 1),}

  #  Create an image view for every image in the swap chain
  for i in 0..<swapchainInfo.images.len:
    swapchainCI.image = swapchainInfo.images[i]

    if device.create(swapchainInfo.imageViews[i], swapchainCI) != success:
      quit "failed to create image view for swap chain image #" & $i

  echo "created image views for swap chain images"

proc createFramebuffers =
  swapchainInfo.framebuffers.setLen(swapchainInfo.images.len)

  #  NOTE: Framebuffer is basically a specific choice of attachments for a render pass
  #  That means all attachments must have the same dimensions, interesting restriction
  for i in 0..<swapchainInfo.images.len:
    var frameBufferCI = FramebufferCreateInfo{
      renderPass: renderPass[],
      attachmentCount: 1,
      pAttachments: unsafeAddr swapchainInfo.imageViews[i][],
      width: swapchainInfo.extent.width,
      height: swapchainInfo.extent.height,
      layers: 1,}

    if device.create(swapchainInfo.framebuffers[i], frameBufferCI) != success:
      quit "failed to create framebuffer for swap chain image view #" & $i

  echo "created framebuffers for swap chain image views"

proc createShaderModule(shader: var Uniq[ShaderModule]; filename: string): Result =
  var shadersrc =
    if filename.fileExists: filename.readFile
    else: quit filename & " is not exists!"

  var shaderModuleCI = ShaderModuleCreateInfo{
    codeSize: uint32 shadersrc.len,
    pCode: cast[ptr uint32](addr shadersrc[0]),}

  result = device.create(shader, shaderModuleCI)
  if result == success:
    echo "created shader module for ", filename
  else:
    quit "failed to create shader module for " & filename & " code: " & $result


proc createGraphicsPipeline =

  #  Set up shader stage info

  var
    vertshader, fragshader: Uniq[ShaderModule]

  discard createShaderModule(vertshader, "shaders/vert.spv")
  discard createShaderModule(fragshader, "shaders/frag.spv")
  var shaderStages = [
    PipelineShaderStageCreateInfo{
      stage: ShaderStageFlagBits.vertex,
      module: vertshader[],
      pName: "main",},
    PipelineShaderStageCreateInfo{
      stage: ShaderStageFlagBits.fragment,
      module: fragshader[],
      pName: "main",},]

  #  Describe vertex input
  var vertexInputCreateInfo = PipelineVertexInputStateCreateInfo{
    vertexBindingDescriptionCount: 1,
    pVertexBindingDescriptions: addr vertexBindingDescription,
    vertexAttributeDescriptionCount: uint32 vertexAttributeDescriptions.len,
    pVertexAttributeDescriptions: addr vertexAttributeDescriptions[0],}

  #  Describe input assembly
  var inputAssemblyCreateInfo = PipelineInputAssemblyStateCreateInfo{
    topology: PrimitiveTopology.triangleList,
    primitiveRestartEnable: Bool32.false,}

  #  Describe viewport and scissor
  var viewport = Viewport{
    x: 0,
    y: 0,
    width: float32 swapchainInfo.extent.width,
    height: float32 swapchainInfo.extent.height,
    minDepth: 0,
    maxDepth: 1,}

  var scissor = Rect2D{
    offset: Offset2D(x: 0, y: 0),
    extent: swapchainInfo.extent,}

  #  NOTE: scissor test is always enabled (although dynamic scissor is possible)
  #  Number of viewports must match number of scissors
  var viewportCreateInfo = PipelineViewportStateCreateInfo{
    viewportCount: 1,
    pViewports: addr viewport,
    scissorCount: 1,
    pScissors: addr scissor,}

  #  Describe rasterization
  #  NOTE: depth bias and using polygon modes other than fill require changes to logical device creation (device features)
  var rasterizationCreateInfo = PipelineRasterizationStateCreateInfo{
    depthClampEnable: Bool32.false,
    rasterizerDiscardEnable: Bool32.false,
    polygonMode: PolygonMode.fill,
    cullMode: CullModeFlags{back},
    frontFace: FrontFace.counterClockwise,
    depthBiasEnable: Bool32.false,
    depthBiasConstantFactor: 0.0f,
    depthBiasClamp: 0.0f,
    depthBiasSlopeFactor: 0.0f,
    lineWidth: 1.0f,}

  #  Describe multisampling
  #  NOTE: using multisampling also requires turning on device features
  var multisampleCreateInfo = PipelineMultisampleStateCreateInfo{
    rasterizationSamples: SampleCountFlagBits.e1,
    sampleShadingEnable: Bool32.false,
    minSampleShading: 1.0f,
    alphaToCoverageEnable: Bool32.false,
    alphaToOneEnable: Bool32.false,}

  #  Describing color blending
  #  NOTE: all paramaters except blendEnable and colorWriteMask are irrelevant here
  var colorBlendAttachmentState = PipelineColorBlendAttachmentState{
    blendEnable: Bool32.false,
    srcColorBlendFactor: BlendFactor.one,
    dstColorBlendFactor: BlendFactor.zero,
    colorBlendOp: BlendOp.add,
    srcAlphaBlendFactor: BlendFactor.one,
    dstAlphaBlendFactor: BlendFactor.zero,
    alphaBlendOp: BlendOp.add,
    colorWriteMask: ColorComponentFlags{r, g, b, a},}

  #  NOTE: all attachments must have the same values unless a device feature is enabled
  var colorBlendCreateInfo = PipelineColorBlendStateCreateInfo{
    logicOpEnable: Bool32.false,
    logicOp: LogicOp.copy,
    attachmentCount: 1,
    pAttachments: addr colorBlendAttachmentState,
    blendConstants: [0f32, 0, 0, 0],}

  #  Describe pipeline layout
  #  NOTE: this describes the mapping between memory and shader resources (descriptor sets)
  #  This is for uniform buffers and samplers
  var layoutBinding = DescriptorSetLayoutBinding{
    descriptorType: DescriptorType.uniformBuffer,
    descriptorCount: 1,
    stageFlags: ShaderStageFlags{vertex},
    binding: 0,}

  var descriptorSetLayoutCI = DescriptorSetLayoutCreateInfo{
    bindingCount: 1,
    pBindings: addr layoutBinding,}

  if device.create(descriptorSetLayout, descriptorSetLayoutCI) != success:
    quit "failed to create descriptor layout"

  var pipelineLayoutCI = PipelineLayoutCreateInfo{
    setLayoutCount: 1,
    pSetLayouts: unsafeAddr descriptorSetLayout[],}

  if device.create(pipelineLayout, pipelineLayoutCI) != success:
    quit "failed to create pipeline layout"

  #  Create the graphics pipeline
  var pipelineCreateInfo = GraphicsPipelineCreateInfo{
    stageCount: 2,
    pStages: addr shaderStages[0],
    pVertexInputState: addr vertexInputCreateInfo,
    pInputAssemblyState: addr inputAssemblyCreateInfo,
    pViewportState: addr viewportCreateInfo,
    pRasterizationState: addr rasterizationCreateInfo,
    pMultisampleState: addr multisampleCreateInfo,
    pColorBlendState: addr colorBlendCreateInfo,
    layout: pipelineLayout[],
    renderPass: renderPass[],
    subpass: 0,
    basePipelineHandle: Pipeline.none,
    basePipelineIndex: -1,}

  var res = device[].createGraphicsPipelines(PipelineCache.none, 1, addr pipelineCreateInfo, nil, addr graphicsPipeline)
  if res != success:
    quit "failed to create graphics pipeline. code: " & $res
  else:
    echo "created graphics pipeline"

proc createDescriptorPool =
  #  This describes how many descriptor sets we'll create from this pool for each type
  var typeCount = DescriptorPoolSize(
    thetype: DescriptorType.uniformBuffer,
    descriptorCount: 1,)

  var descriptorPoolCI = DescriptorPoolCreateInfo{
    poolSizeCount: 1,
    pPoolSizes: addr typeCount,
    maxSets: 1,}

  if device.create(descriptorPool, descriptorPoolCI) != success:
    quit "failed to create descriptor pool"

proc createDescriptorSet =
  #  There needs to be one descriptor set per binding point in the shader
  var allocInfo = DescriptorSetAllocateInfo{
    descriptorPool: descriptorPool[],
    descriptorSetCount: 1,
    pSetLayouts: unsafeAddr descriptorSetLayout[],}

  if device[].allocateDescriptorSets(addr allocInfo, addr descriptorSet) != success:
    quit "failed to create descriptor set"
  else:
    echo "created descriptor set"

  #  Update descriptor set with uniform binding
  var descriptorBufferInfo = DescriptorBufferInfo{
    buffer: uniform.handle.buffer[],
    offset: DeviceSize 0,
    range: DeviceSize sizeof uniform.data,}

  var writeDescriptorSet = WriteDescriptorSet{
    dstSet: descriptorSet,
    descriptorCount: 1,
    descriptorType: DescriptorType.uniformBuffer,
    pBufferInfo: addr descriptorBufferInfo,
    dstBinding: 0,
    dstArrayElement: 0,
    pImageInfo: nil,
    pTexelBufferView: nil,}

  device[].updateDescriptorSets(1, addr writeDescriptorSet, 0, nil)

proc createCommandBuffers =
  #  Allocate graphics command buffers
  graphicsCommandBuffers.setLen(swapchainInfo.images.len)

  var allocInfo = CommandBufferAllocateInfo{
    commandPool: commandPool[],
    level: CommandBufferLevel.primary,
    commandBufferCount: uint32 swapchainInfo.images.len,}

  if device[].allocateCommandBuffers(addr allocInfo, addr graphicsCommandBuffers[0]) != success:
    quit "failed to allocate graphics command buffers"
  else:
    echo "allocated graphics command buffers"

  #  Prepare data for recording command buffers
  var beginInfo = CommandBufferBeginInfo{
    flags: CommandBufferUsageFlags{simultaneousUse},}

  var subResourceRange = ImageSubresourceRange{
  aspectMask: ImageAspectFlags{color},
  baseMipLevel: 0,
  levelCount: 1,
  baseArrayLayer: 0,
  layerCount: 1 }

  var clearColor = ClearValue( color:
    ClearColorValue(float32: [0.1f, 0.1f, 0.1f, 1.0f]) #  R, G, B, A
  )

  #  Record command buffer for each swap image
  for i, commandBuffer in graphicsCommandBuffers:
    #  If present queue family and graphics queue family are different, then a barrier is necessary
    #  The barrier is also needed initially to transition the image to the present layout
    var barrier = (
      presentToDraw: ImageMemoryBarrier{
        srcAccessMask: AccessFlags{noneKHR},
        dstAccessMask: AccessFlags{colorAttachmentWrite},
        oldLayout: ImageLayout.undefined,
        newLayout: ImageLayout.presentSrcKHR,
        srcQueueFamilyIndex:
          if presentQueueFamily != graphicsQueueFamily: QueueFamilyIgnored
          else:                                         presentQueueFamily,
        dstQueueFamilyIndex:
          if presentQueueFamily != graphicsQueueFamily: QueueFamilyIgnored
          else:                                         graphicsQueueFamily,
        image: swapchainInfo.images[i],
        subresourceRange: subresourceRange,},
    )

    var renderPassBeginInfo = RenderPassBeginInfo{
      renderPass: renderPass[],
      framebuffer: swapchainInfo.framebuffers[i][],
      renderArea: Rect2D(
        offset: Offset2D(x: 0, y: 0),
        extent: swapchainInfo.extent,),
      clearValueCount: 1,
      pClearValues: addr clearColor,}

    var offset: DeviceSize

    discard commandBuffer.beginCommandBuffer(addr beginInfo)
    commandBuffer.cmdPipelineBarrier(
      PipelineStageFlags{colorAttachmentOutput},
      PipelineStageFlags{colorAttachmentOutput},
      DependencyFlags.none, 0, nil, 0, nil, 1, addr barrier.presentToDraw)
    commandBuffer.cmdBeginRenderPass(addr renderPassBeginInfo, SubpassContents.inline)
    commandBuffer.cmdBindDescriptorSets(PipelineBindPoint.graphics, pipelineLayout[], 0, 1, addr descriptorSet, 0, nil)
    commandBuffer.cmdBindPipeline(PipelineBindPoint.graphics, graphicsPipeline)
    commandBuffer.cmdBindVertexBuffers(0, 1, unsafeAddr vertexSource.buffer[], addr offset)
    commandBuffer.cmdBindIndexBuffer(indexSource.buffer[], DeviceSize(0), IndexType.uint32)
    commandBuffer.cmdDrawIndexed(3, 1, 0, 0, 0)
    commandBuffer.cmdEndRenderPass

    #  If present and graphics queue families differ, then another barrier is required
    if presentQueueFamily != graphicsQueueFamily:
      var drawToPresentBarrier = ImageMemoryBarrier{
        srcAccessMask: AccessFlags{colorAttachmentWrite},
        dstAccessMask: AccessFlags{memoryRead},
        oldLayout: ImageLayout.presentSrcKHR,
        newLayout: ImageLayout.presentSrcKHR,
        srcQueueFamilyIndex: graphicsQueueFamily,
        dstQueueFamilyIndex: presentQueueFamily,
        image: swapchainInfo.images[i],
        subresourceRange: subResourceRange }

      commandBuffer.cmdPipelineBarrier(
        PipelineStageFlags{colorAttachmentOutput},
        PipelineStageFlags{bottomOfPipe},
        DependencyFlags.none, 0, nil, 0, nil, 1, addr drawToPresentBarrier)

    try: discard commandBuffer.endCommandBuffer
    except: quit "failed to record command buffer"

  echo "recorded command buffers"

  #  No longer needed
  destroy pipelineLayout

proc cleanRenderer =
  discard device[].deviceWaitIdle

  device[].freeCommandBuffers(commandPool[], graphicsCommandBuffers.len.uint32, addr graphicsCommandBuffers[0])

  device[].destroyPipeline(graphicsPipeline)
  destroy renderPass

  for i in 0..<swapchainInfo.images.len:
    destroy swapchainInfo.framebuffers[i]
    destroy swapchainInfo.imageViews[i]

  destroy descriptorSetLayout

proc setupVulkan =
  create(instance)
    .loadAppCommands
    .create(messenger)
    .create(surface, targetWindow= window)
    .find(physicalDevice)
      .checkSwapChainSupport
      .find(graphicsQueueFamily, presentQueueFamily)
      .create(device, graphicsQueueFamily, presentQueueFamily)
  block:
    let CI = SemaphoreCreateInfo{}
    if  device.create(semaphore.imageAvailable, CI) != success or
        device.create(semaphore.renderingFinished, CI) != success:
      quit "failed to create semaphores"
  createCommandPool()
  createVertexBuffer()
  createSwapChain()
  createUniformBuffer()
  createRenderPass()
  createImageViews()
  createFramebuffers()
  createGraphicsPipeline()
  createDescriptorPool()
  createDescriptorSet()
  createCommandBuffers()

proc onWindowSizeChanged =
  windowResized = false

  #  Only recreate objects that are affected by framebuffer size changes
  cleanRenderer()

  createSwapChain()
  createRenderPass()
  createImageViews()
  createFramebuffers()
  createGraphicsPipeline()
  createCommandBuffers()

  matrices.proj.needsUpdate = true


proc processio =
  if window.getKey(Key.Escape) == KeyStat.Press:
    window.setWindowShouldClose(true)
  let axisws =
    float(window.getKey(Key.W) == KeyStat.Press) -
    float(window.getKey(Key.S) == KeyStat.Press)
  let axisda =
    float(window.getKey(Key.D) == KeyStat.Press) -
    float(window.getKey(Key.A) == KeyStat.Press)
  let axiseq =
    float(window.getKey(Key.E) == KeyStat.Press) -
    float(window.getKey(Key.Q) == KeyStat.Press)
  if axisws != 0:
    camera.coord.moveFront(0.1*axisws)
    matrices.view.needsUpdate = true
  if axisda != 0:
    camera.coord.moveRight(0.1*axisda)
    matrices.view.needsUpdate = true
  if axiseq != 0:
    camera.coord.moveZ(0.1*axiseq)
    matrices.view.needsUpdate = true

  swap mousePos.last, mousePos.current
  window.getCursorPos(addr mousePos.current.x, addr mousePos.current.y)
  # window.setCursorPos(swapchain.extent.width.float/2, swapchain.extent.height.float/2)
  mousePos.delta = mousePos.current - mousePos.last

  if mousePos.delta.x != 0:
    camera.coord.rotateZ(-0.005 * mousePos.delta.x.rad32)
    matrices.view.needsUpdate = true
  if mousePos.delta.y != 0:
    camera.coord.pitch(-0.005 * mousePos.delta.y.rad32)
    matrices.view.needsUpdate = true


  if window.getKey(Key.Space) == KeyStat.Press:
    clear modelCoord
    clear camera.coord
    camera.coord.point 0, -3, 1
    matrices.view.needsUpdate = true


proc draw =
  #  Acquire image
  var imageIndex: uint32
  var res = device[].acquireNextImageKHR(swapchain[], uint64.high, semaphore.imageAvailable[], Fence.none, addr imageIndex)

  #  Unless surface is out of date right now, defer swap chain recreation until end of this frame
  if res == errorOutOfDateKHR:
    onWindowSizeChanged()
    return
  elif res != success:
    quit "failed to acquire image"

  #  This is the stage where the queue should wait on the semaphore
  var waitDstStageMask = PipelineStageFlags{topOfPipe}

  #  Wait for image to be available and draw
  var submitInfo = SubmitInfo{
    waitSemaphoreCount: 1,
    pWaitSemaphores: unsafeAddr semaphore.imageAvailable[],

    signalSemaphoreCount: 1,
    pSignalSemaphores: unsafeAddr semaphore.renderingFinished[],

    pWaitDstStageMask: addr waitDstStageMask,

    commandBufferCount: 1,
    pCommandBuffers: addr graphicsCommandBuffers[imageIndex],
  }

  if graphicsQueue.queueSubmit(1, addr submitInfo) != success:
    quit "failed to submit draw command buffer"

  #  Present drawn image
  #  NOTE: semaphore here is not strictly necessary, because commands are processed in submission order within a single queue
  var presentInfo = PresentInfoKHR{
    waitSemaphoreCount: 1,
    pWaitSemaphores: unsafeAddr semaphore.renderingFinished[],

    swapchainCount: 1,
    pSwapchains: unsafeAddr swapchain[],
    pImageIndices: addr imageIndex,
  }

  res = presentQueue.queuePresentKHR(addr presentInfo)

  if windowResized or res in [suboptimalKHR, errorOutOfDateKHR]:
    onWindowSizeChanged()
  elif res != success:
    quit "failed to submit present command buffer."

proc mainLoop =
  while not window.windowShouldClose:
    processio()
    updateUniformData()
    draw()

    glfwPollEvents()

when isMainModule:
  #  Create window for Vulkan
  discard glfwInit()
  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
  window = glfwCreateWindow(winsz.width.int32, winsz.height.int32, "The triangle and movable camera that took 1154 lines of code with safetyhandles")
  if window == nil:
    glfwTerminate()
    quit(QuitFailure)
  discard window.setWindowSizeCallback onWindowResized
  window.setInputMode GLFWCursorSpecial, GLFWCursorDisabled

  #  Use Vulkan
  setupVulkan()
  mainLoop()
  cleanRenderer()