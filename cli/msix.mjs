// Windows app packages (MSIX), made and signed by lamp itself: an Xbox in Developer Mode takes them through its Device
// Portal. This is Sources/Lamp/MSIX.swift in Node, and makes the same package from the same files (a test holds the
// two together, cli/tests/fixtures/msix): the manifest lamp writes, so the package's identity and publisher are Lamp's,
// the block map and content types, the files laid out as Zip64 (Windows opens nothing else), and an Authenticode
// signature with a key and a certificate of lamp's own, which Developer Mode accepts once the certificate is installed
// beside the package.

import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, sign as signWith } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { deflateRawSync } from "node:zlib";
import { Problem } from "./state.mjs";

/** Lamp's publisher name; a package's manifest must name exactly its certificate's subject. */
export const PUBLISHER = "CN=Lamp";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest();

/** Windows' short id for a publisher: the first 8 bytes of SHA-256 of its name in UTF-16LE, in Crockford's base 32. */
export function publisherID(publisher) {
  const bits = sha256(Buffer.from(publisher, "utf16le")).readBigUInt64BE(0), alphabet = "0123456789abcdefghjkmnpqrstvwxyz";
  let id = "";
  // 64 bits as 13 digits of 5 bits: the last digit takes the lowest 4 bits shifted up one.
  for (let index = 0; index < 13; index++) {
    const shift = 64n - 5n * BigInt(index + 1);
    id += alphabet[Number((shift >= 0n ? bits >> shift : bits << -shift) & 31n)];
  }
  return id;
}

/** An identity name for an app: Windows takes letters, digits, dots and dashes, 3 to 50 of them. */
export function identityName(slug) {
  const plain = [...slug].filter((c) => /[A-Za-z0-9-]/.test(c)).join("");
  return "Lamp." + (plain || "app").slice(0, 40);
}

/**
 * A version newer than `previous`, so each build replaces the last (Windows refuses a changed package under a version
 * it has): minutes since 2026 in two of the four parts, or the previous one's next revision when two builds fall in
 * the same minute.
 */
export function versionAfter(previous, date = new Date()) {
  const minutes = Math.max(0, Math.floor((date.getTime() / 1000 - 1_767_225_600) / 60));
  const byTime = [1, minutes >> 16, minutes & 0xffff, 0];
  const next = String(previous ?? "").split(".").map(Number);
  const earlier = () => { for (let i = 0; i < 4; i++) if (next[i] !== byTime[i]) return next[i] < byTime[i]; return false; };
  if (next.length !== 4 || next.some((n) => !Number.isInteger(n)) || earlier()) return byTime.join(".");
  for (let index = 3; index >= 0; index--) {
    if (next[index] < 0xffff) { next[index] += 1; break; }
    next[index] = 0;
  }
  return next.join(".");
}

/** The names Windows gives a package with this identity ({ name, publisher, version, architecture }): what it's opened and removed by. */
export function namesOf(identity) {
  const family = `${identity.name}_${publisherID(identity.publisher)}`;
  return {
    fullName: `${identity.name}_${identity.version}_${identity.architecture ?? "neutral"}__${publisherID(identity.publisher)}`,
    familyName: family,
    appUserModelID: `${family}!App`,
  };
}

// MARK: Making a package

// Lamp's web host for the Xbox (Resources/WebHost): the program a web app's package starts, and WebView2's own
// library beside it, whose classes the package registers so Windows finds them (`WebHost` in Lamp's app).
export const WEB_HOST = {
  program: "App.exe",
  library: "Microsoft.Web.WebView2.Core.dll",
  folder: "Web",
  classes: [
    "Microsoft.Web.WebView2.Core.CoreWebView2Environment",
    "Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions",
    "Microsoft.Web.WebView2.Core.CoreWebView2ControllerWindowReference",
    "Microsoft.Web.WebView2.Core.CoreWebView2CustomSchemeRegistration",
  ],
};

