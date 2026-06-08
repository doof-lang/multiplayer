# std/multiplayer

`std/multiplayer` provides early peer multiplayer primitives for Doof programs.
The first backend uses Apple Multipeer Connectivity for local service discovery,
invitation, connection, and reliable UTF-8 text messages.

This module is intentionally transport-shaped: callers work with a
`MultiplayerSession`, `PeerInfo`, and events rather than directly with Apple
types, so Bonjour or pure server discovery can be added later.
