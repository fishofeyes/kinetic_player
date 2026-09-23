import Artplayer, { type Option as ArtplayerOption } from 'artplayer';
import { ART_PLUGIN_KEYS, getPluginInstance, resolveArtPlugins } from './plugins';
import {
  buildStreamCustomType,
  inferStreamType,
  type CustomTypeMap,
  type StreamHttpOptions,
} from './stream_types';
import type {
  ArtPluginsConfig,
  ArtplayerWithStream,
  AudioTrackInfo,
  KineticArtplayerConfig,
  PluginFactory,
  ScaleMode,
  VideoSizeInfo,
} from './types';
import { PlayerState, ScaleMode as ScaleModeEnum } from './types';

const POSITION_THROTTLE_MS = 250;

function argbToCssHex(argb: number): string {
  const rgb = argb & 0xffffff;
  return `#${rgb.toString(16).padStart(6, '0')}`;
}

function artLangFromLocale(locale?: string): string {
  const code = (locale ?? 'zh').toLowerCase().split(/[-_]/)[0];
  switch (code) {
    case 'en':
      return 'en';
    case 'id':
      return 'id';
    case 'vi':
      return 'vi';
    case 'ms':
      return 'ms';
    case 'fil':
    case 'tl':
      return 'fil';
    default:
      return 'zh-cn';
  }
}

function artI18nFromStrings(strings?: Record<string, string>): Record<string, string> {
  if (!strings) return {};
  const pick = (key: string, fallback: string): string => {
    const value = strings[key];
    return value && value.length > 0 ? value : fallback;
  };
  return {
    Volume: pick('kinetic_volume_icon', 'Volume'),
    Settings: pick('kinetic_settings_title', 'Settings'),
    Fullscreen: pick('kinetic_fullscreen_icon', 'Fullscreen'),
    'Play Speed': pick('kinetic_rate_title', 'Speed'),
    'Aspect Ratio': pick('kinetic_settings_aspect', 'Aspect ratio'),
    Loop: pick('kinetic_settings_loop', 'Loop'),
  };
}

function artI18nOption(
  locale?: string,
  strings?: Record<string, string>,
): Record<string, Record<string, string>> | undefined {
  const lang = artLangFromLocale(locale);
  if (lang === 'zh-cn' || lang === 'en' || lang === 'id') return undefined;
  return { [lang]: artI18nFromStrings(strings) };
}

/**
 * Artplayer adapter for kinetic_player Web.
 * Maps public API (play/pause/seek/volume/rate/dispose/togglePip) to Artplayer.
 */
export class KineticArtplayerAdapter {
  private art: Artplayer;
  private readonly config: KineticArtplayerConfig;
  private disposed = false;
  private lastPositionEmit = 0;
  private state: PlayerState = PlayerState.idle;
  private volumeBeforeMute = 1;
  private muted = false;
  private looping = false;
  private pipActive = false;
  private scaleMode: ScaleMode = ScaleModeEnum.fit;
  private httpOptions: StreamHttpOptions = {};

