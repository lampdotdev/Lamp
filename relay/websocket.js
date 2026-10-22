// A WebSocket server side small enough to read whole (RFC 6455): text messages, pings and closes, with every
// message size-capped, so the relay needs nothing installed. Messages the relay carries are a few hundred bytes.

import { createHash } from 'node:crypto';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

export class Socket {
  constructor(stream, { maxMessage }) {
    this.stream = stream;
    this.maxMessage = maxMessage;
    this.buffer = Buffer.alloc(0);
    this.parts = [];
    this.open = true;
    this.handlers = { message: () => {}, close: () => {} };
    stream.setNoDelay(true);
    stream.on('data', (chunk) => this.receive(chunk));
    stream.on('close', () => this.closed());
    stream.on('error', () => this.closed());
  }

  on(event, handler) { this.handlers[event] = handler; }

  // What's waiting to go out to this socket, for the relay to drop stale movement rather than queue it.
  get backlog() { return this.stream.writableLength; }

  send(text) {
    if (this.open) this.stream.write(frame(0x1, Buffer.from(text, 'utf8')));
  }

  close(code = 1000) {
    if (!this.open) return;
    const payload = Buffer.alloc(2);
    payload.writeUInt16BE(code);
    this.stream.write(frame(0x8, payload));
    this.stream.end();
    this.closed();
  }

  closed() {
    if (!this.open) return;
    this.open = false;
    this.stream.destroy();
    this.handlers.close();
  }

  receive(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.open) {
      const read = parse(this.buffer, this.maxMessage);
      if (read === null) return;
      if (read === false) return this.close(1009);
      this.buffer = this.buffer.subarray(read.length);
      this.handle(read);
    }
  }

  handle({ fin, opcode, payload }) {
    if (opcode === 0x8) return this.close();
    if (opcode === 0x9) return this.stream.write(frame(0xA, payload));
    if (opcode === 0xA) return;
    if (opcode !== 0x0 && opcode !== 0x1) return this.close(1003);   // binary isn't spoken here
    this.parts.push(payload);
    const size = this.parts.reduce((sum, part) => sum + part.length, 0);
    if (size > this.maxMessage) return this.close(1009);
    if (!fin) return;
    const text = Buffer.concat(this.parts).toString('utf8');
    this.parts = [];
    this.handlers.message(text);
  }
}

// Answers an upgrade request, or refuses it; gives back the socket when it was taken.
export function accept(request, stream, options) {
  const key = request.headers['sec-websocket-key'];
  if (request.headers.upgrade?.toLowerCase() !== 'websocket' || !key) {
    stream.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
    return null;
  }
  const answer = createHash('sha1').update(key + GUID).digest('base64');
  stream.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${answer}\r\n\r\n`);
  return new Socket(stream, options);
}

function frame(opcode, payload) {
  const length = payload.length;
  const head = length < 126 ? Buffer.from([0x80 | opcode, length])
    : length < 65536 ? Buffer.from([0x80 | opcode, 126, length >> 8, length & 0xff])
    : (() => { const h = Buffer.alloc(10); h[0] = 0x80 | opcode; h[1] = 127; h.writeBigUInt64BE(BigInt(length), 2); return h; })();
  return Buffer.concat([head, payload]);
}

// One frame off the front of the buffer: null while it hasn't all come, false when it's too big or unmasked.
function parse(buffer, maxMessage) {
  if (buffer.length < 2) return null;
  const fin = (buffer[0] & 0x80) !== 0;
  const opcode = buffer[0] & 0x0f;
  const masked = (buffer[1] & 0x80) !== 0;
  let length = buffer[1] & 0x7f;
  let offset = 2;
  if (!masked) return false;   // a client's frames are always masked
  if (length === 126) {
    if (buffer.length < 4) return null;
    length = buffer.readUInt16BE(2);
    offset = 4;
  } else if (length === 127) {
    if (buffer.length < 10) return null;
    const big = buffer.readBigUInt64BE(2);
    if (big > BigInt(maxMessage)) return false;
    length = Number(big);
    offset = 10;
  }
  if (length > maxMessage) return false;
  if (buffer.length < offset + 4 + length) return null;
  const mask = buffer.subarray(offset, offset + 4);
  const payload = Buffer.from(buffer.subarray(offset + 4, offset + 4 + length));
  for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
  return { fin, opcode, payload, length: offset + 4 + length };
}
