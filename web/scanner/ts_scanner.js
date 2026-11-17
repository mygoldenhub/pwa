// PWA barcode engine for the Scan barcode page (web only).
//
// Native Android/iOS builds use Huawei Scan Kit and never load this file.
//
// Engines, best first:
//   1. The browser's own BarcodeDetector (Chrome on Android: ML Kit based).
//   2. zxing-wasm (zxing-cpp compiled to WebAssembly), self-hosted in ./vendor so it works
//      offline and on iPhone Safari, where BarcodeDetector doesn't exist.
//
// Accuracy measures for reflective / difficult packaging:
//   - Full-HD rear camera with continuous focus / exposure when the phone supports it.
//   - Decode a full-resolution crop of the scan band (more pixels per bar), with a full
//     frame every few passes.
//   - Alternate a contrast-stretched grayscale variant (pulls bars back out of glare) and
//     two zxing binarizers (LocalAverage copes with hot spots, GlobalHistogram with blur).
//   - "Take photo": the phone's native camera app (full resolution, HDR, proper focus),
//     then several crops / variants of that still photo.
//
// Exposes window.tsScanner (see the bottom of this file).

import { prepareZXingModule, readBarcodes } from './vendor/zxing-wasm/es/reader/index.js';

const WASM_URL = new URL('./vendor/zxing-wasm/reader/zxing_reader.wasm', import.meta.url).href;
prepareZXingModule({
  overrides: {
    locateFile: (path, prefix) => (path.endsWith('.wasm') ? WASM_URL : prefix + path),
  },
});

const NATIVE_FORMATS = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'itf'];
const ZXING_FORMATS = ['EAN13', 'EAN8', 'UPCA', 'UPCE', 'Code128', 'ITF'];

const LIVE_INTERVAL_MS = 90;
// Scan band in the video frame: matches the guide box drawn by Flutter (centred ~45% down).
const BAND_CENTER_Y = 0.45;
const BAND_HEIGHT = 0.42;
const PHOTO_MAX_SIDE = 2600;

const log = (...args) => console.debug('[tsScanner]', ...args);

// ---------------------------------------------------------------------------
// Engines

let nativeDetectorPromise = null;

function nativeDetector() {
  if (!nativeDetectorPromise) {
    nativeDetectorPromise = (async () => {
      if (!('BarcodeDetector' in window)) return null;
      try {
        const supported = await window.BarcodeDetector.getSupportedFormats();
        if (!supported.includes('ean_13')) return null;
        const formats = NATIVE_FORMATS.filter((f) => supported.includes(f));
        log('native BarcodeDetector', formats);
        return new window.BarcodeDetector({ formats });
      } catch (e) {
        log('native BarcodeDetector unavailable', e);
        return null;
      }
    })();
  }
  return nativeDetectorPromise;
}

function zxingOptions(binarizer) {
  return {
    formats: ZXING_FORMATS,
    tryHarder: true,
    tryRotate: true,
    tryInvert: true,
    tryDownscale: true,
    binarizer,
    maxNumberOfSymbols: 4,
    textMode: 'HRI', // GS1-128 comes back as "(01)…(30)…", which the app's validator understands
  };
}

async function decodeWithNative(canvas) {
  const detector = await nativeDetector();
  if (!detector) return [];
  try {
    const found = await detector.detect(canvas);
    return found.map((b) => b.rawValue).filter(Boolean);
  } catch (e) {
    log('native detect failed', e);
    return [];
  }
}

async function decodeWithZxing(imageData, binarizer) {
  try {
    const found = await readBarcodes(imageData, zxingOptions(binarizer));
    return found.filter((r) => r.isValid && r.text).map((r) => r.text);
  } catch (e) {
    log('zxing failed', e);
    return [];
  }
}

/** Native first (fast, ML based), then zxing on the same pixels. */
async function decodeCanvas(canvas, ctx, binarizer) {
  const native = await decodeWithNative(canvas);
  if (native.length) return native;
  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  return decodeWithZxing(imageData, binarizer);
}

// ---------------------------------------------------------------------------
// Image helpers

function makeCanvas() {
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  return { canvas, ctx };
}

/** Draws [src] region (sx, sy, sw, sh) into the canvas, scaled by [scale]. */
function drawRegion(target, src, sx, sy, sw, sh, scale = 1) {
  const w = Math.max(1, Math.round(sw * scale));
  const h = Math.max(1, Math.round(sh * scale));
  if (target.canvas.width !== w) target.canvas.width = w;
  if (target.canvas.height !== h) target.canvas.height = h;
  target.ctx.imageSmoothingEnabled = scale < 1;
  target.ctx.drawImage(src, sx, sy, sw, sh, 0, 0, w, h);
}

