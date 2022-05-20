import vulkan
import vkm

import ../vertices

type VertIndex = uint32
type Mesh* = object
  vertices*: seq[Vertex]
  indices*: seq[VertIndex]

{.push, inline.}
proc sizeofVertices*(mesh: Mesh): DeviceSize =
  DeviceSize mesh.vertices.len * sizeof Vertex
proc sizeofIndices*(mesh: Mesh): DeviceSize =
  DeviceSize mesh.indices.len * sizeof VertIndex
{.pop.}

let Triangle* = Mesh(
  vertices: @[
    Vertex(pos: vec3f32( 0        ,  1  , 0), color: HEX"E6E6E6"),
    Vertex(pos: vec3f32(-sqrt 0.75, -0.5, 0), color: HEX"E6E6E6"),
    Vertex(pos: vec3f32( sqrt 0.75, -0.5, 0), color: HEX"E6E6E6"),],
  indices: @[0u32, 1, 2])