import std/macros {.all.}

from vulkan import ObjectType

template parent(Enum: typedesc[enum]) {.pragma.}

macro define_converter(Enum: typedesc[enum]; exportme: static bool = false): untyped =
  for pragma in Enum.customPragmaNode:
    if pragma.len >= 1 and pragma[0].repr == "parent":
      let truename = ident"castAsParent"
      return newProc(
        (if exportme: truename.postfix("*") else: truename),
        [pragma[1], newIdentDefs(ident"e", Enum)],
        (quote do: cast[ptr typeof result](unsafeAddr e)[]),
        nnkConverterDef
      )
  error "`parent` pragma not found", Enum

macro extends(Parent: typedesc[enum]; body): untyped =
  let typedef = body
  template enumname: untyped = typedef[0][0]
  template typepragma: untyped = typedef[0][1]
  template enumfields: untyped = typedef[2][1..^1]
  template parentfields: untyped = Parent.getImpl[2][1..^1]
  typepragma.add newCall(ident"parent", Parent)
  var errorFields: seq[tuple[ext, parent: NimNode]]
  var enumidx = 0
  for parentfield in parentfields:
    template enumval: untyped = enumfields[enumidx][1].intVal
    let parentval = parentfield[1].intVal
    while enumval < parentval: inc enumidx
    if enumval == parentval: errorFields.add (enumfields[enumidx], parentfield)
  if errorFields.len != 0:
    var errorlit = "there are " & $errorFields.len & " duplicated fields:\n"
    for errorfield in errorFields:
      errorlit.add $enumname & "." & repr(errorfield.ext[0]) & " == " & $Parent & "." & repr(errorfield.parent[0]) & " (" & $errorfield.ext[1].intVal & ")\n"
    error errorlit, typedef

  body


when isMainModule:
  type ObjectTypeEX* {.extends: ObjectType.} = enum
    successVal = 100
    # errorVal = 100000_0000
    successVal2 = 100000_0001
    # errorVal2 = 100000_1000
    queueFamily = 200000_0001

  define_converter ObjectTypeEX
  let objtype: ObjectType = ObjectTypeEX.successVal
  echo objtype