/**
 * Grayscale + percentile contrast stretch, in place on the canvas.
 * Glare lifts the dark bars towards white; stretching the 2nd–98th percentile back to
 * 0–255 restores the bar/space contrast the decoders need.
 */
function contrastStretch(target) {
  const { canvas, ctx } = target;
  const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const d = img.data;
  const hist = new Uint32Array(256);
  const gray = new Uint8ClampedArray(d.length / 4);
  for (let i = 0, p = 0; i < d.length; i += 4, p++) {
    const y = (d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29) >> 8;
    gray[p] = y;
    hist[y]++;
  }
  const total = gray.length;
  let lo = 0;
  let hi = 255;
  for (let acc = 0; lo < 255 && (acc += hist[lo]) < total * 0.02; lo++);
  for (let acc = 0; hi > 0 && (acc += hist[hi]) < total * 0.02; hi--);
  const range = Math.max(1, hi - lo);
  for (let i = 0, p = 0; i < d.length; i += 4, p++) {
    const v = ((gray[p] - lo) * 255) / range;
    d[i] = d[i + 1] = d[i + 2] = v;
  }
  ctx.putImageData(img, 0, 0);
}

// ---------------------------------------------------------------------------
// Live camera

const live = {
  generation: 0,
  stream: null,
  track: null,
  video: null,
  timer: null,
  frame: 0,
  work: null,
};

function stopLive() {
  live.generation++;
  if (live.timer) clearTimeout(live.timer);
  live.timer = null;
  if (live.stream) {
    for (const t of live.stream.getTracks()) {
      try {
        t.stop();
      } catch (_) {}
    }
  }
  if (live.video) {
    try {
      live.video.pause();
      live.video.srcObject = null;
    } catch (_) {}
  }
  live.stream = null;
  live.track = null;
}

function cameraErrorCode(e) {
  const name = e && e.name;
  if (name === 'NotAllowedError' || name === 'SecurityError' || name === 'PermissionDeniedError') {
    return 'permission';
  }
  if (name === 'NotFoundError' || name === 'OverconstrainedError' || name === 'DevicesNotFoundError') {
    return 'no-camera';
  }
  if (name === 'NotReadableError' || name === 'TrackStartError') return 'busy';
  return 'error:' + ((e && e.message) || String(e));
}

async function tuneTrack(track) {
  const caps = (track.getCapabilities && track.getCapabilities()) || {};
  const advanced = [];
  if (Array.isArray(caps.focusMode) && caps.focusMode.includes('continuous')) {
    advanced.push({ focusMode: 'continuous' });
  }
  if (Array.isArray(caps.exposureMode) && caps.exposureMode.includes('continuous')) {
    advanced.push({ exposureMode: 'continuous' });
  }
  if (Array.isArray(caps.whiteBalanceMode) && caps.whiteBalanceMode.includes('continuous')) {
    advanced.push({ whiteBalanceMode: 'continuous' });
  }
  for (const constraint of advanced) {
    try {
      await track.applyConstraints({ advanced: [constraint] });
    } catch (e) {
      log('constraint rejected', constraint, e);
    }
  }
  const s = track.getSettings ? track.getSettings() : {};
  log('camera', s.width + 'x' + s.height, 'focus=' + s.focusMode, 'torch=' + !!caps.torch);
}

async function startLive(video, onCodes, onError) {
  stopLive();
  const gen = live.generation;
  live.video = video;
  live.frame = 0;
  live.work = live.work || makeCanvas();

  video.setAttribute('playsinline', '');
  video.setAttribute('muted', '');
  video.muted = true;
  video.autoplay = true;

  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    onError(window.isSecureContext ? 'no-camera' : 'insecure');
    return;
  }

  let stream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: { ideal: 'environment' },
        width: { ideal: 1920 },
        height: { ideal: 1080 },
      },
    });
  } catch (e) {
    if (gen === live.generation) onError(cameraErrorCode(e));
    return;
  }
  if (gen !== live.generation) {
    stream.getTracks().forEach((t) => t.stop());
    return;
  }

  live.stream = stream;
  live.track = stream.getVideoTracks()[0] || null;
  if (live.track) await tuneTrack(live.track);

  video.srcObject = stream;
  try {
    await video.play();
  } catch (e) {
    log('video.play failed', e);
  }

  const tick = async () => {
    if (gen !== live.generation) return;
    const started = performance.now();
    try {
      if (video.readyState >= 2 && video.videoWidth > 0) {
        const codes = await decodeLiveFrame(video, live.frame++);
        if (gen !== live.generation) return;
        if (codes.length) onCodes(codes);
      }
    } catch (e) {
      log('frame failed', e);
    }
    const elapsed = performance.now() - started;
    live.timer = setTimeout(tick, Math.max(0, LIVE_INTERVAL_MS - elapsed));
  };
  tick();
}

