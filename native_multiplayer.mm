#include "native_multiplayer.hpp"

#import <Foundation/Foundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>

#include <map>
#include <vector>

namespace doof_multiplayer {

namespace {

constexpr int32_t kEventStarted = 0;
constexpr int32_t kEventPeerFound = 1;
constexpr int32_t kEventPeerLost = 2;
constexpr int32_t kEventInviteReceived = 3;
constexpr int32_t kEventPeerConnected = 4;
constexpr int32_t kEventPeerDisconnected = 5;
constexpr int32_t kEventMessageReceived = 6;
constexpr int32_t kEventError = 7;

NSString* nsString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

std::string cppString(NSString* value) {
    if (value == nil) {
        return "";
    }
    return std::string([value UTF8String]);
}

std::string nsError(NSError* error, const std::string& fallback) {
    if (error == nil || [error localizedDescription] == nil) {
        return fallback;
    }
    return cppString([error localizedDescription]);
}

NSDictionary<NSString*, NSString*>* discoveryInfoFromText(const std::string& text) {
    if (text.empty()) {
        return @{};
    }

    NSData* data = [nsString(text) dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return @{};
    }

    NSError* error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSMutableDictionary<NSString*, NSString*>* result = [NSMutableDictionary dictionary];
    NSDictionary* dictionary = (NSDictionary*)object;
    for (id key in dictionary) {
        id value = [dictionary objectForKey:key];
        if ([key isKindOfClass:[NSString class]]) {
            if ([value isKindOfClass:[NSString class]]) {
                [result setObject:value forKey:key];
            } else if ([value respondsToSelector:@selector(stringValue)]) {
                [result setObject:[value stringValue] forKey:key];
            }
        }
    }
    return result;
}

std::string discoveryInfoToText(NSDictionary<NSString*, NSString*>* info) {
    if (info == nil || info.count == 0) {
        return "";
    }
    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:info options:0 error:&error];
    if (data == nil) {
        return "";
    }
    NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return cppString(text);
}

}  // namespace

class NativeMultiplayerSession::Impl {
public:
    Impl(
        std::string serviceType,
        std::string displayName,
        std::string discoveryInfoText,
        int32_t roleCode,
        NativeMultiplayerSession::EventCallback callback
    ) : serviceType_(std::move(serviceType)),
        displayName_(std::move(displayName)),
        discoveryInfoText_(std::move(discoveryInfoText)),
        roleCode_(roleCode),
        callback_(std::move(callback)) {
    }

    doof::Result<void, std::string> initialize();
    doof::Result<void, std::string> start();
    void stop();
    doof::Result<void, std::string> invite(const std::string& peerId);
    doof::Result<void, std::string> sendText(const std::string& peerId, const std::string& text);

    void emit(int32_t kind, MCPeerID* peer, NSDictionary<NSString*, NSString*>* discoveryInfo, NSString* message, NSString* error);

    NSString* serviceType() const { return nsString(serviceType_); }
    MCSession* session() const { return session_; }

    std::map<std::string, MCPeerID*> foundPeers_;

private:
    std::string serviceType_;
    std::string displayName_;
    std::string discoveryInfoText_;
    int32_t roleCode_;
    NativeMultiplayerSession::EventCallback callback_;

    MCPeerID* localPeer_ = nil;
    MCSession* session_ = nil;
    MCNearbyServiceAdvertiser* advertiser_ = nil;
    MCNearbyServiceBrowser* browser_ = nil;
    id delegate_ = nil;
    bool started_ = false;
};

}  // namespace doof_multiplayer

@interface DoofMultiplayerDelegate : NSObject <MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate>
- (instancetype)initWithImpl:(doof_multiplayer::NativeMultiplayerSession::Impl*)impl;
@end

@implementation DoofMultiplayerDelegate {
    doof_multiplayer::NativeMultiplayerSession::Impl* _impl;
}

- (instancetype)initWithImpl:(doof_multiplayer::NativeMultiplayerSession::Impl*)impl {
    self = [super init];
    if (self != nil) {
        _impl = impl;
    }
    return self;
}

- (void)advertiser:(MCNearbyServiceAdvertiser*)advertiser didReceiveInvitationFromPeer:(MCPeerID*)peerID withContext:(NSData*)context invitationHandler:(void (^)(BOOL accept, MCSession* session))invitationHandler {
    _impl->emit(doof_multiplayer::kEventInviteReceived, peerID, nil, nil, nil);
    invitationHandler(YES, _impl->session());
}

- (void)advertiser:(MCNearbyServiceAdvertiser*)advertiser didNotStartAdvertisingPeer:(NSError*)error {
    _impl->emit(doof_multiplayer::kEventError, nil, nil, nil, [error localizedDescription]);
}

