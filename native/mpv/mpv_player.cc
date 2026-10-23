#include "mpv_player.h"

#include "png_encode.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <initializer_list>
#include <string>
#include <utility>

#include "mpv/client.h"
#include "mpv/render.h"

namespace kinetic {
namespace {

constexpr int kStateIdle = 0;
constexpr int kStateBuffering = 1;
constexpr int kStateReady = 2;
constexpr int kStatePlaying = 3;
constexpr int kStatePaused = 4;
constexpr int kStateCompleted = 5;
constexpr int kStateError = 6;
constexpr int64_t kProgressIntervalMs = 250;

const char* NodeString(mpv_node* node) {
  if (!node || node->format != MPV_FORMAT_STRING || !node->u.string) {
    return "";
  }
  return node->u.string;
}

bool NodeFlag(mpv_node* node, bool fallback = false) {
  if (!node) return fallback;
  if (node->format == MPV_FORMAT_FLAG) return node->u.flag != 0;
  return fallback;
}

int64_t NodeInt(mpv_node* node, int64_t fallback = 0) {
  if (!node) return fallback;
  if (node->format == MPV_FORMAT_INT64) return node->u.int64;
  if (node->format == MPV_FORMAT_DOUBLE) {
    return static_cast<int64_t>(node->u.double_);
  }
  return fallback;
}

mpv_node* MapGet(mpv_node* map, const char* key) {
  if (!map || map->format != MPV_FORMAT_NODE_MAP || !map->u.list) {
    return nullptr;
  }
  mpv_node_list* list = map->u.list;
  for (int i = 0; i < list->num; i++) {
    if (list->keys[i] && std::strcmp(list->keys[i], key) == 0) {
      return &list->values[i];
    }
  }
  return nullptr;
}

}  // namespace

MpvPlayer::~MpvPlayer() { Shutdown(); }

bool MpvPlayer::Init(Callbacks callbacks) {
  Shutdown();
  cb_ = std::move(callbacks);
  mpv_ = mpv_create();
  if (!mpv_) {
    return false;
  }

  SetOption("terminal", "no");
  SetOption("msg-level", "all=no");
  SetOption("osc", "no");
  SetOption("osd-level", "0");
  SetOption("input-default-bindings", "no");
  SetOption("input-vo-keyboard", "no");
  SetOption("vo", "libmpv");
  SetOption("hwdec", "auto-safe");
  SetOption("keep-open", "yes");
  SetOption("idle", "yes");
  SetOption("sw-fast", "yes");
  SetOption("video-timing-offset", "0");

  if (mpv_initialize(mpv_) < 0) {
    mpv_destroy(mpv_);
    mpv_ = nullptr;
    return false;
  }

  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_SW)},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  if (mpv_render_context_create(&render_, mpv_, params) < 0) {
    mpv_destroy(mpv_);
    mpv_ = nullptr;
    render_ = nullptr;
    return false;
  }

  Observe("pause", MPV_FORMAT_FLAG);
  Observe("eof-reached", MPV_FORMAT_FLAG);
  Observe("paused-for-cache", MPV_FORMAT_FLAG);
  Observe("seeking", MPV_FORMAT_FLAG);
  Observe("time-pos", MPV_FORMAT_DOUBLE);
  Observe("duration", MPV_FORMAT_DOUBLE);
  Observe("demuxer-cache-duration", MPV_FORMAT_DOUBLE);
  Observe("dwidth", MPV_FORMAT_INT64);
  Observe("dheight", MPV_FORMAT_INT64);
  Observe("volume", MPV_FORMAT_DOUBLE);
  Observe("mute", MPV_FORMAT_FLAG);
  Observe("idle-active", MPV_FORMAT_FLAG);

  mpv_set_wakeup_callback(
      mpv_,
      [](void* ctx) {
        auto* self = static_cast<MpvPlayer*>(ctx);
        std::lock_guard<std::mutex> lock(self->wake_mu_);
        self->woke_ = true;
        self->wake_cv_.notify_one();
      },
      this);
  mpv_render_context_set_update_callback(
      render_,
      [](void* ctx) {
        auto* self = static_cast<MpvPlayer*>(ctx);
        std::lock_guard<std::mutex> lock(self->wake_mu_);
        self->woke_ = true;
        self->wake_cv_.notify_one();
      },
      this);

  quit_ = false;
  worker_ = std::thread([this] { WorkerLoop(); });
  EmitState(kStateIdle);
  return true;
}