  private constructor(
    config: KineticArtplayerConfig,
    resolvedPlugins: PluginFactory[],
  ) {
    this.config = config;
    this.httpOptions = {
      userAgent: config.userAgent,
      headers: config.headers,
    };
    const ui = config.ui ?? {};
    const enableControls = ui.enableNativeControls !== false;
    const pipEnabled = ui.pictureInPictureEnabled !== false;

    const extensions = {
      ...(config.artplayerOptions ?? {}),
      ...(config.webCustomExtensions ?? {}),
    };
    const {
      artPlugins: _ignoredPlugins,
      plugins: existingPlugins,
      customType: existingCustomType,
      type: explicitType,
      ...custom
    } = extensions as Record<string, unknown> & {
      artPlugins?: ArtPluginsConfig;
      plugins?: PluginFactory[];
      customType?: CustomTypeMap;
      type?: string;
    };

    const pluginsConfig =
      config.artPlugins ??
      (_ignoredPlugins as ArtPluginsConfig | undefined) ??
      (config.webCustomExtensions?.['artPlugins'] as ArtPluginsConfig | undefined);

    const mergedPlugins = [
      ...resolvedPlugins,
      ...((Array.isArray(existingPlugins) ? existingPlugins : []) as PluginFactory[]),
    ];

    const url = config.url ?? '';
    const streamType =
      (typeof explicitType === 'string' && explicitType) || inferStreamType(url);
    const needsStreamCustomType =
      Boolean(pluginsConfig?.hlsControl) ||
      Boolean(pluginsConfig?.dashControl) ||
      streamType === 'm3u8' ||
      streamType === 'mpd' ||
      streamType === 'hls' ||
      streamType === 'dash';

    this.looping = ui.looping === true;

    const accentArgb =
      typeof ui.accentColor === 'number' ? ui.accentColor : 0xfffb7299;
    const themeHex = argbToCssHex(accentArgb);
    const i18n = artI18nOption(ui.locale, ui.strings);

    const option: ArtplayerOption = {
      container: config.container,
      url,
      poster: ui.coverUrl,
      volume: 1,
      autoplay: false,
      muted: false,
      autoSize: false,
      loop: this.looping,
      playbackRate: true,
      aspectRatio: true,
      screenshot: false,
      setting: ui.showSettingsButton !== false && enableControls,
      hotkey: enableControls,
      pip: pipEnabled && enableControls,
      mutex: true,
      fullscreen: ui.showFullscreenButton !== false && enableControls,
      fullscreenWeb: false,
      miniProgressBar: enableControls,
      playsInline: true,
      lock: enableControls,
      gesture: enableControls,
      autoOrientation: false,
      theme: themeHex,
      lang: artLangFromLocale(ui.locale),
      ...(i18n ? { i18n } : {}),
      moreVideoAttr: {
        // Typed attr is playsInline; WebKit / X5 attrs set in applyMobileInlineAttributes.
        playsInline: true,
        controls: false,
        preload: 'metadata',
      },
      ...(custom as Partial<ArtplayerOption>),
      ...(streamType ? { type: streamType } : {}),
      ...(needsStreamCustomType
        ? {
            customType: buildStreamCustomType(
              existingCustomType,
              this.httpOptions,
            ),
          }
        : existingCustomType
          ? { customType: existingCustomType }
          : {}),
      ...(mergedPlugins.length > 0 ? { plugins: mergedPlugins } : {}),
    };

    this.art = new Artplayer(option);
    if (typeof ui.speed === 'number' && ui.speed > 0) {
      this.art.playbackRate = ui.speed;
    }

    if (!enableControls) {
      this.hideNativeChrome();
    }

    this.applyMobileInlineAttributes();
    this.bindEvents();
    this.setupPipListeners();
  }

  static async create(config: KineticArtplayerConfig): Promise<KineticArtplayerAdapter> {
    const extensions = {
      ...(config.artplayerOptions ?? {}),
      ...(config.webCustomExtensions ?? {}),
    };
    const pluginsConfig =
      config.artPlugins ??
      (extensions['artPlugins'] as ArtPluginsConfig | undefined) ??
      (config.webCustomExtensions?.['artPlugins'] as ArtPluginsConfig | undefined);
    const resolved = await resolveArtPlugins(pluginsConfig);
    return new KineticArtplayerAdapter(config, resolved);
  }

  private hideNativeChrome(): void {
    const style = document.createElement('style');
    style.textContent = `
      .kinetic-art-nocontrols .art-bottom,
      .kinetic-art-nocontrols .art-controls,
      .kinetic-art-nocontrols .art-notice,
      .kinetic-art-nocontrols .art-contextmenus {
        display: none !important;
      }
    `;
    document.head.appendChild(style);
    this.config.container.classList.add('kinetic-art-nocontrols');
  }

  private applyMobileInlineAttributes(): void {
    const video = this.art.video;
    if (!video) return;
    video.setAttribute('playsinline', 'true');
    video.setAttribute('webkit-playsinline', 'true');
    video.setAttribute('x5-video-player-type', 'h5');
    video.controls = false;
  }

