#include "include/kinetic_player/kinetic_player_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "mpv_player.h"

G_DECLARE_FINAL_TYPE(KineticMpvTexture,
                     kinetic_mpv_texture,
                     KINETIC,
                     MPV_TEXTURE,
                     FlPixelBufferTexture)

struct _KineticMpvTexture {
  FlPixelBufferTexture parent_instance;
  kinetic::MpvPlayer* player;
  std::vector<uint8_t>* buffer;
};

G_DEFINE_TYPE(KineticMpvTexture,
              kinetic_mpv_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean kinetic_mpv_texture_copy_pixels(FlPixelBufferTexture* texture,
                                                const uint8_t** out_buffer,
                                                uint32_t* width,
                                                uint32_t* height,
                                                GError** error) {
  KineticMpvTexture* self = KINETIC_MPV_TEXTURE(texture);
  if (!self->player || !self->buffer) {
    static const uint8_t kBlack[] = {0, 0, 0, 255};
    *out_buffer = kBlack;
    *width = 1;
    *height = 1;
    return TRUE;
  }
  if (width && height && *width > 1 && *height > 1) {
    self->player->SetOutputSize(static_cast<int>(*width),
                                static_cast<int>(*height));
  }
  int w = 0, h = 0;
  if (!self->player->CopyRgbaFrame(*self->buffer, w, h) ||
      self->buffer->empty()) {
    static const uint8_t kBlack[] = {0, 0, 0, 255};
    *out_buffer = kBlack;
    *width = 1;
    *height = 1;
    return TRUE;
  }
  *out_buffer = self->buffer->data();
  *width = static_cast<uint32_t>(w);
  *height = static_cast<uint32_t>(h);
  return TRUE;
}

static void kinetic_mpv_texture_dispose(GObject* object) {
  KineticMpvTexture* self = KINETIC_MPV_TEXTURE(object);
  delete self->buffer;
  self->buffer = nullptr;
  self->player = nullptr;
  G_OBJECT_CLASS(kinetic_mpv_texture_parent_class)->dispose(object);
}

static void kinetic_mpv_texture_class_init(KineticMpvTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      kinetic_mpv_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->dispose = kinetic_mpv_texture_dispose;
}

static void kinetic_mpv_texture_init(KineticMpvTexture* self) {
  self->player = nullptr;
  self->buffer = new std::vector<uint8_t>();
}

static KineticMpvTexture* kinetic_mpv_texture_new(kinetic::MpvPlayer* player) {
  KineticMpvTexture* self = KINETIC_MPV_TEXTURE(
      g_object_new(kinetic_mpv_texture_get_type(), nullptr));
  self->player = player;
  return self;
}

namespace {

bool FlMapBool(FlValue* map, const char* key, bool fallback) {
  if (!map) return fallback;
  FlValue* v = fl_value_lookup_string(map, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_BOOL) return fallback;
  return fl_value_get_bool(v);
}

int64_t FlMapInt(FlValue* map, const char* key, int64_t fallback) {
  if (!map) return fallback;
  FlValue* v = fl_value_lookup_string(map, key);
  if (!v) return fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return fl_value_get_int(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int64_t>(fl_value_get_float(v));
  }
  return fallback;
}

double FlMapDouble(FlValue* map, const char* key, double fallback) {
  if (!map) return fallback;
  FlValue* v = fl_value_lookup_string(map, key);
  if (!v) return fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(v));
  }
  return fallback;
}

std::string FlMapString(FlValue* map, const char* key) {
  if (!map) return {};
  FlValue* v = fl_value_lookup_string(map, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) return {};
  return fl_value_get_string(v);
}

std::vector<std::string> FlMapStringList(FlValue* map, const char* key) {
  std::vector<std::string> out;
  if (!map) return out;
  FlValue* list = fl_value_lookup_string(map, key);
  if (!list || fl_value_get_type(list) != FL_VALUE_TYPE_LIST) return out;
  const size_t n = fl_value_get_length(list);
  for (size_t i = 0; i < n; i++) {
    FlValue* item = fl_value_get_list_value(list, i);
    if (item && fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
      const char* s = fl_value_get_string(item);
      if (s && s[0]) out.emplace_back(s);
    }
  }
  return out;
}