void MpvPlayer::Shutdown() {
  {
    std::lock_guard<std::mutex> lock(wake_mu_);
    quit_ = true;
    woke_ = true;
    wake_cv_.notify_one();
  }
  if (worker_.joinable()) {
    worker_.join();
  }
  if (render_) {
    mpv_render_context_free(render_);
    render_ = nullptr;
  }
  if (mpv_) {
    mpv_destroy(mpv_);
    mpv_ = nullptr;
  }
  file_loaded_ = false;
  eof_ = false;
  state_ = kStateIdle;
}

void MpvPlayer::LoadCurrentUnlocked(bool auto_play) {
  if (!mpv_ || playlist_.empty() || playlist_index_ < 0 ||
      playlist_index_ >= static_cast<int>(playlist_.size())) {
    return;
  }
  auto_play_ = auto_play;
  eof_ = false;
  file_loaded_ = false;
  paused_ = !auto_play;
  const char* cmd[] = {"loadfile", playlist_[playlist_index_].c_str(), "replace",
                       nullptr};
  mpv_command_async(mpv_, 0, cmd);
  EmitState(kStateBuffering);
}

void MpvPlayer::Load(const std::string& url, bool auto_play) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_ || url.empty()) return;
  playlist_ = {url};
  playlist_index_ = 0;
  LoadCurrentUnlocked(auto_play);
}

void MpvPlayer::SetPlaylist(const std::vector<std::string>& urls, int start_index,
                            bool auto_play) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_ || urls.empty()) return;
  playlist_ = urls;
  const int last = static_cast<int>(playlist_.size()) - 1;
  playlist_index_ = start_index;
  if (playlist_index_ < 0) playlist_index_ = 0;
  if (playlist_index_ > last) playlist_index_ = last;
  LoadCurrentUnlocked(auto_play);
}

bool MpvPlayer::PlayNextInPlaylist() {
  std::lock_guard<std::mutex> lock(api_mu_);
  return TryPlayNextUnlocked();
}

void MpvPlayer::SetAutoPlayNext(bool enabled) {
  std::lock_guard<std::mutex> lock(api_mu_);
  auto_play_next_ = enabled;
}

bool MpvPlayer::TryPlayNextUnlocked() {
  if (!mpv_ || looping_ || !auto_play_next_) return false;
  if (playlist_index_ >= static_cast<int>(playlist_.size()) - 1) return false;
  playlist_index_++;
  LoadCurrentUnlocked(true);
  return true;
}

void MpvPlayer::Play() {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  if (eof_ || state_ == kStateCompleted) {
    Cmd({"seek", "0", "absolute"});
    eof_ = false;
  }
  SetPropertyFlag("pause", false);
  paused_ = false;
}

void MpvPlayer::Pause() {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  SetPropertyFlag("pause", true);
  paused_ = true;
}

void MpvPlayer::Stop() {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  Cmd({"stop"});
  eof_ = false;
  file_loaded_ = false;
  paused_ = true;
  EmitState(kStateIdle);
}

void MpvPlayer::SeekToMs(int64_t position_ms) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  const double sec = static_cast<double>(position_ms) / 1000.0;
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%f", sec);
  Cmd({"seek", buf, "absolute"});
}

void MpvPlayer::SetScaleMode(int mode) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  // CommonScaleMode: 0 fit, 1 fill, 2 stretch
  if (mode == 2) {
    show_type_ = 4;
  } else if (mode == 1) {
    show_type_ = 3;
  } else {
    show_type_ = 0;
  }
  ApplyShowTypeUnlocked();
}

void MpvPlayer::SetShowType(int mode) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  show_type_ = mode;
  ApplyShowTypeUnlocked();
}