  private bindEvents(): void {
    this.art.on('ready', () => {
      this.applyMobileInlineAttributes();
      this.applyScaleMode(this.scaleMode);
      this.emitState(PlayerState.ready);
    });

    this.art.on('play', () => this.emitState(PlayerState.playing));
    this.art.on('video:play', () => this.emitState(PlayerState.playing));
    this.art.on('pause', () => {
      if (this.state !== PlayerState.completed) {
        this.emitState(PlayerState.paused);
      }
    });
    this.art.on('video:pause', () => {
      if (this.state !== PlayerState.completed) {
        this.emitState(PlayerState.paused);
      }
    });
    this.art.on('video:waiting', () => this.emitState(PlayerState.buffering));
    this.art.on('video:seeking', () => this.emitState(PlayerState.buffering));
    this.art.on('video:seeked', () => {
      this.emitPosition(true);
      if (!this.art.playing) {
        this.emitState(PlayerState.paused);
      } else {
        this.emitState(PlayerState.playing);
      }
    });
    this.art.on('video:ended', () => {
      if (this.looping) {
        void this.seek(0).then(() => this.play());
        return;
      }
      this.emitState(PlayerState.completed);
    });
    this.art.on('video:timeupdate', () => this.emitPosition(false));
    this.art.on('error', (error: unknown) => {
      const message =
        error instanceof Error
          ? error.message
          : typeof error === 'string'
            ? error
            : 'Artplayer error';
      this.config.onError?.(message);
      this.emitState(PlayerState.error);
    });
  }

  private setupPipListeners(): void {
    this.art.on('pip', (state: boolean) => {
      this.pipActive = Boolean(state);
      this.config.onPipChanged?.(this.pipActive);
    });

    const video = this.art.video;
    if (!video) return;
    video.addEventListener('enterpictureinpicture', () => {
      this.pipActive = true;
      this.config.onPipChanged?.(true);
    });
    video.addEventListener('leavepictureinpicture', () => {
      this.pipActive = false;
      this.config.onPipChanged?.(false);
    });
  }

  private emitState(state: PlayerState): void {
    if (this.disposed || this.state === state) return;
    this.state = state;
    this.config.onStateChanged?.(state);
  }

  private emitPosition(force: boolean): void {
    if (this.disposed) return;
    const now = Date.now();
    if (!force && now - this.lastPositionEmit < POSITION_THROTTLE_MS) return;
    this.lastPositionEmit = now;
    const positionMs = Math.max(0, Math.floor((this.art.currentTime ?? 0) * 1000));
    const durationMs = Math.max(0, Math.floor((this.art.duration ?? 0) * 1000));
    this.config.onPositionChanged?.(positionMs, durationMs);
  }

  async play(): Promise<void> {
    try {
      await this.art.play();
    } catch {
      // Autoplay policy fallback: mute then retry.
      this.art.muted = true;
      this.muted = true;
      try {
        await this.art.play();
      } catch (error) {
        const message =
          error instanceof Error ? error.message : 'Playback failed (user gesture required)';
        this.config.onError?.(message);
        this.emitState(PlayerState.error);
        throw error;
      }
    }
  }

  pause(): void {
    this.art.pause();
  }

  stop(): void {
    this.art.pause();
    this.art.currentTime = 0;
    this.emitState(PlayerState.idle);
    this.emitPosition(true);
  }

  async seek(positionMs: number): Promise<void> {
    const seconds = Math.max(0, positionMs) / 1000;
    this.art.currentTime = seconds;
    this.emitPosition(true);
  }

  setVolume(volume: number): void {
    const clamped = Math.min(1, Math.max(0, volume));
    this.art.volume = clamped;
    if (clamped > 0) {
      this.volumeBeforeMute = clamped;
      this.muted = false;
      this.art.muted = false;
    }
  }

  setMute(muted: boolean): void {
    this.muted = muted;
    if (muted) {
      this.volumeBeforeMute = this.art.volume || this.volumeBeforeMute;
      this.art.muted = true;
    } else {
      this.art.muted = false;
      this.art.volume = this.volumeBeforeMute || 1;
    }
  }

