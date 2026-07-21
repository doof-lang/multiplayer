export import class NativeMultiplayerEvent from "./native_multiplayer.hpp" as doof_multiplayer::NativeMultiplayerEvent {
  isolated kind(): int
  isolated peerId(): string
  isolated displayName(): string
  isolated discoveryInfoText(): string
  isolated messageText(): string
  isolated error(): string
}

export import class NativeMultiplayerSession from "./native_multiplayer.hpp" as doof_multiplayer::NativeMultiplayerSession {
  static create(
    serviceType: string,
    displayName: string,
    discoveryInfoText: string,
    roleCode: int,
    callback: (event: NativeMultiplayerEvent): int,
  ): Result<NativeMultiplayerSession, string>

  start(): Result<none, string>
  stop(): none
  invite(peerId: string): Result<none, string>
  sendText(peerId: string, text: string): Result<none, string>
}