void MpvPlayer::ApplyShowTypeUnlocked() {
  if (!mpv_) return;
  // GsyShowType: 0 default, 1 16:9, 2 4:3, 3 full (crop), 4 matchFull (stretch),
  // 5 18:9
  SetProperty("video-aspect-override", "no");
  switch (show_type_) {
    case 1:
      SetProperty("keepaspect", "yes");
      SetProperty("panscan", "0");
      SetProperty("video-aspect-override", "16:9");
      break;
    case 2:
      SetProperty("keepaspect", "yes");
      SetProperty("panscan", "0");
      SetProperty("video-aspect-override", "4:3");
      break;
    case 3:
      SetProperty("keepaspect", "yes");
      SetProperty("panscan", "1.0");
      break;
    case 4:
      SetProperty("keepaspect", "no");
      SetProperty("panscan", "0");
      break;
    case 5:
      SetProperty("keepaspect", "yes");
      SetProperty("panscan", "0");
      SetProperty("video-aspect-override", "18:9");
      break;
    default:
      SetProperty("keepaspect", "yes");
      SetProperty("panscan", "0");
      break;
  }
}

void MpvPlayer::SetRotation(int degrees) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  int norm = degrees % 360;
  if (norm < 0) norm += 360;
  char buf[16];
  std::snprintf(buf, sizeof(buf), "%d", norm);
  SetProperty("video-rotate", buf);
}

void MpvPlayer::SetMirrorHorizontal(bool enabled) {
  std::lock_guard<std::mutex> lock(api_mu_);
  mirror_h_ = enabled;
  ApplyVfUnlocked();
}

void MpvPlayer::SetMirrorVertical(bool enabled) {
  std::lock_guard<std::mutex> lock(api_mu_);
  mirror_v_ = enabled;
  ApplyVfUnlocked();
}

void MpvPlayer::ApplyVfUnlocked() {
  if (!mpv_) return;
  std::string vf;
  if (mirror_h_) vf = "hflip";
  if (mirror_v_) {
    if (!vf.empty()) vf += ",";
    vf += "vflip";
  }
  SetProperty("vf", vf.c_str());
}

void MpvPlayer::SetSubtitleUrl(const std::string& url) {
  std::lock_guard<std::mutex> lock(api_mu_);
  subtitle_url_ = url;
  ApplySubtitleUnlocked();
}

void MpvPlayer::SetSubtitleEnabled(bool enabled) {
  std::lock_guard<std::mutex> lock(api_mu_);
  subtitle_enabled_ = enabled;
  ApplySubtitleUnlocked();
}

void MpvPlayer::ApplySubtitleUnlocked() {
  if (!mpv_) return;
  SetPropertyFlag("sub-visibility", subtitle_enabled_);
  if (!subtitle_enabled_) {
    SetProperty("sid", "no");
    return;
  }
  if (subtitle_url_.empty()) {
    SetProperty("sid", "auto");
    return;
  }
  if (file_loaded_) {
    const char* cmd[] = {"sub-add", subtitle_url_.c_str(), "select", nullptr};
    mpv_command_async(mpv_, 0, cmd);
  }
}

void MpvPlayer::SetRate(double rate) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  if (rate <= 0) rate = 1;
  SetPropertyDouble("speed", rate);
}

void MpvPlayer::SetVolume(double volume_0_1) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  if (volume_0_1 < 0) volume_0_1 = 0;
  if (volume_0_1 > 1) volume_0_1 = 1;
  volume_ = volume_0_1;
  SetPropertyDouble("volume", volume_0_1 * 100.0);
}

void MpvPlayer::SetMute(bool muted) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  SetPropertyFlag("mute", muted);
}

void MpvPlayer::SetLooping(bool looping) {
  std::lock_guard<std::mutex> lock(api_mu_);
  looping_ = looping;
  if (!mpv_) return;
  SetProperty("loop-file", looping ? "inf" : "no");
}

std::vector<MpvAudioTrack> MpvPlayer::GetAudioTracks() {
  std::lock_guard<std::mutex> lock(api_mu_);
  std::vector<MpvAudioTrack> tracks;
  if (!mpv_) return tracks;
  mpv_node node{};
  if (mpv_get_property(mpv_, "track-list", MPV_FORMAT_NODE, &node) < 0) {
    return tracks;
  }
  if (node.format == MPV_FORMAT_NODE_ARRAY && node.u.list) {
    int audio_index = 0;
    for (int i = 0; i < node.u.list->num; i++) {
      mpv_node* item = &node.u.list->values[i];
      const char* type = NodeString(MapGet(item, "type"));
      if (std::strcmp(type, "audio") != 0) continue;
      MpvAudioTrack track;
      track.index = audio_index++;
      const char* title = NodeString(MapGet(item, "title"));
      const char* lang = NodeString(MapGet(item, "lang"));
      track.language = lang;
      if (title && title[0]) {
        track.label = title;
      } else if (lang && lang[0]) {
        track.label = lang;
      } else {
        track.label = "Audio " + std::to_string(track.index);
      }
      track.selected = NodeFlag(MapGet(item, "selected"));
      tracks.push_back(std::move(track));
    }
  }
  mpv_free_node_contents(&node);
  return tracks;
}

