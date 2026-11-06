#include "include/kinetic_player/kinetic_player_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <windows.h>

#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "mpv_player.h"

namespace kinetic_player {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr UINT kKineticPostMsg = WM_APP + 0x6B70;

struct PostedFn {
  std::function<void()> fn;
};

const EncodableMap* AsMap(const EncodableValue* value) {
  return value ? std::get_if<EncodableMap>(value) : nullptr;
}

const EncodableValue* MapAt(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(std::string(key)));
  return it == map.end() ? nullptr : &it->second;
}

std::string GetString(const EncodableMap& map, const char* key,
                      const std::string& fallback = {}) {
  const auto* v = MapAt(map, key);
  if (!v) return fallback;
  if (const auto* s = std::get_if<std::string>(v)) return *s;
  return fallback;
}

bool GetBool(const EncodableMap& map, const char* key, bool fallback) {
  const auto* v = MapAt(map, key);
  if (!v) return fallback;
  if (const auto* b = std::get_if<bool>(v)) return *b;
  return fallback;
}

int64_t GetInt(const EncodableMap& map, const char* key, int64_t fallback) {
  const auto* v = MapAt(map, key);
  if (!v) return fallback;
  if (const auto* i = std::get_if<int32_t>(v)) return *i;
  if (const auto* i = std::get_if<int64_t>(v)) return *i;
  return fallback;
}

double GetDouble(const EncodableMap& map, const char* key, double fallback) {
  const auto* v = MapAt(map, key);
  if (!v) return fallback;
  if (const auto* d = std::get_if<double>(v)) return *d;
  if (const auto* i = std::get_if<int32_t>(v)) return *i;
  if (const auto* i = std::get_if<int64_t>(v)) return static_cast<double>(*i);
  return fallback;
}

std::vector<std::string> GetStringList(const EncodableMap& map, const char* key) {
  std::vector<std::string> out;
  const auto* v = MapAt(map, key);
  const auto* list = v ? std::get_if<EncodableList>(v) : nullptr;
  if (!list) return out;
  for (const auto& item : *list) {
    if (const auto* s = std::get_if<std::string>(&item)) {
      if (!s->empty()) out.push_back(*s);
    }
  }
  return out;
}

std::vector<std::pair<std::string, std::string>> GetHeaderPairs(
    const EncodableMap& map, const char* key) {
  std::vector<std::pair<std::string, std::string>> out;
  const auto* v = MapAt(map, key);
  const auto* headers = v ? std::get_if<EncodableMap>(v) : nullptr;
  if (!headers) return out;
  for (const auto& entry : *headers) {
    const auto* k = std::get_if<std::string>(&entry.first);
    if (!k || k->empty()) continue;
    if (const auto* s = std::get_if<std::string>(&entry.second)) {
      out.emplace_back(*k, *s);
    }
  }
  return out;
}

void ApplyHttpRequestOptions(kinetic::MpvPlayer* player,
                             const EncodableMap& map) {
  player->SetHttpRequestOptions(GetString(map, "userAgent"),
                                GetHeaderPairs(map, "headers"));
}

const EncodableMap* UiMap(const EncodableMap& args) {
  const auto* ui = MapAt(args, "ui");
  return AsMap(ui);
}

void ApplyCreateOptions(kinetic::MpvPlayer* player, const EncodableMap& args) {
  const EncodableMap* ui = UiMap(args);
  const EncodableMap& src = ui ? *ui : args;
  player->SetRate(GetDouble(src, "speed", 1.0));
  player->SetLooping(GetBool(src, "looping", false));
  player->SetKeepLastFrame(GetBool(src, "keepLastFrameWhenComplete", false));
  player->SetSeekOnStartMs(GetInt(src, "seekOnStartMs", -1));
  player->SetAutoPlayNext(GetBool(src, "autoPlayNext", true));
  ApplyHttpRequestOptions(player, args);
  const bool auto_play = GetBool(src, "startAfterPrepared", true);
  auto playlist = GetStringList(args, "playlist");
  if (!playlist.empty()) {
    player->SetPlaylist(playlist,
                        static_cast<int>(GetInt(args, "playlistStartIndex", 0)),
                        auto_play);
    return;
  }
  const std::string url = GetString(args, "url");
  if (!url.empty()) {
    player->Load(url, auto_play);
  }
}

