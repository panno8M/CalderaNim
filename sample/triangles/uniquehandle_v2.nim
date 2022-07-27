import std/options
import std/sugar
import std/strformat
import std/macros
from std/os import fileExists

import vkfw
import caldera
import caldera/safetyhandles {.all.}

type
  BufferMemory = object
    memory: Uniq[DeviceMemory]
    buffer: Uniq[Buffer]
    size: DeviceSize

  SwapchainInfo = object
    extent: Extent2D
    format: Format
    images: Weak[seq[Image]]

  RenderingInstance = object
    graphicsCommandBuffers: Uniq[seq[ClCommandBuffer[QueueFlags{graphics}, primary]]]
    graphicsPipeline: Uniq[Pipeline]
    renderPass: Uniq[RenderPass]
    swapchainImageViews: seq[Uniq[ImageView]]
    swapchainFramebuffers: seq[Uniq[Framebuffer]]
    swapchainInfo: SwapchainInfo
    swapchain: Uniq[SwapchainKHR]

  QueueFamilies = object
    case sharingMode: SharingMode
    of SharingMode.exclusive:
      both: Uniq[QueueFamily[QueueFlags{graphics}]]
    of SharingMode.concurrent:
      graphics: Uniq[QueueFamily[QueueFlags{graphics}]]
      present: Uniq[QueueFamily[QueueFlags{}]]

  MousePos = object
    last: array[2,float]
    current: array[2,float]
    frame: range[0..2]

  UniformMVP = object
    deviceMemory: BufferMemory
    data: tuple[
      transformationMatrix: Mat[4,4,float32]
    ]

var
  window: GLFWWindow
  instance: Uniq[Instance]
  device: Uniq[Device]
  queueFamilies: QueueFamilies
  messenger: Uniq[DebugUtilsMessengerEXT]
  surface: Uniq[SurfaceKHR]
  physicalDevice: PhysicalDevice
  graphicsQueue: ClQueue[QueueFlags{graphics}]
  presentQueue: ClQueue[QueueFlags{}]
  deviceMemoryProperties: PhysicalDeviceMemoryProperties
  semaphore: tuple[ imageAvailable, renderingFinished: Uniq[Semaphore]]
  vertexSource: BufferMemory
  indexSource: BufferMemory
  uniformMVP: UniformMVP
  descriptorPool: Uniq[DescriptorPool]
  descriptorSetLayout: tuple[
    uniformMVP: Uniq[DescriptorSetLayout]
  ]
  descriptorSet: tuple[
    uniformMVP: Uniq[DescriptorSet]
  ]
  pipelineLayout: Uniq[PipelineLayout]
  graphicsCommandPool: Uniq[ClCommandPool[QueueFlags{graphics}]]

var
  rendererShouldRecreate: bool
  mousePos: MousePos
  matrices = (
    view: (mat: mat4[float32](1), needsUpdate: true),
    proj: (mat: mat4[float32](1), needsUpdate: true),
  )

# Utilities
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

proc delta(mousePos: MousePos): array[2,float] =
  if mousePos.frame == 2:
    return mousePos.current - mousePos.last
proc update(window: GLFWWindow; mousePos: var MousePos) =
  if unlikely(mousePos.frame != 2): inc mousePos.frame
  swap mousePos.last, mousePos.current
  window.getCursorPos(addr mousePos.current.x, addr mousePos.current.y)

# NOTE: support swap chain recreation (not only required for resized windows!)
# NOTE: window resize may not result in Vulkan telling that the swap chain should be recreated, should be handled explicitly!
proc onWindowResized(window: GLFWWindow; width, height: int32) {.cdecl.} =
  rendererShouldRecreate = true

proc sendData[T](memory: Weak[DeviceMemory]; data: T) =
  var devicedata: pointer
  memory.map(DeviceSize(0), DeviceSize sizeof data, MemoryMapFlags.none, addr devicedata)
  copyMem(devicedata, unsafeAddr data, sizeof data)
  memory.unmap

