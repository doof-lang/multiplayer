#pragma once

#include "doof_runtime.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace doof_multiplayer {

class NativeMultiplayerEvent {
public:
    NativeMultiplayerEvent(
        int32_t kind,
        std::string peerId,
        std::string displayName,
        std::string discoveryInfoText,
        std::string messageText,
        std::string error
    );

    int32_t kind() const;
    std::string peerId() const;
    std::string displayName() const;
    std::string discoveryInfoText() const;
    std::string messageText() const;
    std::string error() const;

private:
    int32_t kind_;
    std::string peerId_;
    std::string displayName_;
    std::string discoveryInfoText_;
    std::string messageText_;
    std::string error_;
};

class NativeMultiplayerSession : public std::enable_shared_from_this<NativeMultiplayerSession> {
public:
    using EventCallback = doof::callback<int32_t(std::shared_ptr<NativeMultiplayerEvent>)>;

    static doof::Result<std::shared_ptr<NativeMultiplayerSession>, std::string> create(
        const std::string& serviceType,
        const std::string& displayName,
        const std::string& discoveryInfoText,
        int32_t roleCode,
        EventCallback callback
    );

    ~NativeMultiplayerSession();

    doof::Result<void, std::string> start();
    void stop();
    doof::Result<void, std::string> invite(const std::string& peerId);
    doof::Result<void, std::string> sendText(const std::string& peerId, const std::string& text);

    class Impl;

private:
    explicit NativeMultiplayerSession(std::unique_ptr<Impl> impl);

    std::unique_ptr<Impl> impl_;
};

}  // namespace doof_multiplayer