std::vector<std::pair<std::string, std::string>> FlMapHeaderPairs(FlValue* map,
                                                                 const char* key) {
  std::vector<std::pair<std::string, std::string>> out;
  if (!map) return out;
  FlValue* headers = fl_value_lookup_string(map, key);
  if (!headers || fl_value_get_type(headers) != FL_VALUE_TYPE_MAP) return out;
  const size_t n = fl_value_get_length(headers);
  for (size_t i = 0; i < n; i++) {
    FlValue* k = fl_value_get_map_key(headers, i);
    FlValue* v = fl_value_get_map_value(headers, i);
    if (!k || fl_value_get_type(k) != FL_VALUE_TYPE_STRING) continue;
    if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) continue;
    const char* ks = fl_value_get_string(k);
    const char* vs = fl_value_get_string(v);
    if (ks && ks[0] && vs) out.emplace_back(ks, vs);
  }
  return out;
}

void ApplyHttpRequestOptions(kinetic::MpvPlayer* player, FlValue* args) {
  player->SetHttpRequestOptions(FlMapString(args, "userAgent"),
                                FlMapHeaderPairs(args, "headers"));
}

FlValue* FlUi(FlValue* args) {
  if (!args) return nullptr;
  FlValue* ui = fl_value_lookup_string(args, "ui");
  return ui && fl_value_get_type(ui) == FL_VALUE_TYPE_MAP ? ui : nullptr;
}

void ApplyCreateOptions(kinetic::MpvPlayer* player, FlValue* args) {
  FlValue* ui = FlUi(args);
  FlValue* src = ui ? ui : args;
  player->SetRate(FlMapDouble(src, "speed", 1.0));
  player->SetLooping(FlMapBool(src, "looping", false));
  player->SetKeepLastFrame(FlMapBool(src, "keepLastFrameWhenComplete", false));
  player->SetSeekOnStartMs(FlMapInt(src, "seekOnStartMs", -1));
  player->SetAutoPlayNext(FlMapBool(src, "autoPlayNext", true));
  ApplyHttpRequestOptions(player, args);
  const bool auto_play = FlMapBool(src, "startAfterPrepared", true);
  auto playlist = FlMapStringList(args, "playlist");
  if (!playlist.empty()) {
    player->SetPlaylist(
        playlist, static_cast<int>(FlMapInt(args, "playlistStartIndex", 0)),
        auto_play);
    return;
  }
  const std::string url = FlMapString(args, "url");
  if (!url.empty()) {
    player->Load(url, auto_play);
  }
}

FlValue* TracksValue(const std::vector<kinetic::MpvAudioTrack>& tracks) {
  g_autoptr(FlValue) list = fl_value_new_list();
  for (const auto& t : tracks) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "index", fl_value_new_int(t.index));
    fl_value_set_string_take(map, "label", fl_value_new_string(t.label.c_str()));
    fl_value_set_string_take(map, "language",
                             fl_value_new_string(t.language.c_str()));
    fl_value_set_string_take(map, "selected", fl_value_new_bool(t.selected));
    fl_value_append(list, map);
  }
  return fl_value_ref(list);
}

FlValue* VideoTracksValue(const std::vector<kinetic::MpvVideoTrack>& tracks) {
  g_autoptr(FlValue) list = fl_value_new_list();
  for (const auto& t : tracks) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "index", fl_value_new_int(t.index));
    fl_value_set_string_take(map, "label", fl_value_new_string(t.label.c_str()));
    fl_value_set_string_take(map, "language",
                             fl_value_new_string(t.language.c_str()));
    fl_value_set_string_take(map, "selected", fl_value_new_bool(t.selected));
    fl_value_set_string_take(map, "width", fl_value_new_int(t.width));
    fl_value_set_string_take(map, "height", fl_value_new_int(t.height));
    fl_value_set_string_take(map, "bitrate", fl_value_new_int(t.bitrate));
    fl_value_append(list, map);
  }
  return fl_value_ref(list);
}

struct IdleFn {
  std::function<void()> fn;
};

