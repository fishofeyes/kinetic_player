import assert from 'node:assert/strict';
import { test } from 'node:test';
import vm from 'node:vm';
import { build } from 'esbuild';

// Model the public dash.js 5 API: removed APIs must fail this test.
const result = await build({
  entryPoints: [new URL('../src/stream_types.ts', import.meta.url).pathname],
  bundle: true,
  write: false,
  format: 'cjs',
  platform: 'node',
  plugins: [{
    name: 'stream-engines',
    setup(builder) {
      builder.onResolve({ filter: /^(dashjs|hls\.js)$/ }, ({ path }) => ({
        path, namespace: 'test-engine',
      }));
      builder.onLoad({ filter: /.*/, namespace: 'test-engine' }, ({ path }) => ({
        contents: path === 'dashjs'
          ? 'export const MediaPlayer = () => ({create: () => globalThis.dashPlayer});'
          : 'export default class Hls { static isSupported() { return false; } }',
      }));
    },
  }],
});

function loadBridge(dashPlayer) {
  const module = { exports: {} };
  vm.runInNewContext(result.outputFiles[0].text, { module, exports: module.exports, dashPlayer });
  return module.exports;
}

test('DASH applies custom headers through the v5 interceptor before playback', async () => {
  let interceptor;
  let initialized;
  let resetCount = 0;
  const player = {
    addRequestInterceptor(callback) { interceptor = callback; },
    initialize(...args) { initialized = args; },
    reset() { resetCount++; },
  };
  const bridge = loadBridge(player);
  const handlers = bridge.buildStreamCustomType(undefined, {
    headers: { Authorization: 'Bearer example', 'X-Test': 'new' },
  });
  let destroy;
  const art = { on(event, callback) { assert.equal(event, 'destroy'); destroy = callback; } };
  const video = {};
  handlers.mpd(video, 'https://example.test/video.mpd', art);
  assert.equal(art.dash, player);
  assert.deepEqual(initialized, [video, 'https://example.test/video.mpd', false]);
  const request = { headers: { Range: 'bytes=0-', 'X-Test': 'old' } };
  assert.equal(await interceptor(request), request);
  assert.equal(request.headers.Range, 'bytes=0-');
  assert.equal(request.headers.Authorization, 'Bearer example');
  assert.equal(request.headers['X-Test'], 'new');
  const noHeaders = {};
  await interceptor(noHeaders);
  assert.equal(noHeaders.headers.Authorization, 'Bearer example');
  destroy();
  assert.equal(resetCount, 1);
});

test('DASH without custom headers initializes without an interceptor', () => {
  const player = { initialize() {}, reset() {} };
  const handlers = loadBridge(player).buildStreamCustomType();
  handlers.mpd({}, 'https://example.test/video.mpd', { on() {} });
});

test('native HLS fallback and host custom handlers remain available', () => {
  const bridge = loadBridge({});
  const video = { canPlayType: () => 'maybe' };
  bridge.buildStreamCustomType().m3u8(video, 'https://example.test/video.m3u8', {});
  assert.equal(video.src, 'https://example.test/video.m3u8');
  const custom = () => {};
  assert.equal(bridge.buildStreamCustomType({ mpd: custom }).mpd, custom);
});