bool MpvPlayer::SelectAudioTrack(int index) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_ || index < 0) return false;
  auto found = FindTrackId("audio", index);
  if (!found.second) return false;
  char buf[32];
  std::snprintf(buf, sizeof(buf), "%lld", static_cast<long long>(found.first));
  SetProperty("aid", buf);
  return true;
}

std::pair<int64_t, bool> MpvPlayer::FindTrackId(const char* type, int index) {
  std::pair<int64_t, bool> result{0, false};
  if (!mpv_ || index < 0) return result;
  mpv_node node{};
  if (mpv_get_property(mpv_, "track-list", MPV_FORMAT_NODE, &node) < 0) {
    return result;
  }
  if (node.format == MPV_FORMAT_NODE_ARRAY && node.u.list) {
    int typed = 0;
    for (int i = 0; i < node.u.list->num; i++) {
      mpv_node* item = &node.u.list->values[i];
      if (std::strcmp(NodeString(MapGet(item, "type")), type) != 0) continue;
      if (typed == index) {
        result.first = NodeInt(MapGet(item, "id"), 0);
        result.second = true;
        break;
      }
      typed++;
    }
  }
  mpv_free_node_contents(&node);
  return result;
}

std::vector<MpvVideoTrack> MpvPlayer::GetVideoTracks() {
  std::lock_guard<std::mutex> lock(api_mu_);
  std::vector<MpvVideoTrack> tracks;
  if (!mpv_) return tracks;
  mpv_node node{};
  if (mpv_get_property(mpv_, "track-list", MPV_FORMAT_NODE, &node) < 0) {
    return tracks;
  }
  if (node.format == MPV_FORMAT_NODE_ARRAY && node.u.list) {
    int video_index = 0;
    for (int i = 0; i < node.u.list->num; i++) {
      mpv_node* item = &node.u.list->values[i];
      const char* type = NodeString(MapGet(item, "type"));
      if (std::strcmp(type, "video") != 0) continue;
      MpvVideoTrack track;
      track.index = video_index++;
      track.width = static_cast<int>(NodeInt(MapGet(item, "demux-w"), 0));
      track.height = static_cast<int>(NodeInt(MapGet(item, "demux-h"), 0));
      track.bitrate = NodeInt(MapGet(item, "demux-bitrate"), 0);
      const char* title = NodeString(MapGet(item, "title"));
      const char* lang = NodeString(MapGet(item, "lang"));
      track.language = lang;
      if (title && title[0]) {
        track.label = title;
      } else if (track.height > 0) {
        track.label = std::to_string(track.height) + "p";
      } else {
        track.label = "Video " + std::to_string(track.index);
      }
      track.selected = NodeFlag(MapGet(item, "selected"));
      tracks.push_back(std::move(track));
    }
  }
  mpv_free_node_contents(&node);
  return tracks;
}

bool MpvPlayer::SelectVideoTrack(int index) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return false;
  if (index < 0) {
    SetProperty("vid", "auto");
    return true;
  }
  auto found = FindTrackId("video", index);
  if (!found.second) return false;
  char buf[32];
  std::snprintf(buf, sizeof(buf), "%lld", static_cast<long long>(found.first));
  SetProperty("vid", buf);
  return true;
}

MpvNetSpeed MpvPlayer::GetNetSpeed() {
  std::lock_guard<std::mutex> lock(api_mu_);
  MpvNetSpeed speed;
  if (!mpv_) return speed;
  speed.bytes_per_second = GetPropertyInt64("cache-speed", 0);
  if (speed.bytes_per_second < 0) speed.bytes_per_second = 0;
  const double bps = static_cast<double>(speed.bytes_per_second);
  char buf[64];
  if (bps >= 1024.0 * 1024.0) {
    std::snprintf(buf, sizeof(buf), "%.1f MB/s", bps / (1024.0 * 1024.0));
  } else if (bps >= 1024.0) {
    std::snprintf(buf, sizeof(buf), "%.1f KB/s", bps / 1024.0);
  } else {
    std::snprintf(buf, sizeof(buf), "%lld B/s",
                  static_cast<long long>(speed.bytes_per_second));
  }
  speed.text = buf;
  return speed;
}

