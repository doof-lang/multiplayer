import { Assert } from "std/assert"

import {
  MultiplayerConfig,
  MultiplayerRole,
  ProtocolHello,
  decodeProtocolHello,
  encodeProtocolHello,
  validateAppleServiceType,
  validateProtocolHello,
} from "../index"

function assertValidServiceType(serviceType: string): none {
  result := validateAppleServiceType(serviceType)
  case result {
    _: Success -> {}
    f: Failure -> Assert.fail(f.error)
  }
}

function assertInvalidServiceType(serviceType: string): none {
  result := validateAppleServiceType(serviceType)
  case result {
    _: Success -> Assert.fail("Expected invalid service type: ${serviceType}")
    _: Failure -> {}
  }
}

function testConfig(): MultiplayerConfig {
  return MultiplayerConfig {
    serviceType: "doof-jigsaw",
    protocolId: "dev.doof.jigsaw",
    protocolVersion: 1,
    displayName: "Tester",
    role: MultiplayerRole.Host,
  }
}

export function testValidateAppleServiceTypeAcceptsBonjourStyleName(): none {
  assertValidServiceType("doof-jigsaw")
  assertValidServiceType("a1")
  assertValidServiceType("abc-123")
}

export function testValidateAppleServiceTypeRejectsInvalidNames(): none {
  assertInvalidServiceType("")
  assertInvalidServiceType("doof-jigsaw-peer")
  assertInvalidServiceType("Doof")
  assertInvalidServiceType("-doof")
  assertInvalidServiceType("doof-")
  assertInvalidServiceType("doof--jig")
  assertInvalidServiceType("123")
  assertInvalidServiceType("doof_jigsaw")
}

export function testProtocolHelloRoundTripsThroughJson(): none {
  hello := ProtocolHello {
    protocolId: "dev.doof.jigsaw",
    protocolVersion: 1,
    displayName: "Alice",
    role: MultiplayerRole.Client,
  }

  decoded := try! decodeProtocolHello(encodeProtocolHello(hello))
  Assert.equal(decoded.protocolId, hello.protocolId)
  Assert.equal(decoded.protocolVersion, hello.protocolVersion)
  Assert.equal(decoded.displayName, hello.displayName)
  Assert.equal(decoded.role, hello.role)
}

export function testValidateProtocolHelloAcceptsMatchingProtocol(): none {
  config := testConfig()
  hello := ProtocolHello {
    protocolId: config.protocolId,
    protocolVersion: config.protocolVersion,
    displayName: "Peer",
    role: MultiplayerRole.Client,
  }

  result := validateProtocolHello(config, hello)
  case result {
    _: Success -> {}
    f: Failure -> Assert.fail(f.error)
  }
}

export function testValidateProtocolHelloRejectsMismatches(): none {
  config := testConfig()
  wrongId := ProtocolHello {
    protocolId: "other",
    protocolVersion: config.protocolVersion,
    displayName: "Peer",
    role: MultiplayerRole.Client,
  }
  wrongVersion := ProtocolHello {
    protocolId: config.protocolId,
    protocolVersion: 2,
    displayName: "Peer",
    role: MultiplayerRole.Client,
  }

  case validateProtocolHello(config, wrongId) {
    _: Success -> Assert.fail("Expected protocol id mismatch")
    _: Failure -> {}
  }
  case validateProtocolHello(config, wrongVersion) {
    _: Success -> Assert.fail("Expected protocol version mismatch")
    _: Failure -> {}
  }
}
