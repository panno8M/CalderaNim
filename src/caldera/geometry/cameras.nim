import std/options

import vulkan
import vkm
from vkm/mat_transform {.all.} import viewMat

import ./coordinates
import ../syncToken
type
  Lens* = object
    coord: Option[ptr Coords]
    fov*: Radian32
    aspect: float32
    z*: tuple[near, far: float32]
    sync: tuple[proj: SyncToken[stuComponentUpdateNotice]]
    syncFor: tuple[localTranslate, localRotation: SyncTokenRef[stuComponentUpdateNotice]]
    cache: tuple[
      mat: tuple[
        view: Mat[4,4,float32],
        proj: Mat[4,4,float32],
      ]
    ]

func aspect*(e: Extent2D): float32 = e.width.float32 / e.height.float32

proc `aspect=`*(lens: var Lens; aspect: sink float32) =
  lens.aspect = aspect
  reqSync lens.sync.proj

proc coord*(lens: var Lens): var Coords =
  lens.coord.get[]

proc attach*(lens: var Lens; coord: var Coords) =
  lens.coord = some coord.addr

proc projection*(lens: var Lens): lent Mat[4,4,float32] =
  whenSync lens.sync.proj:
    lens.cache.mat.proj = perspectiveRH(lens.fov, lens.aspect, lens.z.near, lens.z.far)
  lens.cache.mat.proj

proc view*(lens: var Lens): lent Mat[4,4,float32] =
  if lens.coord.isSome:
    if lens.syncFor.localRotation.needSync or lens.syncFor.localTranslate.needSync:
      let front = -lens.coord.get[].front
      let right = lens.coord.get[].right
      let top = -lens.coord.get[].top

      if lens.syncFor.localRotation.needSync:
        lens.cache.mat.view{0} = vec(right.unwrap, 0f)
        lens.cache.mat.view{1} = vec(top.unwrap, 0f)
        lens.cache.mat.view{2} = vec(front.unwrap, 0f)

      let pos = lens.coord.get[].point
      lens.cache.mat.view[3] = [
        -dot(right, pos),
        -dot(top, pos),
        -dot(front, pos),
        1]

      updated lens.syncFor.localRotation
      updated lens.syncFor.localTranslate
  else:
    lens.cache.mat.view = mat4[float32](1)
  lens.cache.mat.view

proc newLens*(fov: Radian32; aspect: float32; z: tuple[near, far: float32]; coord: var Coords): Lens =
  result = Lens(
    coord: some coord.addr,
    fov: fov,
    aspect: aspect,
    z: z,
  )
  result.cache.mat.view = mat4[float32](1)
  reqSync result.sync.proj
  result.syncFor.localRotation =<< coord.sync.localRotation
  result.syncFor.localTranslate =<< coord.sync.localTranslate

template newLens*(fov: Radian32; aspect: float32; z: tuple[near, far: float32]): Lens =
  var coords {.gensym.} = newCoords()
  newLens(fov, aspect, z, coords)