const RESERVED = new Set(["appxmanifest.xml", "appxblockmap.xml", "[content_types].xml", "appxsignature.p7x"]);
export const LOGOS = [["StoreLogo", 50, 50], ["Square150x150Logo", 150, 150], ["Square44x44Logo", 44, 44], ["Wide310x150Logo", 310, 150], ["SplashScreen", 620, 300]];

const escaped = (text) => text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");

/**
 * The manifest of a package whose app starts at `entry`: `{ page }` for a web app in the system's own host,
 * `{ program }` for a native one, or "webHost" for a web app in Lamp's host.
 */
export function manifest(identity, displayName, entry) {
  const name = escaped([...displayName].slice(0, 80).join(""));
  let application, minimum, capabilities;
  const network = '<Capabilities><Capability Name="internetClient"/><Capability Name="privateNetworkClientServer"/></Capabilities>';
  if (entry === "webHost") {
    // WebView2's classes come from the copy of its library in the package, which Windows finds only by these
    // registrations; the browser itself is the console's.
    application = `Executable="${WEB_HOST.program}" EntryPoint="App.App"`;
    minimum = "10.0.19041.0";
    const classes = WEB_HOST.classes.map((id) => `<ActivatableClass ActivatableClassId="${id}" ThreadingModel="both"/>`).join("");
    capabilities = network + `<Extensions><Extension Category="windows.activatableClass.inProcessServer"><InProcessServer><Path>${WEB_HOST.library}</Path>${classes}</InProcessServer></Extension></Extensions>`;
  } else if (entry.page) {
    application = `StartPage="${escaped(entry.page)}"`;
    minimum = "10.0.10240.0";
    capabilities = network;
  } else {
    application = `Executable="${escaped(entry.program.replaceAll("/", "\\"))}" EntryPoint="App.App"`;
    minimum = "10.0.17763.0";
    capabilities = "";
  }
  return `<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" IgnorableNamespaces="uap">
  <Identity Name="${identity.name}" Publisher="${escaped(identity.publisher)}" Version="${identity.version}" ProcessorArchitecture="${identity.architecture ?? "neutral"}"/>
  <Properties><DisplayName>${name}</DisplayName><PublisherDisplayName>Lamp</PublisherDisplayName><Logo>LampLogos\\StoreLogo.png</Logo></Properties>
  <Dependencies><TargetDeviceFamily Name="Windows.Universal" MinVersion="${minimum}" MaxVersionTested="10.0.22621.0"/></Dependencies>
  <Resources><Resource Language="en-us"/></Resources>
  <Applications>
    <Application Id="App" ${application}>
      <uap:VisualElements DisplayName="${name}" Description="${name}" BackgroundColor="#1b1b3a" Square150x150Logo="LampLogos\\Square150x150Logo.png" Square44x44Logo="LampLogos\\Square44x44Logo.png">
        <uap:DefaultTile Wide310x150Logo="LampLogos\\Wide310x150Logo.png"/>
        <uap:SplashScreen Image="LampLogos\\SplashScreen.png"/>
      </uap:VisualElements>
    </Application>
  </Applications>
  ${capabilities}
</Package>
`;
}

/**
 * A signed package of the app's files (`[path, bytes]`), started at `entry`, with `logo(width, height)` drawing each
 * of the pictures Windows shows it by.
 */
export function packageOf({ payload, displayName, identity, entry, logo, signer }) {
  const start = entry === "webHost" ? WEB_HOST.program : entry.page ?? entry.program;
  if (!payload.some(([path]) => path === start)) throw new Problem(`the package has no ${start} for the app to start at`);
  const files = payload.filter(([path]) => !RESERVED.has(path.toLowerCase()) && !path.toLowerCase().startsWith("lamplogos/"));
  for (const [name, width, height] of LOGOS) files.push([`LampLogos/${name}.png`, logo(width, height)]);
  files.push(["AppxManifest.xml", Buffer.from(manifest(identity, displayName, entry))]);
  return assemble(files, signer);
}

// MARK: The container

