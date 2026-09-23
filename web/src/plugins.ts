import type Artplayer from 'artplayer';
import artplayerPluginAds from 'artplayer-plugin-ads';
import artplayerPluginAmbilight from 'artplayer-plugin-ambilight';
import artplayerPluginAsr from 'artplayer-plugin-asr';
import artplayerPluginAudioTrack from 'artplayer-plugin-audio-track';
import artplayerPluginAutoThumbnail from 'artplayer-plugin-auto-thumbnail';
import artplayerPluginChapter from 'artplayer-plugin-chapter';
import artplayerPluginChromecast from 'artplayer-plugin-chromecast';
import artplayerPluginDanmuku from 'artplayer-plugin-danmuku';
import artplayerPluginDashControl from 'artplayer-plugin-dash-control';
import artplayerPluginDocumentPip from 'artplayer-plugin-document-pip';
import artplayerPluginHlsControl from 'artplayer-plugin-hls-control';
import artplayerPluginJassub from 'artplayer-plugin-jassub';
import artplayerPluginMultipleSubtitles from 'artplayer-plugin-multiple-subtitles';
import artplayerPluginVast from 'artplayer-plugin-vast';
import artplayerPluginVttThumbnail from 'artplayer-plugin-vtt-thumbnail';

import type { ArtPluginsConfig, ArtplayerWithStream, PluginFactory } from './types';

/** Stable keys accepted from Dart `artPlugins` / webCustomExtensions. */
export const ART_PLUGIN_KEYS = [
  'danmuku',
  'danmukuMask',
  'hlsControl',
  'dashControl',
  'vttThumbnail',
  'multipleSubtitles',
  'chromecast',
  'vast',
  'chapter',
  'autoThumbnail',
  'ambilight',
  'documentPip',
  'audioTrack',
  'jassub',
  'asr',
  'ads',
] as const;

export type ArtPluginKey = (typeof ART_PLUGIN_KEYS)[number];

const DANMUKU_MASK_CDN =
  'https://cdn.jsdelivr.net/npm/artplayer-plugin-danmuku-mask@1.1.0/dist/artplayer-plugin-danmuku-mask.js';

function isEnabled(value: unknown): boolean {
  if (value === false || value == null) return false;
  return true;
}