- (void)browser:(MCNearbyServiceBrowser*)browser foundPeer:(MCPeerID*)peerID withDiscoveryInfo:(NSDictionary<NSString*, NSString*>*)info {
    _impl->foundPeers_[doof_multiplayer::cppString(peerID.displayName)] = peerID;
    _impl->emit(doof_multiplayer::kEventPeerFound, peerID, info, nil, nil);
}

- (void)browser:(MCNearbyServiceBrowser*)browser lostPeer:(MCPeerID*)peerID {
    _impl->foundPeers_.erase(doof_multiplayer::cppString(peerID.displayName));
    _impl->emit(doof_multiplayer::kEventPeerLost, peerID, nil, nil, nil);
}

- (void)browser:(MCNearbyServiceBrowser*)browser didNotStartBrowsingForPeers:(NSError*)error {
    _impl->emit(doof_multiplayer::kEventError, nil, nil, nil, [error localizedDescription]);
}

- (void)session:(MCSession*)session peer:(MCPeerID*)peerID didChangeState:(MCSessionState)state {
    if (state == MCSessionStateConnected) {
        _impl->emit(doof_multiplayer::kEventPeerConnected, peerID, nil, nil, nil);
    } else if (state == MCSessionStateNotConnected) {
        _impl->emit(doof_multiplayer::kEventPeerDisconnected, peerID, nil, nil, nil);
    }
}

- (void)session:(MCSession*)session didReceiveData:(NSData*)data fromPeer:(MCPeerID*)peerID {
    NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    _impl->emit(doof_multiplayer::kEventMessageReceived, peerID, nil, text, nil);
}

- (void)session:(MCSession*)session didReceiveStream:(NSInputStream*)stream withName:(NSString*)streamName fromPeer:(MCPeerID*)peerID {
}

- (void)session:(MCSession*)session didStartReceivingResourceWithName:(NSString*)resourceName fromPeer:(MCPeerID*)peerID withProgress:(NSProgress*)progress {
}

- (void)session:(MCSession*)session didFinishReceivingResourceWithName:(NSString*)resourceName fromPeer:(MCPeerID*)peerID atURL:(NSURL*)localURL withError:(NSError*)error {
}

@end