EncodableList TracksValue(const std::vector<kinetic::MpvAudioTrack>& tracks) {
  EncodableList list;
  for (const auto& t : tracks) {
    list.push_back(EncodableValue(EncodableMap{
        {EncodableValue("index"), EncodableValue(t.index)},
        {EncodableValue("label"), EncodableValue(t.label)},
        {EncodableValue("language"), EncodableValue(t.language)},
        {EncodableValue("selected"), EncodableValue(t.selected)},
    }));
  }
  return list;
}

EncodableList VideoTracksValue(
    const std::vector<kinetic::MpvVideoTrack>& tracks) {
  EncodableList list;
  for (const auto& t : tracks) {
    list.push_back(EncodableValue(EncodableMap{
        {EncodableValue("index"), EncodableValue(t.index)},
        {EncodableValue("label"), EncodableValue(t.label)},
        {EncodableValue("language"), EncodableValue(t.language)},
        {EncodableValue("selected"), EncodableValue(t.selected)},
        {EncodableValue("width"), EncodableValue(t.width)},
        {EncodableValue("height"), EncodableValue(t.height)},
        {EncodableValue("bitrate"), EncodableValue(t.bitrate)},
    }));
  }
  return list;
}

WINDOWPLACEMENT g_window_placement = {sizeof(g_window_placement)};

bool IsFullscreen(HWND hwnd) {
  const LONG style = GetWindowLong(hwnd, GWL_STYLE);
  return (style & WS_OVERLAPPEDWINDOW) == 0;
}

void ToggleFullscreen(HWND hwnd) {
  if (!hwnd) return;
  const LONG style = GetWindowLong(hwnd, GWL_STYLE);
  if (style & WS_OVERLAPPEDWINDOW) {
    MONITORINFO mi = {sizeof(mi)};
    if (GetWindowPlacement(hwnd, &g_window_placement) &&
        GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY),
                       &mi)) {
      SetWindowLong(hwnd, GWL_STYLE, style & ~WS_OVERLAPPEDWINDOW);
      SetWindowPos(hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                   mi.rcMonitor.right - mi.rcMonitor.left,
                   mi.rcMonitor.bottom - mi.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    }
  } else {
    SetWindowLong(hwnd, GWL_STYLE, style | WS_OVERLAPPEDWINDOW);
    SetWindowPlacement(hwnd, &g_window_placement);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
  }
}

class PlayerSlot {
 public:
  PlayerSlot(int view_id, flutter::PluginRegistrarWindows* registrar,
             HWND hwnd)
      : view_id_(view_id), registrar_(registrar), hwnd_(hwnd) {
    player_ = std::make_unique<kinetic::MpvPlayer>();
    texture_ = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture(
            [this](size_t width, size_t height)
                -> const FlutterDesktopPixelBuffer* {
              return CopyPixelBuffer(width, height);
            }));
    texture_id_ = registrar->texture_registrar()->RegisterTexture(texture_.get());

