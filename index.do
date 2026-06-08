import { Backpressure, ChannelReceiver, ChannelSender, SendError, createChannel } from "std/event"
import { formatJsonValue, parseJsonValue } from "std/json"

import { NativeMultiplayerEvent, NativeMultiplayerSession } from "./native"

export enum MultiplayerRole {
  Host,
  Client,
}

export enum MultiplayerEventKind {
  Started,
  PeerFound,
  PeerLost,
  InviteReceived,
  PeerConnected,
  PeerDisconnected,
  MessageReceived,
  HelloReceived,
  Error,
}

export class MultiplayerConfig {
  readonly serviceType: string
  readonly protocolId: string
  readonly protocolVersion: int
  readonly displayName: string
  readonly role: MultiplayerRole
  readonly eventCapacity: int = 256
}

export class PeerInfo {
  readonly id: string
  readonly displayName: string
  readonly discoveryInfoText: string = ""
}

export class ProtocolHello {
  readonly protocolId: string
  readonly protocolVersion: int
  readonly displayName: string
  readonly role: MultiplayerRole
}

export class MultiplayerEvent {
  readonly kind: MultiplayerEventKind
  readonly peer: PeerInfo | null = null
  readonly messageText: string = ""
  readonly hello: ProtocolHello | null = null
  readonly error: string = ""
}

export class MultiplayerSession {
  readonly config: MultiplayerConfig
  readonly events: ChannelReceiver<MultiplayerEvent>
  private readonly eventSender: ChannelSender<MultiplayerEvent>
  private readonly native: NativeMultiplayerSession

  onEvent(handler: (event: MultiplayerEvent): void): MultiplayerSession {
    this.events.onMessage(handler)
    return this
  }

  start(): Result<void, string> {
    return this.native.start()
  }

  stop(): void {
    this.native.stop()
    this.events.close()
  }

  invite(peerId: string): Result<void, string> {
    return this.native.invite(peerId)
  }

  send(peerId: string, text: string): Result<void, string> {
    return this.native.sendText(peerId, text)
  }
}

export function createMultiplayerSession(config: MultiplayerConfig): Result<MultiplayerSession, string> {
  try validateAppleServiceType(config.serviceType)
  if config.eventCapacity <= 0 {
    panic("Multiplayer event capacity must be positive")
  }

  (eventSender, events) := createChannel<MultiplayerEvent>{
    capacity: config.eventCapacity,
    keepsAlive: true,
  }

  let session: MultiplayerSession | null = null
  let pendingEvents: NativeMultiplayerEvent[] = []
  nativeResult := NativeMultiplayerSession.create(
    config.serviceType,
    config.displayName,
    discoveryInfoText(config),
    roleCode(config.role),
    (event: NativeMultiplayerEvent): int => emitNativeEventWhenReady(session, pendingEvents, event),
  )

  let native: NativeMultiplayerSession | null = null
  case nativeResult {
    s: Success -> {
      native = s.value
    }
    f: Failure -> {
      events.close()
      return Failure { error: f.error }
    }
  }

  actualSession := MultiplayerSession {
    config,
    events,
    eventSender,
    native: native!,
  }
  session = actualSession

  for event of pendingEvents {
    ignored := emitNativeEvent(actualSession, event)
  }

  eventSender.onClosed((): void => actualSession.native.stop())
  return Success { value: actualSession }
}

export function validateAppleServiceType(serviceType: string): Result<void, string> {
  if serviceType.length < 1 || serviceType.length > 15 {
    return Failure("Apple service type must be 1-15 characters")
  }

  let hasLetter = false
  let previousHyphen = false
  for index of 0..<serviceType.length {
    ch := serviceType.charAt(index)
    isLetter := ch >= 'a' && ch <= 'z'
    isDigit := ch >= '0' && ch <= '9'
    isHyphen := ch == '-'
    if !isLetter && !isDigit && !isHyphen {
      return Failure("Apple service type may only contain lowercase ASCII letters, numbers, and hyphens")
    }
    if isLetter {
      hasLetter = true
    }
    if isHyphen && (index == 0 || index == serviceType.length - 1 || previousHyphen) {
      return Failure("Apple service type must not start, end, or contain adjacent hyphens")
    }
    previousHyphen = isHyphen
  }

  if !hasLetter {
    return Failure("Apple service type must contain at least one letter")
  }

  return Success()
}

export function encodeProtocolHello(hello: ProtocolHello): string {
  return formatJsonValue(hello.toJsonObject())
}

export function decodeProtocolHello(text: string): Result<ProtocolHello, string> {
  try json := parseJsonValue(text)
  return ProtocolHello.fromJsonValue(json)
}

export function validateProtocolHello(config: MultiplayerConfig, hello: ProtocolHello): Result<void, string> {
  if hello.protocolId != config.protocolId {
    return Failure("Peer protocol id '${hello.protocolId}' does not match '${config.protocolId}'")
  }
  if hello.protocolVersion != config.protocolVersion {
    return Failure("Peer protocol version ${hello.protocolVersion} does not match ${config.protocolVersion}")
  }
  return Success()
}

