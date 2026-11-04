// recolor.js - recolor Claude's icon (JavaScript for Automation, built into macOS).
//   osascript -l JavaScript recolor.js <src.png> <dst.png> <RRGGBB>
// Every colored pixel takes the target hue; saturation and brightness are scaled so the logo's own
// brand color lands exactly on the target, while near-white pixels (the glyph) stay light. Same
// algorithm as src/windows/MultiClaude.cs and src/linux/recolor.py.
ObjC.import('AppKit');

const BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function toHsv(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), d = max - Math.min(r, g, b);
  let h = 0;
  if (d) h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [(h * 60 + 360) % 360, max ? d / max : 0, max];
}

function fromHsv(h, s, v) {
  const c = v * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = v - c;
  const rgb = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][Math.floor(h / 60) % 6];
  return rgb.map(channel => Math.round((channel + m) * 255));
}

function decode(text) {
  const values = new Uint8Array(128);
  for (let i = 0; i < 64; i++) values[BASE64.charCodeAt(i)] = i;
  const size = text.length / 4 * 3 - (text.endsWith('==') ? 2 : text.endsWith('=') ? 1 : 0);
  const bytes = new Uint8Array(size + 2);
  for (let i = 0, o = 0; i < text.length; i += 4) {
    const n = values[text.charCodeAt(i)] << 18 | values[text.charCodeAt(i + 1)] << 12 |
              values[text.charCodeAt(i + 2)] << 6 | values[text.charCodeAt(i + 3)];
    bytes[o++] = n >> 16 & 255; bytes[o++] = n >> 8 & 255; bytes[o++] = n & 255;
  }
  return bytes.subarray(0, size);
}

function encode(bytes) {
  const parts = [];
  for (let start = 0; start < bytes.length; start += 49152) {
    const end = Math.min(start + 49152, bytes.length);
    let text = '';
    for (let i = start; i < end; i += 3) {
      const a = bytes[i], b = i + 1 < end ? bytes[i + 1] : 0, c = i + 2 < end ? bytes[i + 2] : 0;
      text += BASE64[a >> 2] + BASE64[(a & 3) << 4 | b >> 4] +
              (i + 1 < end ? BASE64[(b & 15) << 2 | c >> 6] : '=') + (i + 2 < end ? BASE64[c & 63] : '=');
    }
    parts.push(text);
  }
  return parts.join('');
}

// An uncompressed TIFF is the one way to reach the pixels here: `bitmapData` crashes osascript.
function pixelLayout(tiff) {
  const big = tiff[0] === 0x4d;
  const u16 = i => big ? tiff[i] << 8 | tiff[i + 1] : tiff[i + 1] << 8 | tiff[i];
  const u32 = i => big ? u16(i) * 65536 + u16(i + 2) : u16(i + 2) * 65536 + u16(i);
  const tags = {}, ifd = u32(4);
  for (let k = 0; k < u16(ifd); k++) {
    const entry = ifd + 2 + k * 12, short = u16(entry + 2) === 3, count = u32(entry + 4);
    tags[u16(entry)] = { short, count, value: short && count === 1 ? u16(entry + 8) : u32(entry + 8) };
  }
  const list = tag => {
    const { short, count, value } = tags[tag];
    if (count === 1) return [value];
    return Array.from({ length: count }, (_, k) => short ? u16(value + k * 2) : u32(value + k * 4));
  };
  const channels = tags[277].value, offsets = list(273), sizes = list(279);
  const contiguous = offsets.every((offset, k) => !k || offset === offsets[k - 1] + sizes[k - 1]);
  if (tags[259].value !== 1 || list(258)[0] !== 8 || channels < 3 || !contiguous) throw new Error('Unexpected image format.');
  return { width: tags[256].value, height: tags[257].value, channels, start: offsets[0],
           premultiplied: tags[338] !== undefined && tags[338].value === 1 };
}

// Mean saturation and brightness of the clearly colored, opaque pixels.
function brandColor(tiff, { width, height, channels, start }) {
  let sumS = 0, sumV = 0, count = 0;
  for (let y = 0; y < height; y += 2) {
    for (let x = 0; x < width; x += 2) {
      const i = start + (y * width + x) * channels;
      if (channels > 3 && tiff[i + 3] < 200) continue;
      const [, s, v] = toHsv(tiff[i], tiff[i + 1], tiff[i + 2]);
      if (s >= 0.3) { sumS += s; sumV += v; count++; }
    }
  }
  return count ? [sumS / count, sumV / count] : [0.6, 0.85];
}

function run(argv) {
  const [src, dst, hex] = argv;
  const value = parseInt(hex, 16);
  const [hue, sat, val] = toHsv(value >> 16 & 255, value >> 8 & 255, value & 255);

  const source = $.NSBitmapImageRep.imageRepWithData($.NSData.dataWithContentsOfFile(src));
  const tiff = decode(source.TIFFRepresentation.base64EncodedStringWithOptions(0).js);
  const layout = pixelLayout(tiff);
  const { width, height, channels, start, premultiplied } = layout;
  const [brandS, brandV] = brandColor(tiff, layout);

  for (let i = start, end = start + width * height * channels; i < end; i += channels) {
    const alpha = channels > 3 ? tiff[i + 3] : 255;
    if (!alpha) continue;
    const scale = premultiplied ? 255 / alpha : 1;
    const [, s, v] = toHsv(Math.min(255, tiff[i] * scale), Math.min(255, tiff[i + 1] * scale), Math.min(255, tiff[i + 2] * scale));
    const colored = Math.min(1, s / brandS);
    const rgb = fromHsv(hue, Math.min(1, s * sat / brandS), Math.min(1, v * (1 - colored + colored * val / brandV)));
    for (let c = 0; c < 3; c++) tiff[i + c] = Math.round(rgb[c] / scale);
  }

  const data = $.NSData.alloc.initWithBase64EncodedStringOptions($(encode(tiff)), 0);
  const png = 4; // NSBitmapImageFileTypePNG
  $.NSBitmapImageRep.imageRepWithData(data).representationUsingTypeProperties(png, $({})).writeToFileAtomically(dst, true);
}
