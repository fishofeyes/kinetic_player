import type Artplayer from 'artplayer';
import Hls from 'hls.js';
import * as dashjs from 'dashjs';

import type { ArtplayerWithStream } from './types';

/** Mirrors artplayer `CustomType` without deep package path imports. */
type CustomType =
  | 'flv'
  | 'm3u8'
  | 'hls'
  | 'ts'
  | 'mpd'
  | 'torrent'
  | (string & Record<never, never>);

type CustomTypeHandler = (
  this: Artplayer,
  video: HTMLVideoElement,
  url: string,
  art: Artplayer,
) => unknown;

export type CustomTypeMap = Partial<Record<CustomType, CustomTypeHandler>>;

export interface StreamHttpOptions {
  userAgent?: string;
  headers?: Record<string, string>;
}

function asStreamArt(art: Artplayer): ArtplayerWithStream {
  return art as ArtplayerWithStream;
}

function mergedHeaders(http?: StreamHttpOptions): Record<string, string> {
  const headers: Record<string, string> = { ...(http?.headers ?? {}) };
  if (http?.userAgent && http.userAgent.length > 0) {
    // Browsers typically forbid overriding User-Agent on XHR; set when allowed.
    headers['User-Agent'] = http.userAgent;
  }
  return headers;
}

function applyHeadersToXhr(
  xhr: XMLHttpRequest,
  headers: Record<string, string>,
): void {
  for (const [key, value] of Object.entries(headers)) {
    try {
      xhr.setRequestHeader(key, value);
    } catch {
      // Forbidden header names are ignored by the browser.
    }
  }
}

/**
 * Wires HLS / DASH customType handlers used by hls-control / dash-control plugins.
 * Safe to merge with host-provided customType (host wins on key collision).
 */
export function buildStreamCustomType(
  existing?: CustomTypeMap,
  http?: StreamHttpOptions,
): CustomTypeMap {
  const customType: CustomTypeMap = { ...(existing ?? {}) };
  const headers = mergedHeaders(http);

  if (!customType.m3u8 && !customType.hls) {
    const hlsHandler: CustomTypeHandler = function (video, url, art) {
      const streamArt = asStreamArt(art);
      if (Hls.isSupported()) {
        streamArt.hls?.destroy();
        const hls = new Hls({
          // hls.js 1.7: xhrSetup may receive (xhr, url, context); headers only need xhr.
          xhrSetup: (xhr, _url) => {
            applyHeadersToXhr(xhr, headers);
          },
        });
        hls.loadSource(url);
        hls.attachMedia(video);
        streamArt.hls = hls;
        art.on('destroy', () => hls.destroy());
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = url;
      } else {
        art.notice.show = 'Unsupported HLS playback';
      }
    };
    customType.m3u8 = hlsHandler;
    customType.hls = hlsHandler;
  }

  if (!customType.mpd && !customType.dash) {
    const dashHandler: CustomTypeHandler = function (video, url, art) {
      const streamArt = asStreamArt(art);
      streamArt.dash?.reset();
      const player = dashjs.MediaPlayer().create();
      if (Object.keys(headers).length > 0) {
        player.extendRequestModifier({
          modifyRequestHeader: (request) => {
            for (const [key, value] of Object.entries(headers)) {
              request.setRequestHeader(key, value);
            }
            return request;
          },
        });
      }
      player.initialize(video, url, false);
      streamArt.dash = player;
      art.on('destroy', () => player.reset());
    };
    customType.mpd = dashHandler;
    customType.dash = dashHandler;
  }

  return customType;
}

/** Infer Artplayer `type` from URL when not set explicitly. */
export function inferStreamType(url?: string): CustomType | undefined {
  if (!url) return undefined;
  const lower = url.split('?')[0]?.toLowerCase() ?? '';
  if (lower.endsWith('.m3u8')) return 'm3u8';
  if (lower.endsWith('.mpd')) return 'mpd';
  return undefined;
}
