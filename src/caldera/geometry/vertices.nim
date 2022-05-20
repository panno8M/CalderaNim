import std/macros
import std/strutils

import vulkan
import vkm

type
  Vertex* = object
    pos*: Vec3f32
    color*: Vec3f32

template shaderformat(T): Format =
  when T is float32 | array[1, float32]: Format.r32Sfloat
  elif T is Vec2f32 | array[2, float32]: Format.r32g32Sfloat
  elif T is Vec3f32 | array[3, float32]: Format.r32g32b32Sfloat
  elif T is Vec4f32 | array[4, float32]: Format.r32g32b32a32Sfloat

  elif T is float64 | array[1, float64]: Format.r64Sfloat
  elif T is Vec2f64 | array[2, float64]: Format.r64g64Sfloat
  elif T is Vec3f64 | array[3, float64]: Format.r64g64b64Sfloat
  elif T is Vec4f64 | array[4, float64]: Format.r64g64b64a64Sfloat

  elif T is int32   | array[1,   int32]: Format.r32Sint
  elif T is Vec2i32 | array[2,   int32]: Format.r32g32Sint
  elif T is Vec3i32 | array[3,   int32]: Format.r32g32b32Sint
  elif T is Vec4i32 | array[4,   int32]: Format.r32g32b32a32Sint

  elif T is int64   | array[1,   int64]: Format.r64Sint
  elif T is Vec2i64 | array[2,   int64]: Format.r64g64Sint
  elif T is Vec3i64 | array[3,   int64]: Format.r64g64b64Sint
  elif T is Vec4i64 | array[4,   int64]: Format.r64g64b64a64Sint

  elif T is uint32  | array[1,  uint32]: Format.r32Uint
  elif T is Vec2u32 | array[2,  uint32]: Format.r32g32Uint
  elif T is Vec3u32 | array[3,  uint32]: Format.r32g32b32Uint
  elif T is Vec4u32 | array[4,  uint32]: Format.r32g32b32a32Uint

  elif T is uint64  | array[1,  uint64]: Format.r64Uint
  elif T is Vec2u64 | array[2,  uint64]: Format.r64g64Uint
  elif T is Vec3u64 | array[3,  uint64]: Format.r64g64b64Uint
  elif T is Vec4u64 | array[4,  uint64]: Format.r64g64b64a64Uint

  else:
    {.warning: "No matching format exists. Undefined is selected".}
    Format.undefined

proc offsetOfDotExpr(typeAccess: typed): int {.magic: "OffsetOf", noSideEffect, compileTime.}
macro offsetOf(t: typedesc; member: static string): int =
  let member = ident member
  quote do:
    var tmp {.noinit.} : ptr typeof `t`
    offsetOfDotExpr(tmp[].`member`)

macro fieldLen(t: typedesc): uint32 =
  runnableExamples:
    type SampleVertex1 = object
      pos: array[3, float32]
    type SampleVertex2 = object
      pos: array[3, float32]
      color: array[3, float32]
    doAssert SampleVertex1.fieldLen == 1
    doAssert SampleVertex2.fieldLen == 2

  let i = uint32 Vertex.getTypeImpl[2].len
  quote do: `i`

proc signBinding*(T: typedesc; binding: var VertexInputBindingDescription) =
  #  Binding and attribute descriptions
  binding.binding = 0
  binding.stride = uint32 sizeof Vertex
  binding.inputRate = VertexInputRate.vertex

proc signAttribute*(T: typedesc; attribute: var seq[VertexInputAttributeDescription]) =
  attribute.setLen T.fieldLen
  var i: uint32
  var tmp {.noinit.}: ptr T
  for name, value in tmp[].fieldPairs:
    attribute[i].binding = 0
    attribute[i].location = i
    attribute[i].format = value.shaderformat
    attribute[i].offset = uint32 T.offsetOf name
    inc i

template sign*(T: typedesc; binding: var VertexInputBindingDescription) =
  T.signBinding binding
template sign*(T: typedesc; attribute: var seq[VertexInputAttributeDescription]) =
  T.signAttribute attribute

macro HEX*(code: static string): Vec3f32 =
  if code.len != 6:
    error ""
  let vecarr = [
      code[0..1].parseHexInt.float32/255,
      code[2..3].parseHexInt.float32/255,
      code[4..5].parseHexInt.float32/255]
  quote do:
    vec `vecarr`