    const auto channel_name =
        "com.example.player/mpv_" + std::to_string(view_id_);
    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar->messenger(), channel_name,
        &flutter::StandardMethodCodec::GetInstance());
  }

  ~PlayerSlot() { Destroy(); }

  bool Init(flutter::PluginRegistrarWindows* registrar) {
    kinetic::MpvPlayer::Callbacks cb;
    cb.post_to_ui = [this](std::function<void()> fn) { PostUi(std::move(fn)); };
    cb.on_state = [this](int state) {
      channel_->InvokeMethod(
          "onPlayerStateChanged",
          std::make_unique<EncodableValue>(EncodableMap{
              {EncodableValue("state"), EncodableValue(state)},
          }));
    };
    cb.on_position = [this](int64_t pos, int64_t dur, int64_t buf) {
      channel_->InvokeMethod(
          "onPositionChanged",
          std::make_unique<EncodableValue>(EncodableMap{
              {EncodableValue("position"), EncodableValue(pos)},
              {EncodableValue("duration"), EncodableValue(dur)},
              {EncodableValue("buffered"), EncodableValue(buf)},
          }));
    };
    cb.on_error = [this](const std::string& message, int code) {
      channel_->InvokeMethod(
          "onPlayerError",
          std::make_unique<EncodableValue>(EncodableMap{
              {EncodableValue("message"), EncodableValue(message)},
              {EncodableValue("code"), EncodableValue(code)},
          }));
    };
    cb.on_frame = [this]() {
      registrar_->texture_registrar()->MarkTextureFrameAvailable(texture_id_);
    };
    if (!player_->Init(std::move(cb))) {
      return false;
    }
    channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) { Handle(call, std::move(result)); });
    return true;
  }

  void Destroy() {
    if (destroyed_) return;
    destroyed_ = true;
    if (channel_) {
      channel_->SetMethodCallHandler(nullptr);
    }
    if (player_) {
      player_->Shutdown();
    }
    if (texture_id_ >= 0 && registrar_) {
      registrar_->texture_registrar()->UnregisterTexture(texture_id_);
      texture_id_ = -1;
    }
    player_.reset();
    texture_.reset();
  }

  int64_t texture_id() const { return texture_id_; }

  void ApplyCreate(const EncodableMap& args) {
    ApplyCreateOptions(player_.get(), args);
  }

  void Handle(const flutter::MethodCall<EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto& method = call.method_name();
    const auto* args = AsMap(call.arguments());
    const EncodableMap empty;
    const EncodableMap& map = args ? *args : empty;

    if (method == "play") {
      player_->Play();
      result->Success();
    } else if (method == "pause") {
      player_->Pause();
      result->Success();
    } else if (method == "stop") {
      player_->Stop();
      result->Success();
    } else if (method == "seekTo") {
      player_->SeekToMs(GetInt(map, "position", 0));
      result->Success();
    } else if (method == "setScaleMode") {
      player_->SetScaleMode(static_cast<int>(GetInt(map, "mode", 0)));
      result->Success();
    } else if (method == "setRate") {
      player_->SetRate(GetDouble(map, "rate", 1));
      result->Success();
    } else if (method == "setVolume") {
      player_->SetVolume(GetDouble(map, "volume", 1));
      result->Success();
    } else if (method == "setMute") {
      player_->SetMute(GetBool(map, "muted", false));
      result->Success();
    } else if (method == "switchVideoSource") {
      player_->Load(GetString(map, "url"), GetBool(map, "autoPlay", true));
      result->Success();
    } else if (method == "getAudioTracks") {
      result->Success(EncodableValue(TracksValue(player_->GetAudioTracks())));
    } else if (method == "selectAudioTrack") {
      if (player_->SelectAudioTrack(static_cast<int>(GetInt(map, "index", 0)))) {
        result->Success();
      } else {
        result->Error("TRACK", "Audio track not found");
      }
    } else if (method == "getVideoSize") {
      const auto size = player_->GetVideoSize();
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("width"), EncodableValue(size.width)},
          {EncodableValue("height"), EncodableValue(size.height)},
      }));
    } else if (method == "getVideoMetadata") {
      const auto size = player_->GetVideoSize();
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("width"), EncodableValue(size.width)},
          {EncodableValue("height"), EncodableValue(size.height)},
          {EncodableValue("duration"), EncodableValue(player_->GetDurationMs())},
      }));
    } else if (method == "setLooping") {
      player_->SetLooping(GetBool(map, "looping", false));
      result->Success();
    } else if (method == "setLocale") {
      result->Success();
    } else if (method == "setHttpRequestOptions") {
      ApplyHttpRequestOptions(player_.get(), map);
      result->Success();
    } else if (method == "captureFrame") {
      auto png = player_->CapturePng();
      if (png.empty()) {
        result->Success();
      } else {
        result->Success(EncodableValue(std::move(png)));
      }
    } else if (method == "mpvStartFullscreen") {
      ToggleFullscreen(hwnd_);
      result->Success();
    } else if (method == "mpvExitFullscreen") {
      if (IsFullscreen(hwnd_)) ToggleFullscreen(hwnd_);
      result->Success();
    } else if (method == "mpvIsFullscreen") {
      result->Success(EncodableValue(IsFullscreen(hwnd_)));
    } else if (method == "mpvSetHwdec") {
      player_->SetHwdec(GetString(map, "hwdec"));
      result->Success();
    } else if (method == "mpvCommand") {
      const auto* list_v = MapAt(map, "args");
      std::vector<std::string> cmd;
      if (const auto* list = list_v ? std::get_if<EncodableList>(list_v)
                                    : nullptr) {
        for (const auto& item : *list) {
          if (const auto* s = std::get_if<std::string>(&item)) {
            cmd.push_back(*s);
          }
        }
      }
      player_->Command(cmd);
      result->Success();
    } else if (method == "mpvSetKeepLastFrameWhenComplete") {
      player_->SetKeepLastFrame(GetBool(map, "enabled", false));
      result->Success();
    } else if (method == "mpvSetRenderRotation") {
      player_->SetRotation(static_cast<int>(GetInt(map, "degrees", 0)));
      result->Success();
    } else if (method == "mpvSetMirrorHorizontal") {
      player_->SetMirrorHorizontal(GetBool(map, "enabled", false));
      result->Success();
    } else if (method == "mpvSetMirrorVertical") {
      player_->SetMirrorVertical(GetBool(map, "enabled", false));
      result->Success();
    } else if (method == "mpvSetShowType") {
      player_->SetShowType(static_cast<int>(GetInt(map, "mode", 0)));
      result->Success();
    } else if (method == "mpvSetPlaylist") {
      player_->SetPlaylist(GetStringList(map, "urls"),
                           static_cast<int>(GetInt(map, "startIndex", 0)),
                           true);
      result->Success();
    } else if (method == "mpvPlayNextInPlaylist") {
      result->Success(EncodableValue(player_->PlayNextInPlaylist()));
    } else if (method == "mpvSetAutoPlayNext") {
      player_->SetAutoPlayNext(GetBool(map, "enabled", true));
      result->Success();
    } else if (method == "mpvSetSubtitleUrl") {
      player_->SetSubtitleUrl(GetString(map, "url"));
      result->Success();
    } else if (method == "mpvSetSubtitleEnabled") {
      player_->SetSubtitleEnabled(GetBool(map, "enabled", true));
      result->Success();
    } else if (method == "mpvListVideoTracks") {
      result->Success(EncodableValue(VideoTracksValue(player_->GetVideoTracks())));
    } else if (method == "mpvSelectVideoTrack") {
      result->Success(EncodableValue(player_->SelectVideoTrack(
          static_cast<int>(GetInt(map, "index", -1)))));
    } else if (method == "mpvGetNetSpeed") {
      const auto speed = player_->GetNetSpeed();
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("bytesPerSecond"),
           EncodableValue(speed.bytes_per_second)},
          {EncodableValue("text"), EncodableValue(speed.text)},
      }));
    } else if (method == "mpvSetCoverUrl" || method == "mpvSetWatermarkUrl" ||
               method == "mpvSetPurePlayMode" || method == "mpvSetUiConfig" ||
               method == "dispose") {
      if (method == "dispose") {
        Destroy();
      }
      result->Success();
    } else {
      result->NotImplemented();
    }
  }

 private:
  void PostUi(std::function<void()> fn) {
    auto* posted = new PostedFn{std::move(fn)};
    if (!hwnd_ || !PostMessage(hwnd_, kKineticPostMsg, 0,
                               reinterpret_cast<LPARAM>(posted))) {
      delete posted;
    }
  }

  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width,
                                                   size_t height) {
    player_->SetOutputSize(static_cast<int>(width), static_cast<int>(height));
    std::vector<uint8_t> rgba;
    int w = 0, h = 0;
    if (!player_->CopyRgbaFrame(rgba, w, h) || rgba.empty()) {
      return nullptr;
    }
    std::lock_guard<std::mutex> lock(pixel_mu_);
    bgra_.resize(rgba.size());
    for (size_t i = 0; i < rgba.size(); i += 4) {
      bgra_[i + 0] = rgba[i + 2];
      bgra_[i + 1] = rgba[i + 1];
      bgra_[i + 2] = rgba[i + 0];
      bgra_[i + 3] = rgba[i + 3];
    }
    pixel_buffer_.buffer = bgra_.data();
    pixel_buffer_.width = static_cast<size_t>(w);
    pixel_buffer_.height = static_cast<size_t>(h);
    pixel_buffer_.release_callback = nullptr;
    pixel_buffer_.release_context = nullptr;
    return &pixel_buffer_;
  }

  int view_id_ = 0;
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  HWND hwnd_ = nullptr;
  std::unique_ptr<kinetic::MpvPlayer> player_;
  std::unique_ptr<flutter::TextureVariant> texture_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  int64_t texture_id_ = -1;
  bool destroyed_ = false;
  std::mutex pixel_mu_;
  std::vector<uint8_t> bgra_;
  FlutterDesktopPixelBuffer pixel_buffer_{};
};

class KineticPlayerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<KineticPlayerPlugin>(registrar);
    registrar->AddPlugin(std::move(plugin));
  }

  explicit KineticPlayerPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar) {
    if (registrar_->GetView()) {
      hwnd_ = registrar_->GetView()->GetNativeWindow();
    }
    window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [](HWND, UINT message, WPARAM, LPARAM lparam) -> std::optional<LRESULT> {
          if (message != kKineticPostMsg) {
            return std::nullopt;
          }
          auto* posted = reinterpret_cast<PostedFn*>(lparam);
          if (posted) {
            posted->fn();
            delete posted;
          }
          return 0;
        });

    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar_->messenger(), "com.example.player/mpv",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandlePlugin(call, std::move(result));
        });
  }

  ~KineticPlayerPlugin() override {
    for (auto& [id, slot] : players_) {
      slot->Destroy();
    }
    players_.clear();
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }

 private:
  void HandlePlugin(const flutter::MethodCall<EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto& method = call.method_name();
    const auto* args = AsMap(call.arguments());
    const EncodableMap empty;
    const EncodableMap& map = args ? *args : empty;

    if (method == "create") {
      const int view_id = next_id_++;
      auto slot = std::make_unique<PlayerSlot>(view_id, registrar_, hwnd_);
      if (!slot->Init(registrar_)) {
        result->Error("MPV", "Failed to initialize libmpv");
        return;
      }
      slot->ApplyCreate(map);
      const int64_t texture_id = slot->texture_id();
      players_[view_id] = std::move(slot);
      if (GetBool(map, "controllerOwned", false)) controller_players_.insert(view_id);
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("viewId"), EncodableValue(view_id)},
          {EncodableValue("textureId"), EncodableValue(texture_id)},
      }));
    } else if (method == "reset") {
      for (const auto id : controller_players_) {
        auto it = players_.find(id);
        if (it != players_.end()) {
          it->second->Destroy();
          players_.erase(it);
        }
      }
      controller_players_.clear();
      result->Success();
    } else if (method == "destroy") {
      const int view_id = static_cast<int>(GetInt(map, "viewId", -1));
      auto it = players_.find(view_id);
      controller_players_.erase(view_id);
      if (it != players_.end()) {
        it->second->Destroy();
        players_.erase(it);
      }
      result->Success();
    } else {
      result->NotImplemented();
    }
  }

  flutter::PluginRegistrarWindows* registrar_;
  HWND hwnd_ = nullptr;
  int window_proc_id_ = 0;
  int next_id_ = 1;
  std::map<int, std::unique_ptr<PlayerSlot>> players_;
  std::set<int> controller_players_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
};

}  // namespace

}  // namespace kinetic_player

void KineticPlayerPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  kinetic_player::KineticPlayerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
