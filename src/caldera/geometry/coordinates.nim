import vkm
import ../syncToken

type
  Coords* = object
    countRef: int
    volume: array[3,float32]
    pose: NQuat[float32]
    point: array[3,float32]
    sync*: tuple[
      localRotation,
      localScaleRotation,
      localTranslate: SyncToken[stuComponentUpdateNotice]]
    cache: tuple[
      mat: tuple[
        local: tuple[
          model: Mat[4,4,float32],
          rot: Mat[3,3,float32] ],
        global: tuple[
          model: Mat[4,4,float32] ],
      ]
    ]

proc pointWasChanged*(coords: var Coords) =
  reqSync coords.sync.localTranslate
proc poseWasChanged*(coords: var Coords) =
  reqSync coords.sync.localRotation
  reqSync coords.sync.localScaleRotation
proc volumeWasChanged*(coords: var Coords) =
  reqSync coords.sync.localScaleRotation

proc localRot*(coords: var Coords): lent Mat[3,3,float32] =
  whenSync coords.sync.localRotation:
    coords.cache.mat.local.rot = coords.pose.mat3
  coords.cache.mat.local.rot

proc localModel*(coords: var Coords): lent Mat[4,4,float32] =
  template cache: untyped = coords.cache
  template mlm: untyped = cache.mat.local.model
  whenSync coords.sync.localTranslate:
    mlm[3] = vec(coords.point, 1f)
  whenSync coords.sync.localScaleRotation:
    mlm[0].xyz = coords.localRot[0] * coords.volume
    mlm[1].xyz = coords.localRot[1] * coords.volume
    mlm[2].xyz = coords.localRot[2] * coords.volume
  mlm

proc clear*(coords: var Coords) =
  zeroMem coords.addr, sizeof Coords
  cast[ptr Quat[float32]](addr coords.pose)[].vec.w = 1
  coords.volume = [1f].xxx
  for i in 0..2:
    coords.cache.mat.local.rot[i][i] = 1
    coords.cache.mat.local.model[i][i] = 1
    coords.cache.mat.global.model[i][i] = 1
  coords.cache.mat.local.model[3][3] = 1
  coords.cache.mat.global.model[3][3] = 1
proc newCoords*(): Coords =
  clear result

let axis3* = (
  right: asNormalized [1f, 0, 0],
  front: asNormalized [0f, 1, 0],
  top:   asNormalized [0f, 0, 1])

proc right*(this: var Coords): Normalized[array[3,float32]] = asNormalized this.localrot[0]
proc front*(this: var Coords): Normalized[array[3,float32]] = asNormalized this.localrot[1]
proc top  *(this: var Coords): Normalized[array[3,float32]] = asNormalized this.localrot[2]

proc point*(this: Coords): lent array[3,float32] =
  this.point
proc volume*(this: Coords): lent array[3,float32] =
  this.volume
proc pose*(this: Coords): lent NQuat[float32] =
  this.pose

proc move*(this: var Coords; delta: array[3,float32]): var Coords {.discardable.} =
  this.pointWasChanged
  this.point += delta
  this
proc move*(this: var Coords; dx, dy, dz = default(float32)): var Coords {.discardable.} =
  this.pointWasChanged
  this.point += [dx, dy, dz]
  this