gboolean IdleDispatch(gpointer data) {
  auto* posted = static_cast<IdleFn*>(data);
  posted->fn();
  delete posted;
  return G_SOURCE_REMOVE;
}

void PostUi(std::function<void()> fn) {
  g_idle_add(IdleDispatch, new IdleFn{std::move(fn)});
}

GtkWindow* HostWindow(FlPluginRegistrar* registrar) {
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (!view) return nullptr;
  GtkWidget* top = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!top || !GTK_IS_WINDOW(top)) return nullptr;
  return GTK_WINDOW(top);
}

class PlayerSlot {
 public:
  PlayerSlot(int view_id, FlPluginRegistrar* registrar)
      : view_id_(view_id), registrar_(registrar) {
    player_ = std::make_unique<kinetic::MpvPlayer>();
  }

  ~PlayerSlot() { Destroy(); }

  bool Init() {
    kinetic::MpvPlayer::Callbacks cb;
    cb.post_to_ui = [](std::function<void()> fn) { PostUi(std::move(fn)); };
    cb.on_state = [this](int state) {
      if (!channel_) return;
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "state", fl_value_new_int(state));
      fl_method_channel_invoke_method(channel_, "onPlayerStateChanged", map,
                                      nullptr, nullptr, nullptr);
    };
    cb.on_position = [this](int64_t pos, int64_t dur, int64_t buf) {
      if (!channel_) return;
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "position", fl_value_new_int(pos));
      fl_value_set_string_take(map, "duration", fl_value_new_int(dur));
      fl_value_set_string_take(map, "buffered", fl_value_new_int(buf));
      fl_method_channel_invoke_method(channel_, "onPositionChanged", map,
                                      nullptr, nullptr, nullptr);
    };
    cb.on_error = [this](const std::string& message, int code) {
      if (!channel_) return;
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "message",
                               fl_value_new_string(message.c_str()));
      fl_value_set_string_take(map, "code", fl_value_new_int(code));
      fl_method_channel_invoke_method(channel_, "onPlayerError", map, nullptr,
                                      nullptr, nullptr);
    };
    cb.on_frame = [this]() {
      if (texture_registrar_ && texture_) {
        fl_texture_registrar_mark_texture_frame_available(texture_registrar_,
                                                          FL_TEXTURE(texture_));
      }
    };
    if (!player_->Init(std::move(cb))) {
      return false;
    }

    texture_registrar_ = fl_plugin_registrar_get_texture_registrar(registrar_);
    texture_ = kinetic_mpv_texture_new(player_.get());
    fl_texture_registrar_register_texture(texture_registrar_,
                                          FL_TEXTURE(texture_));
    texture_id_ = fl_texture_get_id(FL_TEXTURE(texture_));

    const std::string name =
        "com.example.player/mpv_" + std::to_string(view_id_);
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    channel_ = fl_method_channel_new(
        fl_plugin_registrar_get_messenger(registrar_), name.c_str(),
        FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(
        channel_,
        [](FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
          static_cast<PlayerSlot*>(user_data)->Handle(call);
        },
        this, nullptr);
    return true;
  }

  void Destroy() {
    if (destroyed_) return;
    destroyed_ = true;
    if (channel_) {
      fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                                nullptr);
      g_object_unref(channel_);
      channel_ = nullptr;
    }
    if (player_) {
      player_->Shutdown();
    }
    if (texture_registrar_ && texture_) {
      fl_texture_registrar_unregister_texture(texture_registrar_,
                                              FL_TEXTURE(texture_));
      g_object_unref(texture_);
      texture_ = nullptr;
    }
    player_.reset();
  }

  int64_t texture_id() const { return texture_id_; }

  void ApplyCreate(FlValue* args) { ApplyCreateOptions(player_.get(), args); }

  void Handle(FlMethodCall* call) {
    const gchar* method = fl_method_call_get_name(call);
    FlValue* args = fl_method_call_get_args(call);
    g_autoptr(FlMethodResponse) response = nullptr;

    if (g_strcmp0(method, "play") == 0) {
      player_->Play();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "pause") == 0) {
      player_->Pause();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "stop") == 0) {
      player_->Stop();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "seekTo") == 0) {
      player_->SeekToMs(FlMapInt(args, "position", 0));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "setScaleMode") == 0) {
      player_->SetScaleMode(static_cast<int>(FlMapInt(args, "mode", 0)));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "setRate") == 0) {
      player_->SetRate(FlMapDouble(args, "rate", 1));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "setVolume") == 0) {
      player_->SetVolume(FlMapDouble(args, "volume", 1));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "setMute") == 0) {
      player_->SetMute(FlMapBool(args, "muted", false));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "switchVideoSource") == 0) {
      player_->Load(FlMapString(args, "url"),
                    FlMapBool(args, "autoPlay", true));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "getAudioTracks") == 0) {
      g_autoptr(FlValue) list = TracksValue(player_->GetAudioTracks());
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
    } else if (g_strcmp0(method, "selectAudioTrack") == 0) {
      if (player_->SelectAudioTrack(
              static_cast<int>(FlMapInt(args, "index", 0)))) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      } else {
        response = FL_METHOD_RESPONSE(
            fl_method_error_response_new("TRACK", "Audio track not found",
                                         nullptr));
      }
    } else if (g_strcmp0(method, "getVideoSize") == 0) {
      const auto size = player_->GetVideoSize();
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "width", fl_value_new_int(size.width));
      fl_value_set_string_take(map, "height", fl_value_new_int(size.height));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
    } else if (g_strcmp0(method, "getVideoMetadata") == 0) {
      const auto size = player_->GetVideoSize();
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "width", fl_value_new_int(size.width));
      fl_value_set_string_take(map, "height", fl_value_new_int(size.height));
      fl_value_set_string_take(map, "duration", fl_value_new_int(player_->GetDurationMs()));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
    } else if (g_strcmp0(method, "setLooping") == 0) {
      player_->SetLooping(FlMapBool(args, "looping", false));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "setLocale") == 0) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "setHttpRequestOptions") == 0) {
      ApplyHttpRequestOptions(player_.get(), args);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "captureFrame") == 0) {
      auto png = player_->CapturePng();
      if (png.empty()) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      } else {
        g_autoptr(FlValue) bytes =
            fl_value_new_uint8_list(png.data(), png.size());
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(bytes));
      }
    } else if (g_strcmp0(method, "mpvStartFullscreen") == 0) {
      GtkWindow* win = HostWindow(registrar_);
      if (win) {
        if (gtk_window_is_fullscreen(win)) {
          gtk_window_unfullscreen(win);
        } else {
          gtk_window_fullscreen(win);
        }
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvExitFullscreen") == 0) {
      GtkWindow* win = HostWindow(registrar_);
      if (win) gtk_window_unfullscreen(win);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvIsFullscreen") == 0) {
      GtkWindow* win = HostWindow(registrar_);
      const bool full = win && gtk_window_is_fullscreen(win);
      g_autoptr(FlValue) v = fl_value_new_bool(full);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
    } else if (g_strcmp0(method, "mpvSetHwdec") == 0) {
      player_->SetHwdec(FlMapString(args, "hwdec"));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvCommand") == 0) {
      std::vector<std::string> cmd;
      FlValue* list = args ? fl_value_lookup_string(args, "args") : nullptr;
      if (list && fl_value_get_type(list) == FL_VALUE_TYPE_LIST) {
        const size_t n = fl_value_get_length(list);
        for (size_t i = 0; i < n; i++) {
          FlValue* item = fl_value_get_list_value(list, i);
          if (item && fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
            cmd.emplace_back(fl_value_get_string(item));
          }
        }
      }
      player_->Command(cmd);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvSetKeepLastFrameWhenComplete") == 0) {
      player_->SetKeepLastFrame(FlMapBool(args, "enabled", false));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvSetRenderRotation") == 0) {
      player_->SetRotation(static_cast<int>(FlMapInt(args, "degrees", 0)));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvSetMirrorHorizontal") == 0) {
      player_->SetMirrorHorizontal(FlMapBool(args, "enabled", false));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvSetMirrorVertical") == 0) {
      player_->SetMirrorVertical(FlMapBool(args, "enabled", false));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvSetShowType") == 0) {
      player_->SetShowType(static_cast<int>(FlMapInt(args, "mode", 0)));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvSetPlaylist") == 0) {
      player_->SetPlaylist(FlMapStringList(args, "urls"),
                           static_cast<int>(FlMapInt(args, "startIndex", 0)),
                           true);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvPlayNextInPlaylist") == 0) {
      g_autoptr(FlValue) v = fl_value_new_bool(player_->PlayNextInPlaylist());
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
    } else if (g_strcmp0(method, "mpvSetAutoPlayNext") == 0) {
      player_->SetAutoPlayNext(FlMapBool(args, "enabled", true));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvSetSubtitleUrl") == 0) {
      player_->SetSubtitleUrl(FlMapString(args, "url"));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvSetSubtitleEnabled") == 0) {
      player_->SetSubtitleEnabled(FlMapBool(args, "enabled", true));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (g_strcmp0(method, "mpvListVideoTracks") == 0) {
      g_autoptr(FlValue) list = VideoTracksValue(player_->GetVideoTracks());
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
    } else if (g_strcmp0(method, "mpvSelectVideoTrack") == 0) {
      g_autoptr(FlValue) v = fl_value_new_bool(player_->SelectVideoTrack(
          static_cast<int>(FlMapInt(args, "index", -1))));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
    } else if (g_strcmp0(method, "mpvGetNetSpeed") == 0) {
      const auto speed = player_->GetNetSpeed();
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "bytesPerSecond",
                               fl_value_new_int(speed.bytes_per_second));
      fl_value_set_string_take(map, "text",
                               fl_value_new_string(speed.text.c_str()));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
    } else if (g_strcmp0(method, "mpvSetCoverUrl") == 0 ||
               g_strcmp0(method, "mpvSetWatermarkUrl") == 0 ||
               g_strcmp0(method, "mpvSetPurePlayMode") == 0 ||
               g_strcmp0(method, "mpvSetUiConfig") == 0 ||
               g_strcmp0(method, "dispose") == 0) {
      if (g_strcmp0(method, "dispose") == 0) {
        Destroy();
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }
    fl_method_call_respond(call, response, nullptr);
  }

 private:
  int view_id_ = 0;
  FlPluginRegistrar* registrar_ = nullptr;
  FlTextureRegistrar* texture_registrar_ = nullptr;
  KineticMpvTexture* texture_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  std::unique_ptr<kinetic::MpvPlayer> player_;
  int64_t texture_id_ = -1;
  bool destroyed_ = false;
};

