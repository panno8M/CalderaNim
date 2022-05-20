
type
  Component* = ptr object of RootObj
    container: ComponentContainer
  ComponentContainer* = object
    a: seq[Component]

proc hasComponent*(cc: var ComponentContainer; key: string): bool =
  return

proc getComponent*(cc: var ComponentContainer; key: string) =
  return