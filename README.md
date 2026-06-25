# std/multiplayer

`std/multiplayer` provides early peer multiplayer primitives for Doof programs.
The first backend uses Apple Multipeer Connectivity for local service discovery,
invitation, connection, and reliable UTF-8 text messages.

This module is intentionally transport-shaped: callers work with a
`MultiplayerSession`, `PeerInfo`, and events rather than directly with Apple
types, so Bonjour or pure server discovery can be added later.

## Documentation

- [Guide and API reference](docs/API.md) explains session roles, Apple service validation, events, protocol hello validation, and the current backend scope.
- Tests can be run with `doof test multiplayer`.