struct PluginState {
  FlPluginRegistrar* registrar = nullptr;
  FlMethodChannel* channel = nullptr;
  int next_id = 1;
  std::map<int, std::unique_ptr<PlayerSlot>> players;
  std::map<int, bool> controller_players;
};

void PluginHandle(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  auto* state = static_cast<PluginState*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "create") == 0) {
    const int view_id = state->next_id++;
    auto slot = std::make_unique<PlayerSlot>(view_id, state->registrar);
    if (!slot->Init()) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "MPV",
          "Failed to initialize libmpv. Install libmpv-dev / mpv-libs-devel.",
          nullptr));
    } else {
      slot->ApplyCreate(args);
      const int64_t texture_id = slot->texture_id();
      state->players[view_id] = std::move(slot);
      if (FlMapBool(args, "controllerOwned", false)) state->controller_players[view_id] = true;
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "viewId", fl_value_new_int(view_id));
      fl_value_set_string_take(map, "textureId",
                               fl_value_new_int(texture_id));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
    }
  } else if (g_strcmp0(method, "reset") == 0) {
    for (const auto& entry : state->controller_players) {
      auto it = state->players.find(entry.first);
      if (it != state->players.end()) {
        it->second->Destroy();
        state->players.erase(it);
      }
    }
    state->controller_players.clear();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "destroy") == 0) {
    const int view_id = static_cast<int>(FlMapInt(args, "viewId", -1));
    auto it = state->players.find(view_id);
    state->controller_players.erase(view_id);
    if (it != state->players.end()) {
      it->second->Destroy();
      state->players.erase(it);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void kinetic_player_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  auto* state = new PluginState();
  state->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  state->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "com.example.player/mpv",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(state->channel, PluginHandle, state,
                                            nullptr);
}