function discoveryInfoText(config: MultiplayerConfig): string {
  return "{\"protocolId\":\"${config.protocolId}\",\"protocolVersion\":\"${config.protocolVersion}\"}"
}

function localHello(config: MultiplayerConfig): ProtocolHello {
  return ProtocolHello {
    protocolId: config.protocolId,
    protocolVersion: config.protocolVersion,
    displayName: config.displayName,
    role: config.role,
  }
}

function roleCode(role: MultiplayerRole): int {
  return case role {
    MultiplayerRole.Host -> 0,
    MultiplayerRole.Client -> 1,
  }
}

function peerFromNative(event: NativeMultiplayerEvent): PeerInfo {
  return PeerInfo {
    id: event.peerId(),
    displayName: event.displayName(),
    discoveryInfoText: event.discoveryInfoText(),
  }
}

function emitNativeEventWhenReady(
  session: MultiplayerSession | null,
  pendingEvents: NativeMultiplayerEvent[],
  event: NativeMultiplayerEvent,
): int {
  actualSession := session else {
    pendingEvents.push(event)
    return 0
  }
  return emitNativeEvent(actualSession, event)
}

function emitNativeEvent(
  session: MultiplayerSession,
  event: NativeMultiplayerEvent,
): int {
  publicEvent := nativeEventToPublic(session, event)
  sent := session.eventSender.send(publicEvent, eventKey(publicEvent))
  return channelSendResultToNativeCode(sent)
}

function eventKey(event: MultiplayerEvent): string | null {
  if event.peer == null {
    return null
  }
  return case event.kind {
    MultiplayerEventKind.PeerFound -> "found:${event.peer!.id}",
    MultiplayerEventKind.PeerLost -> "lost:${event.peer!.id}",
    _ -> null,
  }
}

function nativeEventToPublic(
  session: MultiplayerSession,
  event: NativeMultiplayerEvent,
): MultiplayerEvent {
  return case event.kind() {
    0 -> MultiplayerEvent {
      kind: MultiplayerEventKind.Started,
    },
    1 -> MultiplayerEvent {
      kind: MultiplayerEventKind.PeerFound,
      peer: peerFromNative(event),
    },
    2 -> MultiplayerEvent {
      kind: MultiplayerEventKind.PeerLost,
      peer: peerFromNative(event),
    },
    3 -> MultiplayerEvent {
      kind: MultiplayerEventKind.InviteReceived,
      peer: peerFromNative(event),
    },
    4 -> publicConnectedEvent(session, event),
    5 -> MultiplayerEvent {
      kind: MultiplayerEventKind.PeerDisconnected,
      peer: peerFromNative(event),
    },
    6 -> publicMessageEvent(session, event),
    _ -> MultiplayerEvent {
      kind: MultiplayerEventKind.Error,
      peer: peerFromNative(event),
      error: event.error(),
    },
  }
}

function publicConnectedEvent(
  session: MultiplayerSession,
  event: NativeMultiplayerEvent,
): MultiplayerEvent {
  peer := peerFromNative(event)
  helloResult := session.native.sendText(peer.id, encodeProtocolHello(localHello(session.config)))
  case helloResult {
    _: Success -> {}
    f: Failure -> emitLocalError(session, f.error)
  }
  return MultiplayerEvent {
    kind: MultiplayerEventKind.PeerConnected,
    peer,
  }
}

function publicMessageEvent(
  session: MultiplayerSession,
  event: NativeMultiplayerEvent,
): MultiplayerEvent {
  text := event.messageText()
  peer := peerFromNative(event)
  hello := decodeProtocolHello(text)
  case hello {
    s: Success -> {
      validation := validateProtocolHello(session.config, s.value)
      case validation {
        _: Success -> {
          return MultiplayerEvent {
            kind: MultiplayerEventKind.HelloReceived,
            peer,
            messageText: text,
            hello: s.value,
          }
        }
        f: Failure -> {
          return MultiplayerEvent {
            kind: MultiplayerEventKind.Error,
            peer,
            messageText: text,
            error: f.error,
          }
        }
      }
    }
    _: Failure -> {}
  }

  return MultiplayerEvent {
    kind: MultiplayerEventKind.MessageReceived,
    peer,
    messageText: text,
  }
}

function emitLocalError(session: MultiplayerSession, error: string): void {
  ignored := session.eventSender.send(MultiplayerEvent {
    kind: MultiplayerEventKind.Error,
    error,
  })
}

function channelSendResultToNativeCode(
  sent: Result<Backpressure, SendError>,
): int {
  return case sent {
    s: Success -> case s.value {
      Backpressure.None -> 0,
      Backpressure.High -> 1,
    },
    f: Failure -> case f.error {
      SendError.Full -> 2,
      SendError.Closed -> 3,
    },
  }
}