MpvVideoSize MpvPlayer::GetVideoSize() const {
  return {video_w_, video_h_};
}

int64_t MpvPlayer::GetDurationMs() {
  std::lock_guard<std::mutex> lock(api_mu_);
  return mpv_ ? static_cast<int64_t>(GetPropertyDouble("duration", 0) * 1000.0) : 0;
}

std::vector<uint8_t> MpvPlayer::CapturePng() {
  std::vector<uint8_t> rgba;
  int w = 0, h = 0;
  if (!CopyRgbaFrame(rgba, w, h) || rgba.empty()) {
    return {};
  }
  return EncodePngRgba(rgba.data(), w, h);
}

void MpvPlayer::SetHwdec(const std::string& hwdec) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_ || hwdec.empty()) return;
  SetProperty("hwdec", hwdec.c_str());
}

void MpvPlayer::SetHttpRequestOptions(
    const std::string& user_agent,
    const std::vector<std::pair<std::string, std::string>>& headers) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_) return;
  if (user_agent.empty()) {
    SetProperty("user-agent", "");
  } else {
    SetProperty("user-agent", user_agent.c_str());
  }
  if (headers.empty()) {
    SetProperty("http-header-fields", "");
    return;
  }
  std::string fields;
  for (const auto& kv : headers) {
    if (kv.first.empty()) continue;
    if (!fields.empty()) fields += "\n";
    fields += kv.first;
    fields += ": ";
    fields += kv.second;
  }
  SetProperty("http-header-fields", fields.c_str());
}

void MpvPlayer::Command(const std::vector<std::string>& args) {
  std::lock_guard<std::mutex> lock(api_mu_);
  if (!mpv_ || args.empty()) return;
  std::vector<const char*> cargs;
  cargs.reserve(args.size() + 1);
  for (const auto& a : args) {
    cargs.push_back(a.c_str());
  }
  cargs.push_back(nullptr);
  mpv_command_async(mpv_, 0, cargs.data());
}

void MpvPlayer::SetKeepLastFrame(bool enabled) {
  std::lock_guard<std::mutex> lock(api_mu_);
  keep_last_frame_ = enabled;
}

void MpvPlayer::SetSeekOnStartMs(int64_t ms) {
  std::lock_guard<std::mutex> lock(api_mu_);
  seek_on_start_ms_ = ms;
}

void MpvPlayer::SetOutputSize(int width, int height) {
  if (width < 2) width = 2;
  if (height < 2) height = 2;
  if (width > 3840) width = 3840;
  if (height > 2160) height = 2160;
  output_w_ = width;
  output_h_ = height;
}

bool MpvPlayer::CopyRgbaFrame(std::vector<uint8_t>& out, int& width,
                              int& height) {
  std::lock_guard<std::mutex> lock(frame_mu_);
  if (rgba_.empty() || frame_w_ <= 0 || frame_h_ <= 0) {
    return false;
  }
  out = rgba_;
  width = frame_w_;
  height = frame_h_;
  return true;
}

void MpvPlayer::WorkerLoop() {
  while (true) {
    {
      std::unique_lock<std::mutex> lock(wake_mu_);
      wake_cv_.wait_for(lock, std::chrono::milliseconds(50),
                        [this] { return quit_ || woke_; });
      woke_ = false;
      if (quit_) break;
    }
    if (!mpv_) continue;
    while (true) {
      mpv_event* event = mpv_wait_event(mpv_, 0);
      if (!event || event->event_id == MPV_EVENT_NONE) break;
      HandleEvent(event);
    }
    MaybeRender();
    EmitPosition(false);
  }
}