async function decodeLiveFrame(video, n) {
  const vw = video.videoWidth;
  const vh = video.videoHeight;
  const work = live.work;

  // Every 4th pass looks at the whole frame; the rest at the scan band in full resolution.
  if (n % 4 === 3) {
    drawRegion(work, video, 0, 0, vw, vh);
  } else {
    const bandH = Math.round(vh * BAND_HEIGHT);
    const top = Math.min(Math.max(0, Math.round(vh * BAND_CENTER_Y - bandH / 2)), vh - bandH);
    drawRegion(work, video, 0, top, vw, bandH);
  }

  // Alternate raw / contrast-stretched pixels, and the zxing binarizer every other pair.
  if (n % 2 === 1) contrastStretch(work);
  const binarizer = Math.floor(n / 2) % 2 === 0 ? 'LocalAverage' : 'GlobalHistogram';
  return decodeCanvas(work.canvas, work.ctx, binarizer);
}

async function setTorch(on) {
  const track = live.track;
  if (!track) return false;
  try {
    await track.applyConstraints({ advanced: [{ torch: !!on }] });
    return true;
  } catch (e) {
    log('torch failed', e);
    return false;
  }
}

function torchSupported() {
  const track = live.track;
  if (!track || !track.getCapabilities) return false;
  return !!track.getCapabilities().torch;
}

// ---------------------------------------------------------------------------
// Take photo (phone's native camera app)

async function loadBitmap(file) {
  try {
    return await createImageBitmap(file, { imageOrientation: 'from-image' });
  } catch (_) {
    return createImageBitmap(file);
  }
}

async function decodeImageFile(file) {
  const started = performance.now();
  const bmp = await loadBitmap(file);
  const W = bmp.width;
  const H = bmp.height;
  const work = makeCanvas();
  const fit = Math.min(1, PHOTO_MAX_SIDE / Math.max(W, H));

  // Horizontal bands at full resolution (barcodes are usually held level), then the whole photo.
  const band = (cy, frac) => {
    const h = Math.round(H * frac);
    const top = Math.min(Math.max(0, Math.round(H * cy - h / 2)), H - h);
    return [0, top, W, h];
  };
  const regions = [
    [0, 0, W, H],
    band(0.5, 0.4),
    band(0.25, 0.4),
    band(0.75, 0.4),
  ];

  const attempts = [];
  for (const r of regions) {
    attempts.push({ r, stretch: false, binarizer: 'LocalAverage' });
    attempts.push({ r, stretch: true, binarizer: 'LocalAverage' });
  }
  attempts.push({ r: regions[0], stretch: false, binarizer: 'GlobalHistogram' });
  attempts.push({ r: regions[1], stretch: true, binarizer: 'GlobalHistogram' });

  try {
    for (const a of attempts) {
      const [sx, sy, sw, sh] = a.r;
      const scale = Math.min(1, PHOTO_MAX_SIDE / Math.max(sw, sh), sw === W && sh === H ? fit : 1);
      drawRegion(work, bmp, sx, sy, sw, sh, scale);
      if (a.stretch) contrastStretch(work);
      const codes = await decodeCanvas(work.canvas, work.ctx, a.binarizer);
      if (codes.length) {
        log('photo decoded', codes, Math.round(performance.now() - started) + 'ms', a);
        return codes;
      }
    }
  } finally {
    if (bmp.close) bmp.close();
  }
  log('photo: no barcode', Math.round(performance.now() - started) + 'ms');
  return [];
}

/**
 * Opens the phone's camera app and decodes the photo.
 * Must be called directly from a tap. Stops the live camera first so the camera app can use it.
 * Resolves with raw values ([] when nothing was found) or null when the user cancelled.
 */
function decodePhoto() {
  stopLive();
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.setAttribute('capture', 'environment');
    input.style.display = 'none';
    document.body.appendChild(input);

    let settled = false;
    const done = (value) => {
      if (settled) return;
      settled = true;
      input.remove();
      resolve(value);
    };

    input.addEventListener('change', async () => {
      const file = input.files && input.files[0];
      if (!file) return done(null);
      try {
        done(await decodeImageFile(file));
      } catch (e) {
        log('photo decode failed', e);
        done([]);
      }
    });
    input.addEventListener('cancel', () => done(null));
    input.click();
  });
}

// ---------------------------------------------------------------------------

window.tsScanner = {
  startLive,
  stop: stopLive,
  torchSupported,
  setTorch,
  decodePhoto,
};
log('ready');