proc moveX*(this: var Coords; delta: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point.x += delta
  this
proc moveY*(this: var Coords; delta: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point.y += delta
  this
proc moveZ*(this: var Coords; delta: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point.z += delta
  this
proc moveRight*(this: var Coords; delta: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point += this.right * delta
  this
proc moveFront*(this: var Coords; delta: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point += this.front * delta
  this
proc moveTop*(this: var Coords; delta: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point += this.top * delta
  this

proc point*(this: var Coords; pos: array[3,float32]): var Coords {.discardable.} =
  this.pointWasChanged
  this.point = pos
  this
proc point*(this: var Coords; x, y, z: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point = [x, y, z]
  this
proc pointX*(this: var Coords; pos: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point.x = pos
  this
proc pointY*(this: var Coords; pos: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point.y = pos
  this
proc pointZ*(this: var Coords; pos: float32): var Coords {.discardable.} =
  this.pointWasChanged
  this.point.z = pos
  this

proc rotate*(this: var Coords; axis: Normalized[array[3,float32]]; angle: Radian32): var Coords {.discardable.} =
  this.poseWasChanged
  this.pose = this.pose.rotate(angle, axis)
  this
proc rotateX*(this: var Coords; angle: Radian32): var Coords {.discardable.} =
  this.poseWasChanged
  this.pose = this.pose.rotateGrobalX(angle)
  this
proc rotateY*(this: var Coords; angle: Radian32): var Coords {.discardable.} =
  this.poseWasChanged
  this.pose = this.pose.rotateGrobalY(angle)
  this
proc rotateZ*(this: var Coords; angle: Radian32): var Coords {.discardable.} =
  this.poseWasChanged
  this.pose = this.pose.rotateGrobalZ(angle)
  this
proc pitch*(this: var Coords; angle: Radian32): var Coords {.discardable.} =
  this.poseWasChanged
  this.pose = this.pose.rotateX(angle)
  this
proc roll*(this: var Coords; angle: Radian32): var Coords {.discardable.} =
  this.poseWasChanged
  this.pose = this.pose.rotateY(angle)
  this
proc yaw*(this: var Coords; angle: Radian32): var Coords {.discardable.} =
  this.poseWasChanged
  this.pose = this.pose.rotateZ(angle)
  this

proc pitch*(this: Coords): Radian32 = this.pose.pitch
proc roll *(this: Coords): Radian32 = this.pose.roll
proc yaw  *(this: Coords): Radian32 = this.pose.yaw

proc pose*(this: var Coords; axis: Normalized[array[3,float32]]; angle: Radian32): var Coords {.discardable.} =
  this.poseWasChanged
  this.pose = NQuat[float32].rotate(angle, axis)
  this

proc scale*(this: var Coords; factor: array[3,float32]): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume *= factor
  this
proc scale*(this: var Coords; fx, fy, fz = default(float32)): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume *= [fx, fy, fz]
  this
proc scale*(this: var Coords; factor: float32): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume *= factor
  this
proc scaleX*(this: var Coords; factor: float32): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume.x *= factor
  this
proc scaleY*(this: var Coords; factor: float32): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume.y *= factor
  this
proc scaleZ*(this: var Coords; factor: float32): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume.z *= factor
  this

proc resize*(this: var Coords; newSize: array[3,float32]): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume = newSize
  this
proc resize*(this: var Coords; nx, ny, nz = default(float32)): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume = [nx, ny, nz]
  this
proc resize*(this: var Coords; n: float32): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume = [n].xxx
  this
proc resizeX*(this: var Coords; factor: float32): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume.x = factor
  this
proc resizeY*(this: var Coords; factor: float32): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume.y = factor
  this
proc resizeZ*(this: var Coords; factor: float32): var Coords {.discardable.} =
  this.volumeWasChanged
  this.volume.z = factor
  this

func `$`*(coords: Coords): string =
  result.add "point: " & $coords.point & "\n"
  result.add "pose : " & $coords.pose & "\n"
  result.add "scale: " & $coords.volume

when isMainModule:
  import sugar

  var coords = newCoords()

  coords.yaw(45'deg32.rad).move(10, 20, 30)

  echo "default"
  echo coords.localModel

  dump coords.front

  coords.scale(50, 40, 30)

  echo "scale"
  echo coords.localModel

  coords.move(10, 20, 30)

  echo "translate"
  echo coords.localModel

  var childCoords = newCoords()

  childCoords.moveX(10)

  echo "child's default"
  echo childCoords.localModel

  echo "parent * child"
  echo coords.localModel * childCoords.localModel