void MpvPlayer::HandleEvent(mpv_event* event) {
  switch (event->event_id) {
    case MPV_EVENT_FILE_LOADED:
      file_loaded_ = true;
      eof_ = false;
      if (seek_on_start_ms_ >= 0) {
        const double sec = static_cast<double>(seek_on_start_ms_) / 1000.0;
        char buf[64];
        std::snprintf(buf, sizeof(buf), "%f", sec);
        const char* cmd[] = {"seek", buf, "absolute", nullptr};
        mpv_command_async(mpv_, 0, cmd);
        seek_on_start_ms_ = -1;
      }
      ApplyVfUnlocked();
      ApplyShowTypeUnlocked();
      ApplySubtitleUnlocked();
      EmitState(kStateReady);
      if (auto_play_) {
        SetPropertyFlag("pause", false);
        paused_ = false;
      } else {
        SetPropertyFlag("pause", true);
        paused_ = true;
        EmitState(kStatePaused);
      }
      break;
    case MPV_EVENT_END_FILE: {
      auto* end = static_cast<mpv_event_end_file*>(event->data);
      if (!end) break;
      if (end->reason == MPV_END_FILE_REASON_ERROR ||
          end->reason == MPV_END_FILE_REASON_REDIRECT) {
        const char* msg = mpv_error_string(end->error);
        EmitState(kStateError);
        if (cb_.on_error && cb_.post_to_ui) {
          std::string text = msg ? msg : "playback error";
          int code = end->error;
          cb_.post_to_ui([this, text, code] {
            if (cb_.on_error) cb_.on_error(text, code);
          });
        }
      } else if (end->reason == MPV_END_FILE_REASON_EOF) {
        eof_ = true;
        if (looping_) {
          break;
        }
        if (TryPlayNextUnlocked()) {
          eof_ = false;
          break;
        }
        EmitState(kStateCompleted);
      } else if (end->reason == MPV_END_FILE_REASON_STOP) {
        file_loaded_ = false;
        EmitState(kStateIdle);
      }
      break;
    }
    case MPV_EVENT_PROPERTY_CHANGE:
      HandleProperty(event);
      break;
    default:
      break;
  }
}

void MpvPlayer::HandleProperty(mpv_event* event) {
  auto* prop = static_cast<mpv_event_property*>(event->data);
  if (!prop || !prop->name) return;
  const char* name = prop->name;
  if (std::strcmp(name, "pause") == 0 && prop->format == MPV_FORMAT_FLAG) {
    paused_ = prop->data && *static_cast<int*>(prop->data);
    RecomputeState();
  } else if (std::strcmp(name, "eof-reached") == 0 &&
             prop->format == MPV_FORMAT_FLAG) {
    eof_ = prop->data && *static_cast<int*>(prop->data);
    RecomputeState();
  } else if (std::strcmp(name, "paused-for-cache") == 0 &&
             prop->format == MPV_FORMAT_FLAG) {
    paused_for_cache_ = prop->data && *static_cast<int*>(prop->data);
    RecomputeState();
  } else if (std::strcmp(name, "seeking") == 0 &&
             prop->format == MPV_FORMAT_FLAG) {
    seeking_ = prop->data && *static_cast<int*>(prop->data);
    RecomputeState();
  } else if (std::strcmp(name, "dwidth") == 0 &&
             prop->format == MPV_FORMAT_INT64 && prop->data) {
    video_w_ = static_cast<int>(*static_cast<int64_t*>(prop->data));
  } else if (std::strcmp(name, "dheight") == 0 &&
             prop->format == MPV_FORMAT_INT64 && prop->data) {
    video_h_ = static_cast<int>(*static_cast<int64_t*>(prop->data));
  } else if ((std::strcmp(name, "time-pos") == 0 ||
              std::strcmp(name, "duration") == 0 ||
              std::strcmp(name, "demuxer-cache-duration") == 0) &&
             prop->format == MPV_FORMAT_DOUBLE) {
    EmitPosition(false);
  }
}

void MpvPlayer::RecomputeState() {
  if (state_ == kStateError || state_ == kStateIdle) return;
  if (eof_ && !looping_) {
    EmitState(kStateCompleted);
    return;
  }
  if (seeking_ || paused_for_cache_) {
    EmitState(kStateBuffering);
    return;
  }
  if (paused_) {
    EmitState(file_loaded_ ? kStatePaused : kStateIdle);
    return;
  }
  if (file_loaded_) {
    EmitState(kStatePlaying);
  }
}