  setPlaybackRate(rate: number): void {
    this.art.playbackRate = rate;
  }

  setLooping(looping: boolean): void {
    this.looping = looping;
    // Artplayer 5.4 exposes loop via option; keep local flag for ended handler.
    (
      this.art as Artplayer & {
        option: { loop?: boolean };
      }
    ).option.loop = looping;
  }

  setScaleMode(mode: ScaleMode): void {
    this.scaleMode = mode;
    this.applyScaleMode(mode);
  }

  private applyScaleMode(mode: ScaleMode): void {
    const video = this.art.video;
    if (!video) return;
    switch (mode) {
      case ScaleModeEnum.fill:
        video.style.objectFit = 'cover';
        break;
      case ScaleModeEnum.stretch:
        video.style.objectFit = 'fill';
        break;
      case ScaleModeEnum.fit:
      default:
        video.style.objectFit = 'contain';
        break;
    }
  }

  async switchVideoSource(url: string, autoPlay = true): Promise<void> {
    this.emitState(PlayerState.buffering);
    this.destroyStreamEngines();
    // Artplayer 5.4: reset clears the previous video request before switchUrl.
    this.art.reset();
    const streamType = inferStreamType(url);
    if (streamType) {
      this.art.option.type = streamType;
      this.art.option.customType = buildStreamCustomType(
        undefined,
        this.httpOptions,
      );
    }
    await this.art.switchUrl(url);
    if (autoPlay) {
      await this.play();
    } else {
      this.emitState(PlayerState.ready);
    }
  }

  /** Tear down HLS/DASH engines attached by customType handlers. */
  private destroyStreamEngines(): void {
    const streamArt = this.art as ArtplayerWithStream;
    try {
      streamArt.hls?.destroy();
    } catch {
      // ignore
    }
    streamArt.hls = undefined;
    try {
      streamArt.dash?.reset();
    } catch {
      // ignore
    }
    streamArt.dash = undefined;
  }

  setHttpRequestOptions(options?: {
    userAgent?: string;
    headers?: Record<string, string>;
  }): void {
    const userAgent =
      typeof options?.userAgent === 'string' && options.userAgent.length > 0
        ? options.userAgent
        : undefined;
    const headers =
      options?.headers && Object.keys(options.headers).length > 0
        ? { ...options.headers }
        : undefined;
    this.httpOptions = { userAgent, headers };
    this.art.option.customType = buildStreamCustomType(
      undefined,
      this.httpOptions,
    );
  }

  getAudioTracks(): AudioTrackInfo[] {
    const tracks = this.readAudioTracks();
    // Most browsers do not expose HTMLMediaElement.audioTracks for plain
    // progressive media; return empty so hosts don't offer a fake selectable track.
    if (!tracks || tracks.length === 0) {
      return [];
    }
    const result: AudioTrackInfo[] = [];
    for (let i = 0; i < tracks.length; i++) {
      const t = tracks[i];
      result.push({
        index: i,
        label: t.label || `Track ${i + 1}`,
        language: t.language || undefined,
        selected: t.enabled,
      });
    }
    return result;
  }

  selectAudioTrack(index: number): boolean {
    const tracks = this.readAudioTracks();
    // No multi-track API: treat as single default stream — no-op success for 0.
    if (!tracks || tracks.length === 0) {
      return index === 0;
    }
    if (index < 0 || index >= tracks.length) return false;
    for (let i = 0; i < tracks.length; i++) {
      tracks[i].enabled = i === index;
    }
    return true;
  }

  private readAudioTracks():
    | {
        length: number;
        [index: number]: { label?: string; language?: string; enabled: boolean };
      }
    | undefined {
    const video = this.art.video as HTMLVideoElement & {
      audioTracks?: {
        length: number;
        [index: number]: { label?: string; language?: string; enabled: boolean };
      };
    };
    return video?.audioTracks;
  }

  getVideoSize(): VideoSizeInfo | null {
    const video = this.art.video;
    if (!video) return null;
    const width = video.videoWidth || 0;
    const height = video.videoHeight || 0;
    if (width <= 0 || height <= 0) return null;
    return { width, height };
  }

