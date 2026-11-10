// Just enough PNG for the pictures lamp makes itself: an app's icon on the tile a device shows it on, at the sizes the
// device's package names (`DeviceSupport.iconPNG` in Lamp's app, which draws the same tile with AppKit).

import { deflateSync, inflateSync } from "node:zlib";

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const CRC = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8), sum = Buffer.alloc(4);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, "latin1");
  sum.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, sum]);
}

/** A PNG of these pixels (four bytes each: red, green, blue, alpha). */
export function encode(width, height, rgba) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;                                 // eight bits a channel
  header[9] = 6;                                 // color with alpha
  const rows = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) rgba.copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  return Buffer.concat([SIGNATURE, chunk("IHDR", header), chunk("IDAT", deflateSync(rows)), chunk("IEND", Buffer.alloc(0))]);
}

/**
 * A PNG's pixels (four bytes each), or null for one this doesn't read: only what an icon is saved as, eight bits a
 * channel and not interlaced.
 */
export function decode(bytes) {
  try {
    if (bytes.length < 33 || !bytes.subarray(0, 8).equals(SIGNATURE)) return null;
    let width = 0, height = 0, kind = 0, palette = null, clear = null;
    const packed = [];
    for (let at = 8; at + 12 <= bytes.length;) {
      const length = bytes.readUInt32BE(at), type = bytes.toString("latin1", at + 4, at + 8), data = bytes.subarray(at + 8, at + 8 + length);
      if (type === "IHDR") {
        width = data.readUInt32BE(0); height = data.readUInt32BE(4); kind = data[9];
        if (data[8] !== 8 || data[12] !== 0 || ![0, 2, 3, 4, 6].includes(kind)) return null;
      } else if (type === "PLTE") palette = data;
      else if (type === "tRNS") clear = data;
      else if (type === "IDAT") packed.push(data);
      else if (type === "IEND") break;
      at += 12 + length;
    }
    if (!width || !height || width > 8192 || height > 8192) return null;
    const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[kind], stride = width * channels;
    const raw = inflateSync(Buffer.concat(packed));
    if (raw.length < (stride + 1) * height) return null;
    const lines = Buffer.alloc(stride * height);
    for (let y = 0; y < height; y++) {
      const filter = raw[y * (stride + 1)], from = y * (stride + 1) + 1, to = y * stride;
      for (let x = 0; x < stride; x++) {
        const left = x >= channels ? lines[to + x - channels] : 0, up = y ? lines[to + x - stride] : 0;
        const corner = x >= channels && y ? lines[to + x - stride - channels] : 0;
        let guess = 0;
        if (filter === 1) guess = left;
        else if (filter === 2) guess = up;
        else if (filter === 3) guess = (left + up) >> 1;
        else if (filter === 4) {
          const p = left + up - corner, a = Math.abs(p - left), b = Math.abs(p - up), c = Math.abs(p - corner);
          guess = a <= b && a <= c ? left : b <= c ? up : corner;
        }
        lines[to + x] = (raw[from + x] + guess) & 0xff;
      }
    }
    const rgba = Buffer.alloc(width * height * 4);
    for (let i = 0; i < width * height; i++) {
      const at = i * channels;
      let r, g, b, a = 255;
      if (kind === 0) r = g = b = lines[at];
      else if (kind === 4) { r = g = b = lines[at]; a = lines[at + 1]; }
      else if (kind === 2) { r = lines[at]; g = lines[at + 1]; b = lines[at + 2]; }
      else if (kind === 6) { r = lines[at]; g = lines[at + 1]; b = lines[at + 2]; a = lines[at + 3]; }
      else {
        if (!palette) return null;
        const index = lines[at];
        r = palette[index * 3]; g = palette[index * 3 + 1]; b = palette[index * 3 + 2];
        a = clear && index < clear.length ? clear[index] : 255;
      }
      rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b; rgba[i * 4 + 3] = a;
    }
    return { width, height, rgba };
  } catch { return null; }
}