void MpvPlayer::MaybeRender() {
  if (!render_) return;
  uint64_t flags = mpv_render_context_update(render_);
  if (!(flags & MPV_RENDER_UPDATE_FRAME)) {
    return;
  }
  const int w = output_w_;
  const int h = output_h_;
  std::vector<uint8_t> rgb0(static_cast<size_t>(w) * static_cast<size_t>(h) * 4);
  int size[2] = {w, h};
  size_t stride = static_cast<size_t>(w) * 4;
  char format[] = "rgb0";
  int flip = 0;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_SW_SIZE, size},
      {MPV_RENDER_PARAM_SW_FORMAT, format},
      {MPV_RENDER_PARAM_SW_STRIDE, &stride},
      {MPV_RENDER_PARAM_SW_POINTER, rgb0.data()},
      {MPV_RENDER_PARAM_FLIP_Y, &flip},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  if (mpv_render_context_render(render_, params) < 0) {
    return;
  }
  std::vector<uint8_t> rgba(rgb0.size());
  for (int i = 0; i < w * h; i++) {
    rgba[i * 4 + 0] = rgb0[i * 4 + 0];
    rgba[i * 4 + 1] = rgb0[i * 4 + 1];
    rgba[i * 4 + 2] = rgb0[i * 4 + 2];
    rgba[i * 4 + 3] = 255;
  }
  {
    std::lock_guard<std::mutex> lock(frame_mu_);
    rgba_.swap(rgba);
    frame_w_ = w;
    frame_h_ = h;
  }
  if (cb_.on_frame) {
    cb_.on_frame();
  }
}

void MpvPlayer::EmitState(int state) {
  if (state_ == state) return;
  state_ = state;
  if (cb_.on_state && cb_.post_to_ui) {
    cb_.post_to_ui([this, state] {
      if (cb_.on_state) cb_.on_state(state);
    });
  }
}

void MpvPlayer::EmitPosition(bool force) {
  if (!mpv_ || !cb_.on_position || !cb_.post_to_ui) return;
  const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
                       std::chrono::steady_clock::now().time_since_epoch())
                       .count();
  if (!force && now - last_pos_emit_ms_ < kProgressIntervalMs) {
    return;
  }
  last_pos_emit_ms_ = now;
  const double pos = GetPropertyDouble("time-pos", 0);
  const double dur = GetPropertyDouble("duration", 0);
  const double cached = GetPropertyDouble("demuxer-cache-duration", 0);
  const int64_t pos_ms = static_cast<int64_t>(pos * 1000.0);
  const int64_t dur_ms = static_cast<int64_t>(dur * 1000.0);
  const int64_t buf_ms = static_cast<int64_t>((pos + cached) * 1000.0);
  cb_.post_to_ui([this, pos_ms, dur_ms, buf_ms] {
    if (cb_.on_position) cb_.on_position(pos_ms, dur_ms, buf_ms);
  });
}

void MpvPlayer::Observe(const char* name, int format) {
  mpv_observe_property(mpv_, 0, name, static_cast<mpv_format>(format));
}

void MpvPlayer::SetOption(const char* name, const char* value) {
  mpv_set_option_string(mpv_, name, value);
}

void MpvPlayer::SetProperty(const char* name, const char* value) {
  mpv_set_property_string(mpv_, name, value);
}

void MpvPlayer::SetPropertyFlag(const char* name, bool value) {
  int flag = value ? 1 : 0;
  mpv_set_property(mpv_, name, MPV_FORMAT_FLAG, &flag);
}

void MpvPlayer::SetPropertyDouble(const char* name, double value) {
  mpv_set_property(mpv_, name, MPV_FORMAT_DOUBLE, &value);
}

double MpvPlayer::GetPropertyDouble(const char* name, double fallback) {
  double value = fallback;
  if (mpv_get_property(mpv_, name, MPV_FORMAT_DOUBLE, &value) < 0) {
    return fallback;
  }
  return value;
}

int64_t MpvPlayer::GetPropertyInt64(const char* name, int64_t fallback) {
  int64_t value = fallback;
  if (mpv_get_property(mpv_, name, MPV_FORMAT_INT64, &value) < 0) {
    return fallback;
  }
  return value;
}

void MpvPlayer::Cmd(const std::initializer_list<const char*>& args) {
  std::vector<const char*> cargs(args.begin(), args.end());
  cargs.push_back(nullptr);
  mpv_command_async(mpv_, 0, cargs.data());
}

}  // namespace kinetic
