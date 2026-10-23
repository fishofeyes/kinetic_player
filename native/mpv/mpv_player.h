#ifndef KINETIC_MPV_PLAYER_H_
#define KINETIC_MPV_PLAYER_H_

#include <condition_variable>
#include <cstdint>
#include <functional>
#include <initializer_list>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

struct mpv_handle;
struct mpv_render_context;
struct mpv_event;

namespace kinetic {

struct MpvAudioTrack {
  int index = 0;
  std::string label;
  std::string language;
  bool selected = false;
};

struct MpvVideoTrack {
  int index = 0;
  std::string label;
  std::string language;
  bool selected = false;
  int width = 0;
  int height = 0;
  int64_t bitrate = 0;
};

struct MpvNetSpeed {
  int64_t bytes_per_second = 0;
  std::string text;
};

struct MpvVideoSize {
  int width = 0;
  int height = 0;
};

class MpvPlayer {
 public:
  using PostToUi = std::function<void(std::function<void()>)>;
  using OnState = std::function<void(int)>;
  using OnPosition = std::function<void(int64_t, int64_t, int64_t)>;
  using OnError = std::function<void(const std::string&, int)>;
  using OnFrame = std::function<void()>;

  struct Callbacks {
    PostToUi post_to_ui;
    OnState on_state;
    OnPosition on_position;
    OnError on_error;
    OnFrame on_frame;
  };

  MpvPlayer() = default;
  ~MpvPlayer();

  MpvPlayer(const MpvPlayer&) = delete;
  MpvPlayer& operator=(const MpvPlayer&) = delete;

  bool Init(Callbacks callbacks);
  void Shutdown();

  void Load(const std::string& url, bool auto_play);
  void SetPlaylist(const std::vector<std::string>& urls, int start_index,
                   bool auto_play);
  bool PlayNextInPlaylist();
  void SetAutoPlayNext(bool enabled);
  void Play();
  void Pause();
  void Stop();
  void SeekToMs(int64_t position_ms);
  void SetScaleMode(int mode);
  void SetShowType(int mode);
  void SetRate(double rate);
  void SetVolume(double volume_0_1);
  void SetMute(bool muted);
  void SetLooping(bool looping);
  void SetRotation(int degrees);
  void SetMirrorHorizontal(bool enabled);
  void SetMirrorVertical(bool enabled);
  void SetSubtitleUrl(const std::string& url);
  void SetSubtitleEnabled(bool enabled);
  std::vector<MpvAudioTrack> GetAudioTracks();
  bool SelectAudioTrack(int index);
  std::vector<MpvVideoTrack> GetVideoTracks();
  bool SelectVideoTrack(int index);
  MpvNetSpeed GetNetSpeed();
  MpvVideoSize GetVideoSize() const;
  int64_t GetDurationMs();
  std::vector<uint8_t> CapturePng();
  void SetHwdec(const std::string& hwdec);
  void SetHttpRequestOptions(const std::string& user_agent,
                             const std::vector<std::pair<std::string, std::string>>& headers);
  void Command(const std::vector<std::string>& args);
  void SetKeepLastFrame(bool enabled);
  void SetSeekOnStartMs(int64_t ms);
  void SetOutputSize(int width, int height);

  // Latest RGBA8888 frame. |out| is replaced. Returns false if empty.
  bool CopyRgbaFrame(std::vector<uint8_t>& out, int& width, int& height);

 private:
  void WorkerLoop();
  void HandleEvent(mpv_event* event);
  void HandleProperty(mpv_event* event);
  void MaybeRender();
  void EmitState(int state);
  void EmitPosition(bool force);
  void Observe(const char* name, int format);
  void SetOption(const char* name, const char* value);
  void SetProperty(const char* name, const char* value);
  void SetPropertyFlag(const char* name, bool value);
  void SetPropertyDouble(const char* name, double value);
  double GetPropertyDouble(const char* name, double fallback = 0);
  int64_t GetPropertyInt64(const char* name, int64_t fallback = 0);
  void Cmd(const std::initializer_list<const char*>& args);
  void RecomputeState();
  void LoadCurrentUnlocked(bool auto_play);
  bool TryPlayNextUnlocked();
  void ApplyVfUnlocked();
  void ApplySubtitleUnlocked();
  void ApplyShowTypeUnlocked();
  std::pair<int64_t, bool> FindTrackId(const char* type, int index);

  Callbacks cb_{};
  mpv_handle* mpv_ = nullptr;
  mpv_render_context* render_ = nullptr;

  std::thread worker_;
  std::mutex wake_mu_;
  std::condition_variable wake_cv_;
  bool quit_ = false;
  bool woke_ = false;

  std::mutex frame_mu_;
  std::vector<uint8_t> rgba_;
  int frame_w_ = 0;
  int frame_h_ = 0;
  int output_w_ = 16;
  int output_h_ = 16;
  int video_w_ = 0;
  int video_h_ = 0;

  std::mutex api_mu_;
  int state_ = 0;  // CommonPlayerState.idle
  bool auto_play_ = true;
  bool looping_ = false;
  bool keep_last_frame_ = false;
  int64_t seek_on_start_ms_ = -1;
  bool file_loaded_ = false;
  bool eof_ = false;
  bool paused_ = true;
  bool seeking_ = false;
  bool paused_for_cache_ = false;
  double volume_ = 1.0;

  std::vector<std::string> playlist_;
  int playlist_index_ = 0;
  bool auto_play_next_ = true;
  bool mirror_h_ = false;
  bool mirror_v_ = false;
  int show_type_ = 0;
  std::string subtitle_url_;
  bool subtitle_enabled_ = true;

  int64_t last_pos_emit_ms_ = 0;
};

}  // namespace kinetic

#endif  // KINETIC_MPV_PLAYER_H_