/** A PNG's size in pixels, read from its header; null when it isn't one. */
export function sizeOf(bytes) {
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(SIGNATURE)) return null;
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

/**
 * The app's icon as a square of that many pixels, clear where the icon is: what a phone's home screen shows. Null for
 * no icon, or one this can't read.
 */
export function scaled(icon, side) {
  const picture = icon && decode(icon);
  if (!picture) return null;
  const out = Buffer.alloc(side * side * 4), across = picture.width / side, down = picture.height / side;
  for (let y = 0; y < side; y++) {
    for (let x = 0; x < side; x++) {
      const x0 = Math.floor(x * across), x1 = Math.max(x0 + 1, Math.min(picture.width, Math.ceil((x + 1) * across)));
      const y0 = Math.floor(y * down), y1 = Math.max(y0 + 1, Math.min(picture.height, Math.ceil((y + 1) * down)));
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = y0; sy < y1; sy++) {
        for (let sx = x0; sx < x1; sx++) {
          const at = (Math.min(sy, picture.height - 1) * picture.width + Math.min(sx, picture.width - 1)) * 4, alpha = picture.rgba[at + 3];
          r += picture.rgba[at] * alpha; g += picture.rgba[at + 1] * alpha; b += picture.rgba[at + 2] * alpha; a += alpha;
        }
      }
      if (!a) continue;
      const at = (y * side + x) * 4;
      out[at] = Math.round(r / a); out[at + 1] = Math.round(g / a); out[at + 2] = Math.round(b / a);
      out[at + 3] = Math.round(a / ((x1 - x0) * (y1 - y0)));
    }
  }
  return encode(side, side, out);
}

// The tile's color: Lamp's dark blue, the same one the package's manifest names for the tile behind it.
const TILE = [27, 27, 58];

/**
 * The app's icon centered on its tile's color at a logo's size, or the color alone when the app has no icon (or one
 * this can't read): a device's package names these files, and shows nothing in their place without them.
 */
export function tile(icon, width, height) {
  const out = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) { out[i * 4] = TILE[0]; out[i * 4 + 1] = TILE[1]; out[i * 4 + 2] = TILE[2]; out[i * 4 + 3] = 255; }
  const picture = icon && decode(icon);
  if (picture) {
    const side = Math.round(Math.min(width, height) * 0.8), left = Math.round((width - side) / 2), top = Math.round((height - side) / 2);
    const across = picture.width / side, down = picture.height / side;
    for (let y = 0; y < side; y++) {
      for (let x = 0; x < side; x++) {
        // Each pixel is the average of the part of the icon it covers, so a large icon made small stays smooth.
        const x0 = Math.floor(x * across), x1 = Math.max(x0 + 1, Math.min(picture.width, Math.ceil((x + 1) * across)));
        const y0 = Math.floor(y * down), y1 = Math.max(y0 + 1, Math.min(picture.height, Math.ceil((y + 1) * down)));
        let r = 0, g = 0, b = 0, a = 0;
        for (let sy = y0; sy < y1; sy++) {
          for (let sx = x0; sx < x1; sx++) {
            const at = (Math.min(sy, picture.height - 1) * picture.width + Math.min(sx, picture.width - 1)) * 4, alpha = picture.rgba[at + 3];
            r += picture.rgba[at] * alpha; g += picture.rgba[at + 1] * alpha; b += picture.rgba[at + 2] * alpha; a += alpha;
          }
        }
        if (!a) continue;
        const cover = a / ((x1 - x0) * (y1 - y0)) / 255, at = ((top + y) * width + left + x) * 4;
        out[at] = Math.round((r / a) * cover + TILE[0] * (1 - cover));
        out[at + 1] = Math.round((g / a) * cover + TILE[1] * (1 - cover));
        out[at + 2] = Math.round((b / a) * cover + TILE[2] * (1 - cover));
      }
    }
  }
  return encode(width, height, out);
}
