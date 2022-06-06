import std/macros
import std/strutils

import vulkan
import vkm
import clsl

type
  Vertex* = object
    pos*: Vec3f32
    color*: Vec3f32

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

proc signBindingDesc*(T: typedesc; binding: var VertexInputBindingDescription) =
  #  Binding and attribute descriptions
  binding.binding = 0
  binding.stride = uint32 sizeof Vertex
  binding.inputRate = VertexInputRate.vertex

proc signAttributeDesc*(T: typedesc; attribute: var seq[VertexInputAttributeDescription]) =
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
  T.signBindingDesc binding
template sign*(T: typedesc; attribute: var seq[VertexInputAttributeDescription]) =
  T.signAttributeDesc attribute

proc bindingDesc*(T: typedesc): VertexInputBindingDescription =
  T.sign result
proc attributeDesc*(T: typedesc): seq[VertexInputAttributeDescription] =
  T.sign result

macro HEX*(code: static string): Vec3f32 =
  if code.len != 6:
    error ""
  let vecarr = [
      code[0..1].parseHexInt.float32/255,
      code[2..3].parseHexInt.float32/255,
      code[4..5].parseHexInt.float32/255]
  quote do:
    vec `vecarr`