function asOption(value: unknown): Record<string, unknown> {
  if (value === true) return {};
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

type NamedPlugin = { name?: string; update?: () => void };

/**
 * Official hls/dash-control plugins throw on ready when art.hls / art.dash
 * is missing (e.g. progressive MP4). Rebind update to no-op until the engine
 * is attached so enabling the plugin is safe for mixed playlists.
 */
function softStreamControl(
  art: Artplayer,
  installed: NamedPlugin,
  isReady: (art: Artplayer) => boolean,
): NamedPlugin {
  const originalUpdate = installed.update;
  if (typeof originalUpdate !== 'function') return installed;

  const safeUpdate = (): void => {
    if (!isReady(art)) return;
    originalUpdate.call(installed);
  };

  art.off('ready', originalUpdate);
  art.off('restart', originalUpdate);
  art.on('ready', safeUpdate);
  art.on('restart', safeUpdate);

  return { ...installed, update: safeUpdate };
}

function wrapHlsControl(
  option: Parameters<typeof artplayerPluginHlsControl>[0],
): PluginFactory {
  const factory = artplayerPluginHlsControl(option);
  return (art) => {
    const installed = factory(art) as NamedPlugin;
    return softStreamControl(art, installed, (a) => {
      const stream = a as ArtplayerWithStream;
      return Boolean(stream.hls && stream.hls.media === a.template.$video);
    });
  };
}

function wrapDashControl(
  option: Parameters<typeof artplayerPluginDashControl>[0],
): PluginFactory {
  const factory = artplayerPluginDashControl(option);
  return (art) => {
    const installed = factory(art) as NamedPlugin;
    return softStreamControl(art, installed, (a) => {
      const stream = a as ArtplayerWithStream;
      const dash = stream.dash as
        | { getVideoElement?: () => HTMLVideoElement | null }
        | undefined;
      try {
        return Boolean(dash && dash.getVideoElement?.() === a.template.$video);
      } catch {
        return false;
      }
    });
  };
}

function loadScriptOnce(src: string, globalFlag: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const w = window as unknown as Record<string, unknown>;
    if (w[globalFlag]) {
      resolve();
      return;
    }
    const existing = document.querySelector(`script[data-kinetic-plugin="${src}"]`);
    if (existing) {
      existing.addEventListener('load', () => resolve());
      existing.addEventListener('error', () =>
        reject(new Error(`Failed to load plugin script: ${src}`)),
      );
      return;
    }
    const script = document.createElement('script');
    script.src = src;
    script.async = true;
    script.dataset['kineticPlugin'] = src;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Failed to load plugin script: ${src}`));
    document.head.appendChild(script);
  });
}

async function loadDanmukuMaskFactory(): Promise<
  (option?: Record<string, unknown>) => PluginFactory
> {
  await loadScriptOnce(DANMUKU_MASK_CDN, 'artplayerPluginDanmukuMask');
  const factory = (window as unknown as {
    artplayerPluginDanmukuMask?: (option?: Record<string, unknown>) => PluginFactory;
  }).artplayerPluginDanmukuMask;
  if (!factory) {
    throw new Error('artplayerPluginDanmukuMask global missing after CDN load');
  }
  return factory;
}

/**
 * Builds Artplayer `plugins` array from a JSON-serializable config map.
 * Heavy MediaPipe-based danmukuMask is CDN-lazy-loaded when enabled.
 */
export async function resolveArtPlugins(
  config?: ArtPluginsConfig | null,
): Promise<PluginFactory[]> {
  if (!config) return [];

  const plugins: PluginFactory[] = [];

  if (isEnabled(config.danmuku)) {
    const option = asOption(config.danmuku);
    plugins.push(
      artplayerPluginDanmuku({
        danmuku: option['danmuku'] ?? [],
        ...option,
      } as Parameters<typeof artplayerPluginDanmuku>[0]),
    );
  }

  if (isEnabled(config.danmukuMask)) {
    const factory = await loadDanmukuMaskFactory();
    plugins.push(factory(asOption(config.danmukuMask)));
  }

  if (isEnabled(config.hlsControl)) {
    plugins.push(
      wrapHlsControl(
        asOption(config.hlsControl) as Parameters<typeof artplayerPluginHlsControl>[0],
      ),
    );
  }

  if (isEnabled(config.dashControl)) {
    plugins.push(
      wrapDashControl(
        asOption(config.dashControl) as Parameters<typeof artplayerPluginDashControl>[0],
      ),
    );
  }

  if (isEnabled(config.vttThumbnail)) {
    const option = asOption(config.vttThumbnail);
    // Official plugin fetches option.vtt and parses cues via regex; missing/empty
    // vtt throws "Cannot read properties of null (reading '1')".
    if (typeof option['vtt'] === 'string' && option['vtt'].length > 0) {
      plugins.push(
        artplayerPluginVttThumbnail(
          option as Parameters<typeof artplayerPluginVttThumbnail>[0],
        ),
      );
    }
  }

  if (isEnabled(config.multipleSubtitles)) {
    const option = asOption(config.multipleSubtitles);
    plugins.push(
      artplayerPluginMultipleSubtitles({
        subtitles: (option['subtitles'] as never[]) ?? [],
        ...option,
      } as Parameters<typeof artplayerPluginMultipleSubtitles>[0]),
    );
  }

  if (isEnabled(config.chromecast)) {
    plugins.push(
      artplayerPluginChromecast(
        asOption(config.chromecast) as Parameters<typeof artplayerPluginChromecast>[0],
      ),
    );
  }

  if (isEnabled(config.chapter)) {
    plugins.push(
      artplayerPluginChapter(
        asOption(config.chapter) as Parameters<typeof artplayerPluginChapter>[0],
      ),
    );
  }

  if (isEnabled(config.autoThumbnail)) {
    plugins.push(
      artplayerPluginAutoThumbnail(
        asOption(config.autoThumbnail) as Parameters<typeof artplayerPluginAutoThumbnail>[0],
      ),
    );
  }

  if (isEnabled(config.ambilight)) {
    plugins.push(
      artplayerPluginAmbilight(
        asOption(config.ambilight) as Parameters<typeof artplayerPluginAmbilight>[0],
      ),
    );
  }

  if (isEnabled(config.documentPip)) {
    plugins.push(
      artplayerPluginDocumentPip(
        asOption(config.documentPip) as Parameters<typeof artplayerPluginDocumentPip>[0],
      ),
    );
  }

  if (isEnabled(config.audioTrack)) {
    const option = asOption(config.audioTrack);
    if (typeof option['url'] === 'string' && option['url']) {
      plugins.push(
        artplayerPluginAudioTrack(
          option as unknown as Parameters<typeof artplayerPluginAudioTrack>[0],
        ),
      );
    }
  }

  if (isEnabled(config.jassub)) {
    plugins.push(
      artplayerPluginJassub(
        asOption(config.jassub) as unknown as Parameters<
          typeof artplayerPluginJassub
        >[0],
      ),
    );
  }

  if (isEnabled(config.asr)) {
    plugins.push(
      artplayerPluginAsr(
        asOption(config.asr) as unknown as Parameters<typeof artplayerPluginAsr>[0],
      ),
    );
  }

  if (isEnabled(config.vast)) {
    const option = asOption(config.vast);
    const tagUrl = option['tagUrl'] ?? option['url'];
    plugins.push(
      artplayerPluginVast((ctx) => {
        // Package types expose playUrl/playRes (no init()).
        if (typeof tagUrl === 'string' && tagUrl) {
          ctx.playUrl(tagUrl);
        }
      }),
    );
  }

  if (isEnabled(config.ads)) {
    const option = asOption(config.ads);
    if (typeof option['source'] === 'string' && option['type']) {
      plugins.push(
        artplayerPluginAds(
          option as unknown as Parameters<typeof artplayerPluginAds>[0],
        ),
      );
    }
  }

  return plugins;
}

/** Plugin instance accessors on `art.plugins`. */
export function getPluginInstance(
  art: Artplayer,
  name: string,
): Record<string, unknown> | null {
  const plugins = (art as unknown as { plugins?: Record<string, unknown> }).plugins;
  if (!plugins) return null;
  const direct = plugins[name];
  if (direct && typeof direct === 'object') {
    return direct as Record<string, unknown>;
  }
  for (const key of Object.keys(plugins)) {
    const value = plugins[key];
    if (
      value &&
      typeof value === 'object' &&
      (value as { name?: string }).name === name
    ) {
      return value as Record<string, unknown>;
    }
  }
  return null;
}