const CRC = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** Little-endian fields appended one after another. */
class Writer {
  parts = [];
  length = 0;
  put(bytes) { this.parts.push(bytes); this.length += bytes.length; return this; }
  u16(...values) { for (const v of values) { const b = Buffer.alloc(2); b.writeUInt16LE(v & 0xffff); this.put(b); } return this; }
  u32(...values) { for (const v of values) { const b = Buffer.alloc(4); b.writeUInt32LE(v >>> 0); this.put(b); } return this; }
  u64(...values) { for (const v of values) { const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(v)); this.put(b); } return this; }
  get data() { return Buffer.concat(this.parts); }
}

/** Local records and the central directory (with its Zip64 end records), each Zip64 throughout. */
function layout(entries) {
  const records = new Writer(), central = new Writer();
  for (const [path, data] of entries) {
    const name = Buffer.from(path, "utf8"), crc = crc32(data), offset = records.length, size = data.length;
    // The signature is the one plain, deflated record, as Windows' own packager writes it: it opens nothing else.
    if (path === "AppxSignature.p7x") {
      const deflated = deflateRawSync(data);
      records.u32(0x04034b50).u16(20, 0, 8, 0, 0x21).u32(crc, deflated.length, size).u16(name.length, 0).put(name).put(deflated);
      central.u32(0x02014b50).u16(45, 20, 0, 8, 0, 0x21).u32(crc, deflated.length, size).u16(name.length, 0, 0, 0, 0).u32(0, offset).put(name);
      continue;
    }
    // Local header: Zip64, stored, sizes in the extra field.
    records.u32(0x04034b50).u16(45, 0, 0, 0, 0x21).u32(crc, 0xffffffff, 0xffffffff).u16(name.length, 20).put(name);
    records.u16(1, 16).u64(size, size).put(data);
    // Its central entry, with the offset in the extra field too.
    central.u32(0x02014b50).u16(45, 45, 0, 0, 0, 0x21).u32(crc, 0xffffffff, 0xffffffff).u16(name.length, 28, 0, 0, 0).u32(0, 0xffffffff).put(name);
    central.u16(1, 24).u64(size, size, offset);
  }
  const end = new Writer();
  end.u32(0x06064b50).u64(44).u16(45, 45).u32(0, 0).u64(entries.length, entries.length, central.length, records.length);
  end.u32(0x07064b50, 0).u64(records.length + central.length).u32(1);
  // The disk numbers are written as zeros: the signature is checked over them as zeros.
  end.u32(0x06054b50).u16(0, 0, 0xffff, 0xffff).u32(0xffffffff, 0xffffffff).u16(0);
  return { records: records.data, directory: Buffer.concat([central.data, end.data]) };
}

const lfhSize = (name) => 30 + Buffer.byteLength(name, "utf8") + 20;

function blockMap(entries) {
  const files = entries.map(([path, data]) => {
    let blocks = "";
    for (let start = 0; start < data.length; start += 65536) blocks += `<Block Hash="${sha256(data.subarray(start, start + 65536)).toString("base64")}"/>`;
    return `<File Name="${path.replaceAll("/", "\\").replaceAll("&", "&amp;")}" Size="${data.length}" LfhSize="${lfhSize(path)}">${blocks}</File>`;
  }).join("");
  return Buffer.from('<?xml version="1.0" encoding="UTF-8"?><BlockMap xmlns="http://schemas.microsoft.com/appx/2010/blockmap" '
    + 'HashMethod="http://www.w3.org/2001/04/xmlenc#sha256">' + files + "</BlockMap>");
}

const KNOWN_TYPES = {
  exe: "application/x-msdownload", dll: "application/x-msdownload", png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
  svg: "image/svg+xml", html: "text/html", htm: "text/html", js: "application/javascript", css: "text/css", json: "application/json",
  txt: "text/plain", woff: "font/woff", woff2: "font/woff2", mp3: "audio/mpeg", mp4: "video/mp4", wav: "audio/wav",
};

