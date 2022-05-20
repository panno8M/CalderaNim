import std/macros
import std/strformat
import std/logging

import vulkan

const TraceHook = defined traceHook
type HandleNotAliveDefect* = object of NilAccessDefect

type
  Heap*[HandleType] = object
    mpParent: pointer
    mHandle: HandleType
    mIsAlive: bool
  Weak*[HandleType] {.byCopy.} = object
    mrHeap: ref Heap[HandleType]
  Uniq*[HandleType] {.byRef.} = object
    mrHeap: ref Heap[HandleType]

proc `=copy`[T](dst: var Uniq[T]; src: Uniq[T]) {.error.}
proc `=destroy`[T](handle: var Uniq[T])

when TraceHook:
  import std/tables
  template memaddr[T](handle: var Heap[T]): uint64 = cast[uint64](unsafeaddr handle)
  var hookIdLookup: OrderedTable[uint64, Natural]
  var nextId: Natural
  proc idof*[T](handle: var Heap[T]): Natural =
    {.gcsafe.}:
      if not hookIdLookup.hasKey(memaddr handle):
        hookIdLookup[memaddr handle] = nextId
        inc nextId
      hookIdLookup[memaddr handle]
  var hookLogger* = newConsoleLogger()

template impl_create[T](handle: var Uniq[T]; body): untyped {.used.} =
  template HandleType: untyped = typeof(handle).HandleType
  var heap: Heap[HandleType]
  if handle.mrHeap == nil:
    handle.mrHeap = new Heap[HandleType]
  elif handle.mrHeap.mIsAlive:
    heap = handle.mrHeap[]
  handle.mrHeap.mIsAlive = true
  when TraceHook:
    hookLogger.log lvlInfo, &": (manu) CREATE #{idof(handle.mrHeap[]):03} : {$HandleType}"
  body
template impl_create[S,T](parent: Weak[S]; handle: var Uniq[T]; body): untyped {.used.} =
  template HandleType: untyped = typeof(handle).HandleType
  var heap: Heap[HandleType]
  if handle.mrHeap == nil:
    handle.mrHeap = new Heap[HandleType]
  elif handle.mrHeap.mIsAlive:
    heap = handle.mrHeap[]
  handle.mrHeap.mpParent = cast[pointer](parent.mrHeap)
  handle.mrHeap.mIsAlive = true
  when TraceHook:
    hookLogger.log lvlInfo, &": (manu) CREATE #{idof(handle.mrHeap[]):03} : {$HandleType}"
  body

{.push, used, inline.}
proc castHeapParent[T,S](handle: Heap[T]; Type: typedesc[S]): Heap[S] =
  cast[ptr Heap[S]](handle.mpParent)[]
proc castParent[T,S](handle: Heap[T]; Type: typedesc[S]): S =
  handle.castHeapParent(Type).mHandle
template impl_destroy[T](handle: Heap[T]; body): untyped =
  body
  handle.mIsAlive = false
{.pop.}

proc setLen*[T](handle: var Uniq[seq[T]]; newSize: int) =
  if handle.mrHeap == nil:
    handle.mrHeap = new Heap[seq[T]]
  handle.mrHeap.mHandle.setLen(newSize)

func isAlive*[T](handle: Weak[T]): bool =
  handle.mrHeap != nil and handle.mrHeap.mIsAlive
func isAlive*[T](handle: Uniq[T]): bool =
  handle.mrHeap != nil and handle.mrHeap.mIsAlive

func rawhandle*[T](handle: Weak[T]): lent T =
  if not handle.isAlive:
    raise newException(HandleNotAliveDefect, "This handle has no reference to anywhere. Use unsafeaddr if Nil is acceptable.")
  handle.mrHeap.mHandle
func rawhandle*[T](handle: Uniq[T]): lent T =
  if not handle.isAlive:
    raise newException(HandleNotAliveDefect, "This handle has no reference to anywhere. Use unsafeaddr if Nil is acceptable.")
  handle.mrHeap.mHandle
func rawhandle*[T](handle: var Uniq[T]): var T =
  if not handle.isAlive:
    raise newException(HandleNotAliveDefect, "This handle has no reference to anywhere. Use unsafeaddr if Nil is acceptable.")
  handle.mrHeap.mHandle

func `[]`*[T](handle: Weak[T]): lent T {.inline.} = handle.rawhandle
func `[]`*[T](handle: Uniq[T]): lent T {.inline.} = handle.rawhandle

template `[]`*[T](handle: Weak[seq[T]], i: int): lent T = handle[][i]
template `[]`*[T](handle: Uniq[seq[T]], i: int): lent T = handle[][i]
template `[]`*[I,T](handle: Weak[array[I,T]], i: int): lent T = handle[][i]
template `[]`*[I,T](handle: Uniq[array[I,T]], i: int): lent T = handle[][i]

proc head*[T](handle: Weak[T]): ptr T = unsafeAddr handle[]
proc head*[T](handle: Weak[seq[T]]): ptr T = unsafeAddr handle[][0]
proc head*[I,T](handle: Weak[array[I,T]]): ptr T = unsafeAddr handle[][0]

proc getParentAs[T, S](handle: Weak[T]; Type: typedesc[Weak[S]]): Weak[S] {.inline, used.} =
  if handle.isAlive:
    cast[Weak[S]](handle.mrHeap.mpParent)
  else:
    raise newException(HandleNotAliveDefect, "This handle has no reference to anywhere. It is possible that the reference has already been destroyed.")

template destroy[T](handle: var Heap[T]) = destroy handle
proc `=destroy`[T](handle: var Uniq[T]) =
  if handle.isAlive:
    when TraceHook:
      hookLogger.log lvlInfo, &": (auto) DESTROY #{idof(handle.mrHeap[]):03} : {$T}"
    destroy handle.mrHeap[]
proc destroy*[T](handle: var Uniq[T]) =
  if handle.isAlive:
    when TraceHook:
      hookLogger.log lvlInfo, &": (manu) DESTROY #{idof(handle.mrHeap[]):03} : {$T}"
    destroy handle.mrHeap[]

converter weak*[T](handle: Uniq[T]): lent Weak[T] =
  cast[ptr Weak[T]](unsafeAddr handle)[]
converter weak*[T](handle: var Uniq[T]): var Weak[T] =
  cast[ptr Weak[T]](addr handle)[]
