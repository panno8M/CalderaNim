import std/macros
import std/strformat
import std/logging

import vulkan

const TraceHook = defined traceHook
const UseException = true
# defined safetyHandlesUseException
type HandleNotAliveDefect* = object of NilAccessDefect

proc issueException*() =
  template msg: string = "This handle has no reference to anywhere. Use unsafeaddr if Nil is acceptable."
  when UseException:
    raise newException(HandleNotAliveDefect, msg)
  else:
    quit(msg)

type
  Pac*[HandleType] = object
    mpParent: pointer
    mHandle: HandleType
    mIsAlive: bool
  Weak*[HandleType] {.byCopy.} = object
    mrPac: ref Pac[HandleType]
  Uniq*[HandleType] {.byRef.} = object
    mrPac: ref Pac[HandleType]

proc `=copy`[T](dst: var Uniq[T]; src: Uniq[T]) {.error.}
proc `=destroy`[T](handle: var Uniq[T])

{.push, used, inline.}

when TraceHook:
  import std/tables
  template memaddr[T](handle: var Pac[T]): uint64 = cast[uint64](unsafeaddr handle)
  var hookIdLookup: OrderedTable[uint64, Natural]
  var nextId: Natural
  proc idof*[T](handle: var Pac[T]): Natural =
    {.gcsafe.}:
      if not hookIdLookup.hasKey(memaddr handle):
        hookIdLookup[memaddr handle] = nextId
        inc nextId
      hookIdLookup[memaddr handle]
  var hookLogger* = newConsoleLogger()

  proc `$`(res: Result): string =
    if hookLogger isnot ConsoleLogger:
      return repr res

    if likely(res.ord == 0):
      "\e[32m" & repr(res) & "\e[0m" # Green
    elif res.ord < 0:
      "\e[33m" & repr(res) & "\e[0m" # Red
    else:
      "\e[31m" & repr(res) & "\e[0m" # Yellow


template impl_create[T](handle: var Uniq[T]; body): untyped {.used.} =
  template HandleType: untyped = typeof(handle).HandleType
  var pac: Pac[HandleType]
  if handle.mrPac == nil:
    handle.mrPac = new Pac[HandleType]
  elif handle.mrPac.mIsAlive:
    pac = handle.mrPac[]
  handle.mrPac.mIsAlive = true
  var res = body
  when TraceHook:
    hookLogger.log lvlInfo, &": (manu) CREATE #{idof(handle.mrPac[]):03} [" & $res & &"] : {$HandleType}"
  if pac.mIsAlive: destroy pac
  res
template impl_create[S,T](parent: Weak[S]; handle: var Uniq[T]; body): untyped {.used.} =
  template HandleType: untyped = typeof(handle).HandleType
  var pac: Pac[HandleType]
  if handle.mrPac == nil:
    handle.mrPac = new Pac[HandleType]
  elif handle.mrPac.mIsAlive:
    pac = handle.mrPac[]
  handle.mrPac.mpParent = cast[pointer](parent.mrPac)
  handle.mrPac.mIsAlive = true
  var res = body
  when TraceHook:
    hookLogger.log lvlInfo, &": (manu) CREATE #{idof(handle.mrPac[]):03} [" & $res & &"] : {$HandleType}"
  if pac.mIsAlive: destroy pac
  res
template impl_destroy[T](handle: Pac[T]; body): untyped =
  body
  handle.mIsAlive = false

proc castParentPac[T,S](handle: Pac[T]; Type: typedesc[S]): Pac[S] =
  cast[ptr Pac[S]](handle.mpParent)[]
proc castParent[T,S](handle: Pac[T]; Type: typedesc[S]): S =
  handle.castParentPac(Type).mHandle

proc setLen*[T](handle: var Uniq[seq[T]]; newSize: int) =
  if handle.mrPac == nil:
    handle.mrPac = new Pac[seq[T]]
  handle.mrPac.mHandle.setLen(newSize)

proc isAlive*[T](handle: Weak[T]): bool =
  handle.mrPac != nil and handle.mrPac.mIsAlive
proc isAlive*[T](handle: Uniq[T]): bool =
  handle.mrPac != nil and handle.mrPac.mIsAlive

proc getParentAs[T, S](handle: Weak[T]; Type: typedesc[Weak[S]]): Weak[S] {.inline, used.} =
  if not handle.isAlive: issueException()
  cast[Weak[S]](handle.mrPac.mpParent)

template destroy[T](handle: var Pac[T]) = destroy handle
proc `=destroy`[T](handle: var Uniq[T]) =
  if handle.isAlive:
    when TraceHook:
      hookLogger.log lvlInfo, &": (auto) DESTROY #{idof(handle.mrPac[]):03} : {$T}"
    destroy handle.mrPac[]
proc destroy*[T](handle: var Uniq[T]) =
  if handle.isAlive:
    when TraceHook:
      hookLogger.log lvlInfo, &": (manu) DESTROY #{idof(handle.mrPac[]):03} : {$T}"
    destroy handle.mrPac[]

converter weak*[T](handle: Uniq[T]): lent Weak[T] =
  cast[ptr Weak[T]](unsafeAddr handle)[]
converter weak*[T](handle: var Uniq[T]): lent Weak[T] =
  cast[ptr Weak[T]](addr handle)[]

converter pac*[T](handle: Uniq[T]): lent Pac[T] =
  if not handle.isAlive: issueException()
  handle.mrPac[]
converter pac*[T](handle: var Uniq[T]): lent Pac[T] =
  if not handle.isAlive: issueException()
  handle.mrPac[]
converter pac*[T](handle: Weak[T]): lent Pac[T] =
  if not handle.isAlive: issueException()
  handle.mrPac[]
converter pac*[T](handle: var Weak[T]): lent Pac[T] =
  if not handle.isAlive: issueException()
  handle.mrPac[]
proc pac*[T](handle: var Weak[T]): var Pac[T] =
  if not handle.isAlive: issueException()
  handle.mrPac[]

proc handle*[T](handle: Pac[T]): lent T = handle.mHandle
proc handle*[T](handle: var Pac[T]): var T = handle.mHandle

proc `[]`*[T](handle: Pac[T]): lent T = handle.handle
proc `[]`*[T](handle: var Pac[T]): var T = handle.handle

template `[]`*[T](handle: Pac[seq[T]], i: int): lent T = handle[][i]
template `[]`*[I,T](handle: Pac[array[I,T]], i: int): lent T = handle[][i]

proc head*[T](handle: Pac[T]): ptr T = unsafeAddr handle[]
proc head*[T](handle: Pac[seq[T]]): ptr T = unsafeAddr handle[][0]