#  Find device memory that is supported by the requirements (typeBits) and meets the desired properties
proc getMemoryType(typeBits: uint32; prop: MemoryPropertyFlagBits; props: PhysicalDeviceMemoryProperties): Option[uint32] =
  for i in 0'u32..<32:
    if (typebits and (1'u32 shl i)) == 0: continue
    if prop in props.memoryTypes[i].propertyFlags:
      return some i

proc allocate(device: Weak[Device]; sb: var BufferMemory; bufferCI: BufferCreateInfo; memProp: MemoryPropertyFlagBits) =
  device.create(sb.buffer, bufferCI)
  var memoryRequirements: MemoryRequirements
  sb.buffer.get memoryRequirements
  var memoryAI = MemoryAllocateInfo{
    allocationSize: memoryRequirements.size,
    memoryTypeIndex: getMemoryType(memoryRequirements.memoryTypeBits, memProp, deviceMemoryProperties).get(0)}
  device.create(sb.memory, memoryAI)
  discard device[].bindBufferMemory(sb.buffer[], sb.memory[], DeviceSize(0))
  sb.size = bufferCI.size

proc cmdCopyBuffer[QF,LV](commandBuffer: ClCommandBuffer[QF,LV]; src, dst: BufferMemory; regionCount: uint32; pRegions: arrPtr[BufferCopy]): lent typeof commandBuffer {.discardable.} =
  commandBuffer.cmdCopyBuffer(src.buffer[], dst.buffer[], regionCount, pRegions)
proc cmdCopyBuffer[QF,LV](commandBuffer: ClCommandBuffer[QF,LV]; src, dst: BufferMemory): lent typeof commandBuffer {.discardable.} =
  let region = BufferCopy(size: src.size)
  commandBuffer.cmdCopyBuffer(src, dst, 1'u32, unsafeAddr region)

proc chooseSurfaceFormat(availables: seq[SurfaceFormatKHR]): SurfaceFormatKHR =
  #  We can either choose any format
  if availables.len == 1 and availables[0].format == Format.undefined:
    return SurfaceFormatKHR{
      format: Format.r8g8b8a8Unorm,
      colorSpace: ColorspaceKHR.srgbNonlinearKHR,}

  #  Or go with the standard format - if available
  availables
    .searchIt(it.format == Format.r8g8b8a8Unorm)
    .get(availables[0])


proc chooseSwapExtent(default: Extent2D; surfaceCapabilities: ptr SurfaceCapabilitiesKHR): Extent2D =
  if surfaceCapabilities.currentExtent.width == uint32.high:
    default.clamp(
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
    vulkan.acquireNextImageKHR
    vulkan.queuePresentKHR

proc create(instance: Weak[Instance]; messenger: var Uniq[DebugUtilsMessengerEXT]): Weak[Instance] {.discardable.} =
  when not enableValidationLayers:
    echo "skipped creating debug callback"; return

  var debugUtilsMessengerCI = DebugUtilsMessengerCreateInfoEXT{
  messageSeverity: DebugUtilsMessageSeverityFlagsEXT{errorEXT, warningEXT},
  messageType: DebugUtilsMessageTypeFlagsEXT.all,
  pfnUserCallback: debugCallback,}

  if instance.create(messenger, debugUtilsMessengerCI) != success:
    quit "failed to create debug callback"
  instance

proc create(instance: Weak[Instance]; surface: var Uniq[SurfaceKHR]; targetWindow: GLFWWindow): Weak[Instance] {.discardable.} =
  if safetyhandles.create(instance, surface, targetWindow) != success:
    quit "failed to create window surface!"
  instance

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

  let apiver = deviceProperties.apiVersion
  echo &"physical device supports version {apiVer.major}.{apiVer.minor}.{apiVer.patch}"
  physicalDevice

proc checkSwapChainSupport(physicalDevice: PhysicalDevice): PhysicalDevice =
  result = physicalDevice
  var deviceExtensionProperties: seq[ExtensionProperties]
  physicalDevice.enumerate(deviceExtensionProperties)
  if deviceExtensionProperties.len == 0:
    quit "physical device doesn't support any extensions"

  if deviceExtensionProperties.searchIt($it.extensionName.cstr == KhrSwapchainExtensionName).isNone:
    quit "physical device doesn't support swap chains"
  echo "physical device supports swap chains"

proc find(physicalDevice: PhysicalDevice; graphicsQueueFamily, presentQueueFamily: var uint32): PhysicalDevice =
  #  Check queue families
  #  Find queue family with graphics support
  #  NOTE: is a transfer queue necessary to copy vertices to the gpu or can a graphics queue handle that?
  var queueFamilyProperties: seq[QueueFamilyProperties]
  physicalDevice.get queueFamilyProperties

  echo "physical device has ", queueFamilyProperties.len, " queue families"

  var foundGraphicsQueueFamily: bool
  var foundPresentQueueFamily: bool

  for i in 0'u32..<queueFamilyProperties.len.uint32:
    var presentSupport: Bool32
    discard physicalDevice.getPhysicalDeviceSurfaceSupportKHR(i, surface[], addr presentSupport)

    if queueFamilyProperties[i].queueCount > 0 and QueueFlagBits.graphics in queueFamilyProperties[i].queueFlags:
      graphicsQueueFamily = i
      foundGraphicsQueueFamily = true

      if presentSupport == Bool32.true:
        presentQueueFamily = i
        foundPresentQueueFamily = true
        break

    if not foundPresentQueueFamily and presentSupport == Bool32.true:
      presentQueueFamily = i
      foundPresentQueueFamily = true

  if not foundGraphicsQueueFamily:
    quit "could not find a valid queue family with graphics support"
  if not foundPresentQueueFamily:
    quit "could not find a valid queue family with present support"

  echo "queue family #", graphicsQueueFamily, " supports graphics"
  echo "queue family #", presentQueueFamily, " supports presentation"
  physicalDevice

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

  physicalDevice.getPhysicalDeviceMemoryProperties(addr deviceMemoryProperties)

proc createCommandPool =
  #  Create graphics command pool
  var commandPoolCI = ClCommandPoolCreateInfo{}
  let result =
    if queueFamilies.sharingMode == SharingMode.exclusive:
      queueFamilies.both.create(graphicsCommandPool, commandPoolCI)
    else:
      queueFamilies.graphics.create(graphicsCommandPool, commandPoolCI)
  if result != success:
    quit "failed to create command queue for graphics queue family"

proc createVertexBuffer =
  #  Setup vertices
  let vertices = [
    Vertex(pos: vec [-0.5f32, -0.5,  0], color: HEX"FF0000"),
    Vertex(pos: vec [ 0.5f32,  0.5,  0], color: HEX"00FF00"),
    Vertex(pos: vec [-0.5f32,  0.5,  0], color: HEX"0000FF"),
  ]
  #  Setup indices
  let indices = [0u32, 1, 2]
  var stagingBuffers: tuple[ vertices, indices: BufferMemory]
  var bufferCI = BufferCreateInfo(
    sType: StructureType.bufferCreateInfo,
    sharingMode: SharingMode.exclusive)

  block VertexStaging:
    #  First copy vertices to host accessible vertex buffer memory
    bufferCI.size = DeviceSize vertices.len * sizeof Vertex
    bufferCI.usage = BufferUsageFlags{transferSrc}

    device.allocate(stagingBuffers.vertices, bufferCI, MemoryPropertyFlagBits.hostVisible)
    stagingBuffers.vertices.memory.sendData vertices

    #  Then allocate a gpu only buffer for vertices
    bufferCI.usage = BufferUsageFlags{vertexBuffer, transferDst}
    device.allocate(vertexSource, bufferCI, MemoryPropertyFlagBits.deviceLocal)

  block IndexStaging:
    #  Next copy indices to host accessible index buffer memory
    bufferCI.size = DeviceSize indices.len * sizeof uint32
    bufferCI.usage = BufferUsageFlags{transferSrc}

    device.allocate(stagingBuffers.indices, bufferCI, MemoryPropertyFlagBits.hostVisible)
    stagingBuffers.indices.memory.sendData indices

    #  And allocate another gpu only buffer for indices
    bufferCI.usage = BufferUsageFlags{ indexBuffer, transferDst }
    device.allocate(indexSource, bufferCI, MemoryPropertyFlagBits.deviceLocal)

  #  Allocate command buffer for copy operation
  var copyCommandBuffer: Uniq[ClCommandBuffer[QueueFlags{graphics}, primary]]
  graphicsCommandPool.create(copyCommandBuffer, ClCommandBufferCreateInfo{})

  #  Now copy data from host visible buffer to gpu only buffer

  copyCommandBuffer[].begin CommandBufferBeginInfo{
    flags: CommandBufferUsageFlags{oneTimeSubmit} }
  copyCommandBuffer[]
    .cmdCopyBuffer(stagingBuffers.vertices, vertexSource)
    .cmdCopyBuffer(stagingBuffers.indices, indexSource)
  copyCommandBuffer[].end

  #  Submit to queue
  graphicsQueue.submit SubmitInfo{
    commandBufferCount: 1,
    pCommandBuffers: addr copyCommandBuffer[].downcast,}
  waitIdle graphicsQueue
  destroy copyCommandBuffer

  echo "set up vertex and index buffers"

proc createUniformBuffer =
  var bufferCI = BufferCreateInfo{
    size: DeviceSize sizeof uniformMVP.data,
    usage: BufferUsageFlags{uniformBuffer},
    sharingMode: SharingMode.exclusive,}

  device.allocate(uniformMVP.deviceMemory, bufferCI, MemoryPropertyFlagBits.hostVisible)

proc createSwapchain(renderer: var RenderingInstance; defaultWindowSize: Extent2D) =
  #  Find surface capabilities
  var surfaceCapabilities: SurfaceCapabilitiesKHR
  if physicalDevice.getPhysicalDeviceSurfaceCapabilitiesKHR(surface[], addr surfaceCapabilities) != success:
    quit "failed to acquire presentation surface capabilities"

  #  Find supported surface formats
  var surfaceFormats: seq[SurfaceFormatKHR]
  if physicalDevice.get(surfaceFormats, surface[]) != success:
    quit "failed to get supported surface formats"

  #  Find supported present modes
  var presentModes: seq[PresentModeKHR]
  if physicalDevice.get(presentModes, surface[]) != success:
    quit "failed to get supported presentation modes"

  #  Determine number of images for swap chain
  var imageCount: uint32 = surfaceCapabilities.minImageCount + 1
  if surfaceCapabilities.maxImageCount != 0 and imageCount > surfaceCapabilities.maxImageCount:
    imageCount = surfaceCapabilities.maxImageCount

  echo "using ", imageCount, " images for swap chain"

  #  Select a surface format
  var surfaceFormat = chooseSurfaceFormat(surfaceFormats)

  #  Select swap chain size
  renderer.swapchainInfo.extent = defaultWindowSize.chooseSwapExtent(addr surfaceCapabilities)

  #  Determine transformation to use (preferring no transform)
  var surfaceTransform =
    if SurfaceTransformFlagBitsKHR.identityKHR in surfaceCapabilities.supportedTransforms:
      SurfaceTransformFlagBitsKHR.identityKHR
    else:
      surfaceCapabilities.currentTransform

  #  Choose presentation mode (preferring MAILBOX ~= triple buffering)
  var presentMode = choosePresentMode(presentModes)

  #  Finally, create the swap chain
  let (queueFamilyIndexCount, pQueueFamilyIndices) =
    if queueFamilies.sharingMode == exclusive:
      (0'u32, nil)
    else:
      let queueFamilyIndices = [queueFamilies.graphics[].index.get, queueFamilies.present[].index.get]
      (2'u32, unsafeAddr queueFamilyIndices[0])
  var swapchainCI = SwapchainCreateInfoKHR{
    surface: surface[],
    minImageCount: imageCount,
    imageFormat: surfaceFormat.format,
    imageColorSpace: surfaceFormat.colorSpace,
    imageExtent: renderer.swapchainInfo.extent,
    imageArrayLayers: 1,
    imageUsage: ImageUsageFlags{colorAttachment},
    imageSharingMode: queueFamilies.sharingMode,
    queueFamilyIndexCount: queueFamilyIndexCount,
    pQueueFamilyIndices: pQueueFamilyIndices,
    preTransform: surfaceTransform,
    compositeAlpha: CompositeAlphaFlagBitsKHR.opaqueKHR,
    presentMode: presentMode,
    clipped: Bool32.true,
    oldSwapchain: try: renderer.swapchain[] except HandleNotAliveDefect: SwapchainKHR.none,}

  if device.create(renderer.swapchain, swapchainCI) != success:
    quit "failed to create swap chain"

  renderer.swapchainInfo.format = surfaceFormat.format

  #  Store the images used by the swap chain
  #  NOTE: these are the images that swap chain image indices refer to
  #  NOTE: actual number of images may differ from requested number, since it's a lower bound
  if renderer.swapchain.get(renderer.swapchainInfo.images) != success:
    quit "failed to acquire swap chain images"

proc createRenderPass(renderer: var RenderingInstance) =
  var attachmentDescription = AttachmentDescription{
    format: renderer.swapchainInfo.format,
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

  if device.create(renderer.renderPass, renderPassCI) != success:
    quit "failed to create render pass"

proc createImageViews(renderer: var RenderingInstance) =
  renderer.swapchainImageViews.setLen(renderer.swapchainInfo.images[].len)

  var imageViewCI = ImageViewCreateInfo{
    viewType: ImageViewType.e2D,
    image: Image.none,
    format: renderer.swapchainInfo.format,
    components: ComponentMapping(),
    subresourceRange: ImageSubresourceRange(
      aspectMask: ImageAspectFlags{coLor},
      baseMipLevel: 0,
      levelCount: 1,
      baseArrayLayer: 0,
      layerCount: 1),}

  #  Create an image view for every image in the swap chain
  for i in 0..<renderer.swapchainInfo.images[].len:
    imageViewCI.image = renderer.swapchainInfo.images[i]

    if device.create(renderer.swapchainImageViews[i], imageViewCI) != success:
      quit "failed to create image view for swap chain image #" & $i

proc createFramebuffers(renderer: var RenderingInstance)=
  renderer.swapchainFramebuffers.setLen(renderer.swapchainInfo.images[].len)

  #  NOTE: Framebuffer is basically a specific choice of attachments for a render pass
  #  That means all attachments must have the same dimensions, interesting restriction
  for i in 0..<renderer.swapchainInfo.images[].len:
    var frameBufferCI = FramebufferCreateInfo{
      renderPass: renderer.renderPass[],
      attachmentCount: 1,
      pAttachments: renderer.swapchainImageViews[i].head,
      width: renderer.swapchainInfo.extent.width,
      height: renderer.swapchainInfo.extent.height,
      layers: 1,}

    if device.create(renderer.swapchainFramebuffers[i], frameBufferCI) != success:
      quit "failed to create framebuffer for swap chain image view #" & $i

proc create(device: Weak[Device]; shader: var Uniq[ShaderModule]; filename: string): Result {.discardable.} =
  (if not filename.fileExists: quit filename & " is not exists!")

  var shadersrc = filename.readFile
  let shaderModuleCI = ShaderModuleCreateInfo{
    codeSize: uint32 shadersrc.len,
    pCode: cast[ptr uint32](addr shadersrc[0]),}

  result = device.create(shader, shaderModuleCI)
  if result != success:
    quit "failed to create shader module for " & filename & " code: " & $result
  echo "created shader module for ", filename

proc createDescriptorSetLayout =
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

  if device.create(descriptorSetLayout.uniformMVP, descriptorSetLayoutCI) != success:
    quit "failed to create descriptor layout"

proc createPipelineLayout =
  var pipelineLayoutCI = PipelineLayoutCreateInfo{
    setLayoutCount: 1,
    pSetLayouts: descriptorSetLayout.uniformMVP.head,}

  if device.create(pipelineLayout, pipelineLayoutCI) != success:
    quit "failed to create pipeline layout"

proc createGraphicsPipeline(renderer: var RenderingInstance) =
  var vertshader, fragshader: Uniq[ShaderModule]

  device.create(vertshader, "shaders/vert.spv")
  device.create(fragshader, "shaders/frag.spv")
  var shaderStages = [
    PipelineShaderStageCreateInfo{
      stage: ShaderStageFlagBits.vertex,
      module: vertshader[],
      pName: "main",},
    PipelineShaderStageCreateInfo{
      stage: ShaderStageFlagBits.fragment,
      module: fragshader[],
      pName: "main",},]

  #  Binding and attribute descriptions
  var vertexBindingDescription = Vertex.bindingDesc
  var vertexAttributeDescriptions = Vertex.attributeDesc
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
    width: float32 renderer.swapchainInfo.extent.width,
    height: float32 renderer.swapchainInfo.extent.height,
    minDepth: 0,
    maxDepth: 1,}

  var scissor = Rect2D{
    offset: Offset2D(x: 0, y: 0),
    extent: renderer.swapchainInfo.extent,}

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
    renderPass: renderer.renderPass[],
    subpass: 0,
    basePipelineHandle: Pipeline.none,
    basePipelineIndex: -1,}

  var res = device.create(renderer.graphicsPipeline, pipelineCreateInfo)
  if res != success:
    quit "failed to create graphics pipeline. code: " & $res

proc createDescriptorPool =
  #  This describes how many descriptor sets we'll create from this pool for each type
  var poolSize = DescriptorPoolSize(
    thetype: DescriptorType.uniformBuffer,
    descriptorCount: 1,)

  var descriptorPoolCI = DescriptorPoolCreateInfo{
    flags: DescriptorPoolCreateFlags{freeDescriptorSet},
    poolSizeCount: 1,
    pPoolSizes: addr poolSize,
    maxSets: 1,}

  if device.create(descriptorPool, descriptorPoolCI) != success:
    quit "failed to create descriptor pool"

proc createDescriptorSet =
  if descriptorPool.create(descriptorSet.uniformMVP, descriptorSetLayout.uniformMVP) != success:
    quit "failed to create descriptor set"

  #  Update descriptor set with uniform binding
  var descriptorBufferInfo = DescriptorBufferInfo{
    buffer: uniformMVP.deviceMemory.buffer[],
    offset: DeviceSize 0,
    range: DeviceSize sizeof uniformMVP.data,}

  var writeDescriptorSet = WriteDescriptorSet{
    dstSet: descriptorSet.uniformMVP[],
    descriptorCount: 1,
    descriptorType: DescriptorType.uniformBuffer,
    pBufferInfo: addr descriptorBufferInfo,
    dstBinding: 0,
    dstArrayElement: 0,
    pImageInfo: nil,
    pTexelBufferView: nil,}

  device[].updateDescriptorSets(1, addr writeDescriptorSet, 0, nil)

proc createGraphicsCommandBuffers(renderer: var RenderingInstance) =
  #  Allocate graphics command buffers

  var commandBufferCI = ClCommandBufferCreateInfo{}

  renderer.graphicsCommandBuffers.setLen(renderer.swapchainInfo.images[].len)
  if graphicsCommandPool.create(renderer.graphicsCommandBuffers, commandBufferCI) != success:
    quit "failed to allocate graphics command buffers"

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
  for i, commandBuffer in renderer.graphicsCommandBuffers[]:
    #  If present queue family and graphics queue family are different, then a barrier is necessary
    #  The barrier is also needed initially to transition the image to the present layout
    var barrier = (
      presentToDraw: ImageMemoryBarrier{
        srcAccessMask: AccessFlags{noneKHR},
        dstAccessMask: AccessFlags{colorAttachmentWrite},
        oldLayout: ImageLayout.undefined,
        newLayout: ImageLayout.presentSrcKHR,
        srcQueueFamilyIndex:
          if queueFamilies.sharingMode == concurrent: QueueFamilyIgnored
          else:                                       queueFamilies.both[].index.get,
        dstQueueFamilyIndex:
          if queueFamilies.sharingMode == concurrent: QueueFamilyIgnored
          else:                                       queueFamilies.both[].index.get,
        image: renderer.swapchainInfo.images[i],
        subresourceRange: subresourceRange,},
    )

    var renderPassBeginInfo = RenderPassBeginInfo{
      renderPass: renderer.renderPass[],
      framebuffer: renderer.swapchainFramebuffers[i][],
      renderArea: Rect2D(
        offset: Offset2D(x: 0, y: 0),
        extent: renderer.swapchainInfo.extent,),
      clearValueCount: 1,
      pClearValues: addr clearColor,}

    var offset: DeviceSize

    commandBuffer.begin(beginInfo)
    commandBuffer
      .cmdBarrier(
        PipelineStageFlags{colorAttachmentOutput},
        PipelineStageFlags{colorAttachmentOutput},
        DependencyFlags.none, 0, nil, 0, nil, 1, addr barrier.presentToDraw)
      # .cmdBeginRenderPass(renderPassBeginInfo, SubpassContents.inline)
      .cmdBindDescriptorSets(PipelineBindPoint.graphics, pipelineLayout[], 0, 1, descriptorSet.uniformMVP.head, 0, nil)
      .cmdBindPipeline(PipelineBindPoint.graphics, renderer.graphicsPipeline[])
      .cmdBindVertexBuffers(0, 1, vertexSource.buffer.head, addr offset)
      .cmdBindIndexBuffer(indexSource.buffer[], DeviceSize(0), IndexType.uint32)

      .cmdBeginRenderPass(renderPassBeginInfo, SubpassContents.inline)
      .cmdDrawIndexed(3, 1, 0, 0, 0)
      .cmdEndRenderPass

    #  If present and graphics queue families differ, then another barrier is required
    if queueFamilies.sharingMode == concurrent:
      var drawToPresentBarrier = ImageMemoryBarrier{
        srcAccessMask: AccessFlags{colorAttachmentWrite},
        dstAccessMask: AccessFlags{memoryRead},
        oldLayout: ImageLayout.presentSrcKHR,
        newLayout: ImageLayout.presentSrcKHR,
        srcQueueFamilyIndex: queueFamilies.graphics[].index.get,
        dstQueueFamilyIndex: queueFamilies.present[].index.get,
        image: renderer.swapchainInfo.images[i],
        subresourceRange: subResourceRange }

      commandBuffer.cmdBarrier(
        PipelineStageFlags{colorAttachmentOutput},
        PipelineStageFlags{bottomOfPipe},
        DependencyFlags.none, 0, nil, 0, nil, 1, addr drawToPresentBarrier)

    if commandBuffer.end != success:
      quit "failed to record command buffer"

  echo "recorded command buffers"

proc setup(renderer: var RenderingInstance; defaultWindowSize: Extent2D) =
  renderer.createSwapchain(defaultWindowSize)
  renderer.createRenderPass
  renderer.createImageViews
  renderer.createFramebuffers
  renderer.createGraphicsPipeline
  renderer.createGraphicsCommandBuffers

proc cleanup(renderer: var RenderingInstance) =
  discard device[].deviceWaitIdle
  destroy renderer.graphicsCommandBuffers

  destroy renderer.graphicsPipeline
  destroy renderer.renderPass

  for i in 0..<renderer.swapchainInfo.images[].len:
    destroy renderer.swapchainFramebuffers[i]
    destroy renderer.swapchainImageViews[i]

proc finalize(renderer: var RenderingInstance) =
  cleanup renderer
  destroy renderer.swapchain

proc setupVulkan =
  var
    queueFamilyIndex: tuple[graphics, present: uint32]
  create(instance)
    .loadAppCommands
    .create(messenger)
    .create(surface, targetWindow= window)
    .find(physicalDevice)
      .checkSwapChainSupport
      .find(queueFamilyIndex.graphics, queueFamilyIndex.present)
      .create(device, queueFamilyIndex.graphics, queueFamilyIndex.present)
  queueFamilies = QueueFamilies(
    sharingMode:
      if queueFamilyIndex.graphics == queueFamilyIndex.present:
        SharingMode.exclusive
      else:
        SharingMode.concurrent
  )
  case queueFamilies.sharingMode
  of exclusive:
    device.assembleQueueFamily(queueFamilies.both, queueFamilyIndex.graphics)
    #  Get graphics and presentation queues (which may be the same)
    queueFamilies.both.get(graphicsQueue)
    queueFamilies.both.get(presentQueue)
  of concurrent:
    device.assembleQueueFamily(queueFamilies.graphics, queueFamilyIndex.graphics)
    device.assembleQueueFamily(queueFamilies.present, queueFamilyIndex.present)
    #  Get graphics and presentation queues (which may be the same)
    queueFamilies.graphics.get(graphicsQueue)
    queueFamilies.present.get(presentQueue)

  block:
    let CI = SemaphoreCreateInfo{}
    if  device.create(semaphore.imageAvailable, CI) != success or
        device.create(semaphore.renderingFinished, CI) != success:
      quit "failed to create semaphores"
  createCommandPool()
  createVertexBuffer()
  createUniformBuffer()
  createDescriptorPool()
  createDescriptorSetLayout()
  createDescriptorSet()
  createPipelineLayout()

proc recreate(renderer: var RenderingInstance) =
  echo "< RENDERER RECREATION >"

  #  Only recreate objects that are affected by framebuffer size changes
  cleanup renderer
  setup renderer, renderer.swapchainInfo.extent

  rendererShouldRecreate = false
  matrices.proj.needsUpdate = true
  echo "</RENDERER RECREATION >"

proc processio(camera: var Lens; modelCoord: var Coords) =
  if window.getKey(Key.Escape) == Press:
    window.setWindowShouldClose(true)
  let axisws = float(window.getKey(Key.W)) - float(window.getKey(Key.S))
  let axisda = float(window.getKey(Key.D)) - float(window.getKey(Key.A))
  let axiseq = float(window.getKey(Key.E)) - float(window.getKey(Key.Q))
  if axisws != 0:
    camera.coord.moveFront(0.1*axisws.float)
    matrices.view.needsUpdate = true
  if axisda != 0:
    camera.coord.moveRight(0.1*axisda.float)
    matrices.view.needsUpdate = true
  if axiseq != 0:
    camera.coord.moveZ(0.1*axiseq.float)
    matrices.view.needsUpdate = true

  window.update mousePos

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

proc draw(renderer: var RenderingInstance) =
  #  Acquire image
  var imageIndex: uint32
  var res = device[].acquireNextImageKHR(renderer.swapchain[], uint64.high, semaphore.imageAvailable[], Fence.none, addr imageIndex)

  #  Unless surface is out of date right now, defer swap chain recreation until end of this frame
  if res == errorOutOfDateKHR:
    rendererShouldRecreate = true
    return
  elif res != success:
    quit "failed to acquire image"

  #  This is the stage where the queue should wait on the semaphore
  var waitDstStageMask = PipelineStageFlags{topOfPipe}

  #  Wait for image to be available and draw
  var submitInfo = SubmitInfo{
    waitSemaphoreCount: 1,
    pWaitSemaphores: semaphore.imageAvailable.head,
    signalSemaphoreCount: 1,
    pSignalSemaphores: semaphore.renderingFinished.head,
    pWaitDstStageMask: addr waitDstStageMask,
    commandBufferCount: 1,
    pCommandBuffers: unsafeAddr renderer.graphicsCommandBuffers[][imageIndex].downcast,
  }

  if graphicsQueue.queueSubmit(1, addr submitInfo) != success:
    quit "failed to submit draw command buffer"

  #  Present drawn image
  #  NOTE: semaphore here is not strictly necessary, because commands are processed in submission order within a single queue

  res = presentQueue.present PresentInfoKHR{
    waitSemaphoreCount: 1,
    pWaitSemaphores: semaphore.renderingFinished.head,
    swapchainCount: 1,
    pSwapchains: renderer.swapchain.head,
    pImageIndices: addr imageIndex,
  }

  if res in [suboptimalKHR, errorOutOfDateKHR]:
    rendererShouldRecreate = true
  elif res != success:
    quit "failed to submit present command buffer."

proc update(uniformMVP: var UniformMVP; camera: var Lens; model: var Coords) =
  uniformMVP.data.transformationMatrix = camera.projection * camera.view * model.localModel
  uniformMVP.deviceMemory.memory.sendData uniformMVP.data

proc renderingLoop(defaultWindowSize: Extent2D) =
  var renderer: RenderingInstance
  setup renderer, defaultWindowSize
  var modelCoord = newCoords()
  var camera = newLens(
    fov= 70'deg32.rad,
    aspect= renderer.swapchainInfo.extent.aspect,
    z= (near: 0.1f, far: 10f))
  camera.coord.point [0f, -3, 1]
  block MainLoop:
    echo "< MAIN LOOP >"
    while not window.windowShouldClose:
      processio(camera, modelCoord)
      uniformMVP.update(camera, modelCoord)
      renderer.draw()
      if rendererShouldRecreate:
        recreate renderer
        camera.aspect = renderer.swapchainInfo.extent.aspect
      glfwPollEvents()
    finalize renderer
    echo "</MAIN LOOP >"

when isMainModule:
  const defaultWindowSize = Extent2D(width: 640, height: 480)
  #  Create window for Vulkan
  discard glfwInit()
  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
  window = glfwCreateWindow(defaultWindowSize.width.int32, defaultWindowSize.height.int32, "The triangle and movable camera that took 1079 lines of code with safetyhandles")
  if window == nil:
    glfwTerminate()
    quit(QuitFailure)
  discard window.setWindowSizeCallback onWindowResized
  window.setInputMode GLFWCursorSpecial, GLFWCursorDisabled

  #  Use Vulkan
  setupVulkan()
  renderingLoop defaultWindowSize