namespace doof_multiplayer {

doof::Result<void, std::string> NativeMultiplayerSession::Impl::initialize() {
    @try {
        localPeer_ = [[MCPeerID alloc] initWithDisplayName:nsString(displayName_)];
        session_ = [[MCSession alloc] initWithPeer:localPeer_ securityIdentity:nil encryptionPreference:MCEncryptionRequired];
        delegate_ = [[DoofMultiplayerDelegate alloc] initWithImpl:this];
        session_.delegate = delegate_;

        if (roleCode_ == 0) {
            advertiser_ = [[MCNearbyServiceAdvertiser alloc]
                initWithPeer:localPeer_
                discoveryInfo:discoveryInfoFromText(discoveryInfoText_)
                serviceType:nsString(serviceType_)];
            advertiser_.delegate = delegate_;
        } else {
            browser_ = [[MCNearbyServiceBrowser alloc]
                initWithPeer:localPeer_
                serviceType:nsString(serviceType_)];
            browser_.delegate = delegate_;
        }
    } @catch (NSException* exception) {
        return doof::Failure<std::string>{cppString(exception.reason)};
    }

    return doof::Success<void>{};
}

doof::Result<void, std::string> NativeMultiplayerSession::Impl::start() {
    if (started_) {
        return doof::Success<void>{};
    }
    started_ = true;
    if (advertiser_ != nil) {
        [advertiser_ startAdvertisingPeer];
    }
    if (browser_ != nil) {
        [browser_ startBrowsingForPeers];
    }
    emit(kEventStarted, nil, nil, nil, nil);
    return doof::Success<void>{};
}

void NativeMultiplayerSession::Impl::stop() {
    if (!started_ && advertiser_ == nil && browser_ == nil && session_ == nil) {
        return;
    }
    started_ = false;
    [advertiser_ stopAdvertisingPeer];
    [browser_ stopBrowsingForPeers];
    [session_ disconnect];
    advertiser_.delegate = nil;
    browser_.delegate = nil;
    session_.delegate = nil;
    advertiser_ = nil;
    browser_ = nil;
    session_ = nil;
    localPeer_ = nil;
    delegate_ = nil;
    foundPeers_.clear();
}

doof::Result<void, std::string> NativeMultiplayerSession::Impl::invite(const std::string& peerId) {
    if (browser_ == nil) {
        return doof::Failure<std::string>{"Only browsing clients can invite peers"};
    }
    auto it = foundPeers_.find(peerId);
    if (it == foundPeers_.end()) {
        return doof::Failure<std::string>{"Peer is not currently discoverable: " + peerId};
    }
    [browser_ invitePeer:it->second toSession:session_ withContext:nil timeout:30.0];
    return doof::Success<void>{};
}

doof::Result<void, std::string> NativeMultiplayerSession::Impl::sendText(const std::string& peerId, const std::string& text) {
    if (session_ == nil) {
        return doof::Failure<std::string>{"Session is closed"};
    }

    NSMutableArray<MCPeerID*>* targets = [NSMutableArray array];
    for (MCPeerID* peer in session_.connectedPeers) {
        if (peerId.empty() || cppString(peer.displayName) == peerId) {
            [targets addObject:peer];
        }
    }

    if (targets.count == 0) {
        return doof::Failure<std::string>{"Peer is not connected: " + peerId};
    }

    NSData* data = [nsString(text) dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error = nil;
    BOOL ok = [session_ sendData:data toPeers:targets withMode:MCSessionSendDataReliable error:&error];
    if (!ok) {
        return doof::Failure<std::string>{nsError(error, "Failed to send message")};
    }

    return doof::Success<void>{};
}

void NativeMultiplayerSession::Impl::emit(int32_t kind, MCPeerID* peer, NSDictionary<NSString*, NSString*>* discoveryInfo, NSString* message, NSString* error) {
    std::string peerId;
    std::string displayName;
    if (peer != nil) {
        peerId = cppString(peer.displayName);
        displayName = cppString(peer.displayName);
    }

    auto event = std::make_shared<NativeMultiplayerEvent>(
        kind,
        peerId,
        displayName,
        discoveryInfoToText(discoveryInfo),
        cppString(message),
        cppString(error)
    );
    (void)callback_.call(event);
}

NativeMultiplayerEvent::NativeMultiplayerEvent(
    int32_t kind,
    std::string peerId,
    std::string displayName,
    std::string discoveryInfoText,
    std::string messageText,
    std::string error
) : kind_(kind),
    peerId_(std::move(peerId)),
    displayName_(std::move(displayName)),
    discoveryInfoText_(std::move(discoveryInfoText)),
    messageText_(std::move(messageText)),
    error_(std::move(error)) {
}

int32_t NativeMultiplayerEvent::kind() const { return kind_; }
std::string NativeMultiplayerEvent::peerId() const { return peerId_; }
std::string NativeMultiplayerEvent::displayName() const { return displayName_; }
std::string NativeMultiplayerEvent::discoveryInfoText() const { return discoveryInfoText_; }
std::string NativeMultiplayerEvent::messageText() const { return messageText_; }
std::string NativeMultiplayerEvent::error() const { return error_; }

doof::Result<std::shared_ptr<NativeMultiplayerSession>, std::string> NativeMultiplayerSession::create(
    const std::string& serviceType,
    const std::string& displayName,
    const std::string& discoveryInfoText,
    int32_t roleCode,
    NativeMultiplayerSession::EventCallback callback
) {
    if (displayName.empty()) {
        return doof::Failure<std::string>{"Display name must not be empty"};
    }
    if (roleCode != 0 && roleCode != 1) {
        return doof::Failure<std::string>{"Unknown multiplayer role"};
    }

    auto impl = std::make_unique<Impl>(serviceType, displayName, discoveryInfoText, roleCode, std::move(callback));
    auto initialized = impl->initialize();
    if (doof::is_failure(initialized)) {
        return doof::Failure<std::string>{doof::failure_error(initialized)};
    }

    return doof::Success<std::shared_ptr<NativeMultiplayerSession>>{std::shared_ptr<NativeMultiplayerSession>(new NativeMultiplayerSession(std::move(impl)))};
}

NativeMultiplayerSession::NativeMultiplayerSession(std::unique_ptr<Impl> impl)
    : impl_(std::move(impl)) {
}

NativeMultiplayerSession::~NativeMultiplayerSession() {
    stop();
}

doof::Result<void, std::string> NativeMultiplayerSession::start() {
    return impl_->start();
}

void NativeMultiplayerSession::stop() {
    if (impl_) {
        impl_->stop();
    }
}

doof::Result<void, std::string> NativeMultiplayerSession::invite(const std::string& peerId) {
    return impl_->invite(peerId);
}

doof::Result<void, std::string> NativeMultiplayerSession::sendText(const std::string& peerId, const std::string& text) {
    return impl_->sendText(peerId, text);
}

}  // namespace doof_multiplayer
