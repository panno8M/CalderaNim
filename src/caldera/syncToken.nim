import options
type
  SyncTokenUsage* = enum
    stuComponentUpdateNotice
  SyncToken*[Usage: static SyncTokenUsage] = object
    latestVer: byte
    currentVer: byte
  SyncTokenRef*[Usage: static SyncTokenUsage] = object
    target: Option[ptr SyncToken[Usage]]
    currentVer: byte

func reqSync*[Usage](this: var SyncToken[Usage]) =
  this.latestVer =
    if this.latestVer == byte.high: 0.byte
    else: this.latestVer.succ

func reqSyncIf*[Usage](this: var SyncToken[Usage]; b: bool) =
  if b: this.reqSync()

func bindto*[Usage](this: var SyncTokenRef[Usage]; target: ptr SyncToken[Usage]) =
  this.target = some target
func bindto*[Usage](this: var SyncTokenRef[Usage]; target: var SyncToken[Usage]) =
  this.bindto target.addr

template `=<<`*[Usage](this: var SyncTokenRef[Usage]; target: ptr SyncToken[Usage]) =
  this.bindto target
template `=<<`*[Usage](this: var SyncTokenRef[Usage]; target: var SyncToken[Usage]) =
  this.bindto target

func needSync*[Usage](this: SyncTokenRef[Usage]): bool =
  this.target.isSome and this.currentVer != this.target.get.latestVer

func needSync*[Usage](this: SyncToken[Usage]): bool =
  this.currentVer != this.latestVer

func updated*[Usage](this: var SyncTokenRef[Usage]) =
  if this.target.isSome:
    this.currentVer = this.target.get.latestVer

func updated*[Usage](this: var SyncToken[Usage]) =
  this.currentVer = this.latestVer

template whenSync*[Usage](this: var SyncTokenRef[Usage], body) =
  if this.needSync:
    body
    updated this

template whenSync*[Usage](this: var SyncToken[Usage], body) =
  if this.needSync:
    body
    updated this