// A part's name as its content type names it: what a path may hold as it is, the rest by its bytes.
const partName = (path) => [...Buffer.from(path, "utf8")]
  .map((byte) => (/[A-Za-z0-9!$&'()*+,\-./:=@_~]/.test(String.fromCharCode(byte)) && byte < 128 ? String.fromCharCode(byte) : "%" + byte.toString(16).toUpperCase().padStart(2, "0")))
  .join("");

/**
 * Every part needs a content type: by its extension, or, for a file with none Windows can take (a LICENSE), one of
 * its own. Windows refuses a package with an untyped part, saying its block map is invalid.
 */
export function contentTypes(paths) {
  const extensions = new Set(), untyped = [];
  for (const path of paths) {
    if (path === "AppxManifest.xml") continue;
    const parts = path.split("/").filter(Boolean).pop()?.split(".") ?? [""], last = parts[parts.length - 1];
    if (parts.length > 1 && last && /^[A-Za-z0-9]+$/.test(last)) extensions.add(last.toLowerCase());
    else untyped.push(path);
  }
  const defaults = [...extensions].sort().map((ext) => `<Default Extension="${ext}" ContentType="${KNOWN_TYPES[ext] ?? "application/octet-stream"}"/>`).join("");
  const overrides = untyped.sort().map((path) => `<Override PartName="/${partName(path).replaceAll("&", "&amp;")}" ContentType="application/octet-stream"/>`).join("");
  return Buffer.from('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    + defaults + overrides
    + '<Override PartName="/AppxManifest.xml" ContentType="application/vnd.ms-appx.manifest+xml"/>'
    + '<Override PartName="/AppxBlockMap.xml" ContentType="application/vnd.ms-appx.blockmap+xml"/>'
    + '<Override PartName="/AppxSignature.p7x" ContentType="application/vnd.ms-appx.signature"/></Types>');
}

/**
 * The files laid out as an MSIX: each stored (so the block map's hashes are of what's in the zip), the block map and
 * content types after them, then the signature, then a Zip64 central directory.
 */
export function assemble(files, signer) {
  const entries = files.map(([path, data]) => [path, data]);
  entries.push(["AppxBlockMap.xml", blockMap(entries)]);
  entries.push(["[Content_Types].xml", contentTypes(files.map(([path]) => path))]);
  // What's signed is the package without its signature: its records, its directory and the two files' contents.
  const unsigned = layout(entries);
  const blob = Buffer.concat([
    Buffer.from("APPX"),
    Buffer.from("AXPC"), sha256(unsigned.records),
    Buffer.from("AXCD"), sha256(unsigned.directory),
    Buffer.from("AXCT"), sha256(entries[entries.length - 1][1]),
    Buffer.from("AXBM"), sha256(entries[entries.length - 2][1]),
  ]);
  entries.push(["AppxSignature.p7x", Buffer.concat([Buffer.from("PKCX"), sign(signer, blob)])]);
  const signed = layout(entries);
  return Buffer.concat([signed.records, signed.directory]);
}

// MARK: Signing

const der = {
  tlv(tag, content) {
    const n = content.length, head = [tag];
    if (n < 0x80) head.push(n);
    else {
      const bytes = [];
      for (let v = n; v > 0; v = Math.floor(v / 256)) bytes.unshift(v & 0xff);
      head.push(0x80 | bytes.length, ...bytes);
    }
    return Buffer.concat([Buffer.from(head), content]);
  },
  sequence: (parts) => der.tlv(0x30, Buffer.concat(parts)),
  set: (parts) => der.tlv(0x31, Buffer.concat(parts)),
  null: Buffer.from([0x05, 0x00]),
  integer(value) {
    const bytes = [];
    let v = value;
    do { bytes.unshift(v & 0xff); v = Math.floor(v / 256); } while (v > 0);
    if (bytes[0] & 0x80) bytes.unshift(0);
    return der.tlv(0x02, Buffer.from(bytes));
  },
  /** A dotted object identifier. */
  oid(dotted) {
    const parts = dotted.split(".").map(Number), bytes = [parts[0] * 40 + parts[1]];
    for (const part of parts.slice(2)) {
      const chunk = [part & 0x7f];
      for (let v = Math.floor(part / 128); v > 0; v = Math.floor(v / 128)) chunk.unshift((v & 0x7f) | 0x80);
      bytes.push(...chunk);
    }
    return der.tlv(0x06, Buffer.from(bytes));
  },
  /** An element's contents without its tag and length. */
  contents(element) {
    if (element.length < 2) return Buffer.alloc(0);
    return element.subarray(Math.min(element[1] & 0x80 ? 2 + (element[1] & 0x7f) : 2, element.length));
  },
  /** The elements inside one. */
  children(element) {
    const header = (at) => (at + 1 < element.length ? (element[at + 1] & 0x80 ? 2 + (element[at + 1] & 0x7f) : 2) : 0);
    const length = (at) => {
      const first = element[at + 1];
      if (!(first & 0x80)) return first;
      let n = 0;
      for (let i = 0; i < (first & 0x7f); i++) n = n * 256 + (element[at + 2 + i] ?? 0);
      return n;
    };
    const out = [];
    for (let at = header(0); at < element.length;) {
      const head = header(at), size = length(at);
      if (!head || at + head + size > element.length) break;
      out.push(element.subarray(at, at + head + size));
      at += head + size;
    }
    return out;
  },
};

const OID = {
  rsa: "1.2.840.113549.1.1.1", sha256WithRSA: "1.2.840.113549.1.1.11", sha256: "2.16.840.1.101.3.4.2.1", commonName: "2.5.4.3",
  signedData: "1.2.840.113549.1.7.2", contentType: "1.2.840.113549.1.9.3", messageDigest: "1.2.840.113549.1.9.4",
  indirectData: "1.3.6.1.4.1.311.2.1.4", sipInfo: "1.3.6.1.4.1.311.2.1.30", statementType: "1.3.6.1.4.1.311.2.1.11",
  individualCodeSigning: "1.3.6.1.4.1.311.2.1.21", opusInfo: "1.3.6.1.4.1.311.2.1.12",
};

// The APPX signature's SIP GUID, as Windows lays it out in an SpcSipInfo.
const APPX_SIP = Buffer.from([0x4b, 0xdf, 0xc5, 0x0a, 0x07, 0xce, 0xe2, 0x4d, 0xb7, 0x6e, 0x23, 0xc8, 0x39, 0xa0, 0x9f, 0xd1]);

/**
 * Signs the APPX digest blob as Authenticode does: the blob is the "digest" in an SpcIndirectDataContent, whose own
 * SHA-256 (of its contents, without its outer header) is the signed message digest.
 */
function sign(signer, blob) {
  const zero = der.integer(0);
  const sipInfo = der.sequence([der.integer(0x01010000), der.tlv(0x04, APPX_SIP), zero, zero, zero, zero, zero]);
  const digestAlgorithm = der.sequence([der.oid(OID.sha256), der.null]);
  const indirect = der.sequence([
    der.sequence([der.oid(OID.sipInfo), sipInfo]),
    der.sequence([digestAlgorithm, der.tlv(0x04, blob)]),
  ]);
  const attributes = [
    der.sequence([der.oid(OID.contentType), der.set([der.oid(OID.indirectData)])]),
    der.sequence([der.oid(OID.messageDigest), der.set([der.tlv(0x04, sha256(der.contents(indirect)))])]),
    der.sequence([der.oid(OID.statementType), der.set([der.sequence([der.oid(OID.individualCodeSigning)])])]),
    der.sequence([der.oid(OID.opusInfo), der.set([der.sequence([])])]),
  ].sort(Buffer.compare);
  const signature = signWith("sha256", der.set(attributes), signer.key);
  const signerInfo = der.sequence([
    der.integer(1), der.sequence([signer.issuer, der.tlv(0x02, signer.serial)]), digestAlgorithm,
    der.tlv(0xa0, Buffer.concat(attributes)),
    der.sequence([der.oid(OID.rsa), der.null]), der.tlv(0x04, signature),
  ]);
  const signedData = der.sequence([
    der.integer(1), der.set([digestAlgorithm]),
    der.sequence([der.oid(OID.indirectData), der.tlv(0xa0, indirect)]),
    der.tlv(0xa0, signer.certificate),
    der.set([signerInfo]),
  ]);
  return der.sequence([der.oid(OID.signedData), der.tlv(0xa0, signedData)]);
}

/** A certificate for Lamp's publisher name, signed by its own key, for code signing only. */
function selfSigned(key) {
  const pkcs1 = createPublicKey(key).export({ type: "pkcs1", format: "der" });
  const name = der.sequence([der.set([der.sequence([der.oid(OID.commonName), der.tlv(0x0c, Buffer.from("Lamp"))])])]);
  const spki = der.sequence([der.sequence([der.oid(OID.rsa), der.null]), der.tlv(0x03, Buffer.concat([Buffer.from([0]), pkcs1]))]);
  const serial = randomBytes(16);
  serial[0] = (serial[0] & 0x7f) | 0x01;
  const time = (date) => {
    const text = date.toISOString().replace(/[-:T]/g, "").slice(0, 14) + "Z";
    return date.getUTCFullYear() < 2050 ? der.tlv(0x17, Buffer.from(text.slice(2))) : der.tlv(0x18, Buffer.from(text));
  };
  const from = new Date(Date.now() - 86_400_000);
  const validity = der.sequence([time(from), time(new Date(from.getTime() + 20 * 365 * 86_400_000))]);
  const critical = der.tlv(0x01, Buffer.from([0xff]));
  const extensions = der.sequence([
    der.sequence([der.oid("2.5.29.19"), critical, der.tlv(0x04, der.sequence([]))]),
    der.sequence([der.oid("2.5.29.15"), critical, der.tlv(0x04, der.tlv(0x03, Buffer.from([0x07, 0x80])))]),
    der.sequence([der.oid("2.5.29.37"), der.tlv(0x04, der.sequence([der.oid("1.3.6.1.5.5.7.3.3")]))]),
    der.sequence([der.oid("2.5.29.14"), der.tlv(0x04, der.tlv(0x04, createHash("sha1").update(pkcs1).digest()))]),
  ]);
  const algorithm = der.sequence([der.oid(OID.sha256WithRSA), der.null]);
  const tbs = der.sequence([der.tlv(0xa0, der.integer(2)), der.tlv(0x02, serial), algorithm, name, validity, name, spki, der.tlv(0xa3, extensions)]);
  return der.sequence([tbs, algorithm, der.tlv(0x03, Buffer.concat([Buffer.from([0]), signWith("sha256", tbs, key)]))]);
}

/** A signer from a key (PKCS #1, as it's kept) and its certificate: the issuer and serial a signature names are read back out of the certificate. */
export function signerFrom(keyBytes, certificate) {
  const parts = der.children(der.children(certificate)[0] ?? Buffer.alloc(0));
  if (parts.length < 4) throw new Problem("lamp's certificate for app packages can't be read");
  const versioned = parts[0][0] === 0xa0;
  return {
    key: createPrivateKey({ key: keyBytes, format: "der", type: "pkcs1" }),
    certificate,
    serial: der.contents(parts[versioned ? 1 : 0]),
    issuer: parts[versioned ? 3 : 2],
  };
}

/** A new key (PKCS #1) and a certificate of its own for it. */
export function newSigner() {
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  return { key: privateKey.export({ type: "pkcs1", format: "der" }), certificate: selfSigned(privateKey) };
}

/** lamp's key and its own certificate for packages, made the first time and kept in `folder`, which only the person reads. */
export function keptSigner(folder) {
  const keyFile = join(folder, "key.der"), certificateFile = join(folder, "certificate.der");
  if (existsSync(keyFile) && existsSync(certificateFile)) {
    try { return signerFrom(readFileSync(keyFile), readFileSync(certificateFile)); } catch { /* made again below */ }
  }
  const made = newSigner();
  mkdirSync(folder, { recursive: true, mode: 0o700 });
  writeFileSync(keyFile, made.key, { mode: 0o600 });
  chmodSync(keyFile, 0o600);
  writeFileSync(certificateFile, made.certificate);
  return signerFrom(made.key, made.certificate);
}
