# std/multiplayer Guide

`std/multiplayer` provides early peer multiplayer primitives. The first backend
uses Apple Multipeer Connectivity for local discovery, invitations, connections,
and reliable UTF-8 text messages.

The public API is transport-shaped rather than Apple-shaped: applications work
with sessions, peers, protocol hello messages, and events. That leaves room for
future Bonjour or server-based discovery without changing application code as
much.

## Sessions And Roles

Create a `MultiplayerConfig` with a Bonjour-compatible `serviceType`, protocol
identifier, protocol version, display name, and role. `createMultiplayerSession`
returns a `MultiplayerSession` with a bounded event receiver.

Roles are advisory at the protocol layer:

- `Host`
- `Client`

Applications can use roles to decide who invites, who accepts, or who owns game
state.

## Events

`MultiplayerEvent` reports session lifecycle, peer discovery, invitations,
connections, received text messages, decoded hello messages, and errors. Use
`session.onEvent(handler)` for convenience or subscribe to `session.events`
directly.

`send(peerId, text)` sends reliable UTF-8 text to a connected peer. Binary
payloads and unreliable datagrams are not part of the current public API.

## Protocol Hello

`ProtocolHello` identifies the application protocol. Helpers encode, decode, and
validate hellos so incompatible protocol IDs or versions can be rejected early.

`validateAppleServiceType` checks Apple's Multipeer service-type constraints
before attempting to start native discovery.

## API Map

Types:

- `MultiplayerRole`
- `MultiplayerEventKind`
- `MultiplayerConfig`
- `PeerInfo`
- `ProtocolHello`
- `MultiplayerEvent`
- `MultiplayerSession`

Helpers:

- `createMultiplayerSession`
- `validateAppleServiceType`
- `encodeProtocolHello`
- `decodeProtocolHello`
- `validateProtocolHello`

Declarations are defined in [index.do](../index.do). Native Apple bindings live
in [native.do](../native.do).