  getCurrentPositionMs(): number {
    return Math.max(0, Math.floor((this.art.currentTime ?? 0) * 1000));
  }

  getDurationMs(): number {
    return Math.max(0, Math.floor((this.art.duration ?? 0) * 1000));
  }

  get isPipActive(): boolean {
    return this.pipActive;
  }

  static get isPipSupported(): boolean {
    if (typeof document === 'undefined') return false;
    return Boolean(
      document.pictureInPictureEnabled &&
        (Artplayer as unknown as { html5?: { isPipSupported?: boolean } }).html5
          ?.isPipSupported !== false,
    );
  }

  async togglePip(): Promise<boolean> {
    if (!KineticArtplayerAdapter.isPipSupported) {
      throw new Error('PiP not supported on this platform');
    }
    this.art.pip = !this.art.pip;
    this.pipActive = Boolean(this.art.pip);
    return this.pipActive;
  }

  async captureFrame(): Promise<string | null> {
    try {
      const canvas = document.createElement('canvas');
      const video = this.art.video;
      if (!video || !video.videoWidth) return null;
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext('2d');
      if (!ctx) return null;
      ctx.drawImage(video, 0, 0);
      return canvas.toDataURL('image/png');
    } catch {
      return null;
    }
  }

  applyUiConfig(ui: KineticArtplayerConfig['ui']): void {
    if (!ui) return;
    if (typeof ui.looping === 'boolean') this.setLooping(ui.looping);
    if (typeof ui.speed === 'number' && ui.speed > 0) {
      this.setPlaybackRate(ui.speed);
    }
    if (ui.coverUrl) {
      this.art.poster = ui.coverUrl;
    }
    if (ui.enableNativeControls === false) {
      this.hideNativeChrome();
    }
  }

  applyLocale(locale?: string, strings?: Record<string, string>): void {
    const lang = artLangFromLocale(locale);
    const extra = artI18nOption(locale, strings);
    const i18n = this.art.i18n as { update?: (value: Record<string, Record<string, string>>) => void };
    if (extra && typeof i18n?.update === 'function') {
      i18n.update(extra);
    }
    this.art.option.lang = lang;
  }

  /** List of bundled plugin keys supported by this build. */
  static get availablePlugins(): readonly string[] {
    return ART_PLUGIN_KEYS;
  }

  getPlugin(name: string): Record<string, unknown> | null {
    return getPluginInstance(this.art, name);
  }

  /**
   * Invoke a method on a loaded plugin instance.
   * Example: callPlugin('artplayerPluginDanmuku', 'emit', [{ text: 'hi' }])
   */
  callPlugin(
    name: string,
    method: string,
    args: unknown[] = [],
  ): unknown {
    const plugin = this.getPlugin(name);
    if (!plugin) {
      throw new Error(`Plugin not loaded: ${name}`);
    }
    const fn = plugin[method];
    if (typeof fn !== 'function') {
      throw new Error(`Plugin method not found: ${name}.${method}`);
    }
    return (fn as (...a: unknown[]) => unknown).apply(plugin, args);
  }

  /** Convenience: emit a danmaku item when danmuku plugin is active. */
  emitDanmuku(danmu: Record<string, unknown>): unknown {
    const plugin =
      this.getPlugin('artplayerPluginDanmuku') ?? this.getPlugin('danmuku');
    if (!plugin || typeof plugin['emit'] !== 'function') {
      throw new Error('Danmuku plugin is not loaded');
    }
    return (plugin['emit'] as (d: Record<string, unknown>) => unknown)(danmu);
  }

  /** Document Picture-in-Picture toggle when document-pip plugin is active. */
  toggleDocumentPip(): boolean {
    const plugin = this.getPlugin('artplayerPluginDocumentPip');
    if (!plugin || typeof plugin['toggle'] !== 'function') {
      throw new Error('Document PiP plugin is not loaded');
    }
    (plugin['toggle'] as () => void)();
    return Boolean(plugin['isActive']);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    try {
      this.art.destroy(false);
    } catch {
      // ignore
    }
  }
}
