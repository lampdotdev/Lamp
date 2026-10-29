// The homepage's tapes in 3D (index.astro): New York's sleeve in the hero, and the stack of tapes beside "Change it
// live". They lean toward the pointer, and turn over when clicked to show what's on them: a screenshot on the
// tape's label. Every picture on them is drawn here on a 2D canvas in the page's own fonts, so they print like the
// rest of the page. The page's HTML version of each stays under the canvas, for anyone without WebGL and for
// screen readers; the canvas only takes over once it's drawn.

import type * as ThreeTypes from "three";

type Three = typeof ThreeTypes & { RoundedBoxGeometry: typeof import("three/examples/jsm/geometries/RoundedBoxGeometry.js").RoundedBoxGeometry };

/** three.js and the rounded box the tapes are made of, loaded once the page is up. */
async function three(): Promise<Three> {
  const [core, { RoundedBoxGeometry }] = await Promise.all([import("three"), import("three/examples/jsm/geometries/RoundedBoxGeometry.js")]);
  return { ...core, RoundedBoxGeometry };
}

/** A sleeve, as index.astro describes it: the hero's, and each on the shelf. Its front has its screenshot (as a remix
 * changed it), what it is and where it plays, and a "Remix me" that opens the remix dialog with `remix`
 * (`lamp:remix`, RemixDialog.astro); its back, the changes its starter suggests; its spine, the screenshot, the name or
 * a remix's change, and the stripes. Each place's icon is the `d` of a 256-unit SVG path. */
export type Sleeve = {
  /** An original, a remix of one (its change written on in marker), or a blank one waiting for an idea. */
  look: "original" | "remix" | "blank";
  /** The app's name, and the line over it: who made it, or what it's a remix of. */
  title: string;
  by: string;
  /** What kind of thing it is, and what it is in a line (a remix: its change). */
  kind: string;
  line: string;
  shot?: string;
  treat?: "snow" | "frame";
  tweaks: string[];
  places: { label: string; icon: string }[];
  remix?: string;
  /** The marker a remix's change is written in. */
  ink?: string;
};

const INK = "#1b1a17";
const PAPER = "#f2ecda";
const LABEL = "#f7f2e3";
const PLASTIC = "#26241f";
const RED = "#a8361f";
const MAGENTA = "#b8264f";
const WARM = ["#1f8a4a", "#7cbf3a", "#f6b81c", "#f08a1c", "#e2402a", "#d23778"];

const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

// MARK: Drawing

function sheet(width: number, height: number) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  return { canvas, ctx: canvas.getContext("2d")! };
}

const SANS = '"Inter Tight", "Helvetica Neue", Arial, sans-serif';
const MARKER = '"Permanent Marker", "Marker Felt", cursive';
const MONO = '"JetBrains Mono", ui-monospace, Menlo, monospace';

/** Sets a font, shrinking it until `text` fits in `width`. */
function font(ctx: CanvasRenderingContext2D, style: string, size: number, family: string, text?: string, width?: number) {
  let px = size;
  ctx.font = `${style} ${px}px ${family}`;
  while (text && width && px > 10 && ctx.measureText(text).width > width) {
    px -= 2;
    ctx.font = `${style} ${px}px ${family}`;
  }
}

function fontsReady() {
  return Promise.all([
    document.fonts.load(`900 80px ${SANS}`),
    document.fonts.load(`italic 800 40px ${SANS}`),
    document.fonts.load(`700 24px ${SANS}`),
    document.fonts.load(`40px ${MARKER}`),
    document.fonts.load(`700 24px ${MONO}`),
  ]).catch(() => undefined);
}

function image(src: string) {
  return new Promise<HTMLImageElement | undefined>((resolve) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => resolve(undefined);
    img.src = src;
  });
}

/** A screenshot shown whole in a box, as large as fits, on the box's ink, with what a remix did to it. `top` is how much
 * of the picture's top to leave out (none, as the sleeves have it: nothing of a screenshot is cut). */
function shot(ctx: CanvasRenderingContext2D, img: HTMLImageElement | undefined, x: number, y: number, w: number, h: number, treat?: Sleeve["treat"], top = 0) {
  ctx.save();
  ctx.fillStyle = INK;
  ctx.fillRect(x, y, w, h);
  let [bx, by, bw, bh] = [x, y, w, h];
  if (treat === "frame") {
    // Hung on the kitchen wall: a wooden frame with a mat.
    ctx.fillStyle = "#8a5a32";
    ctx.fillRect(x, y, w, h);
    ctx.fillStyle = LABEL;
    ctx.fillRect(x + 22, y + 22, w - 44, h - 44);
    [bx, by, bw, bh] = [x + 40, y + 40, w - 80, h - 80];
  }
  ctx.beginPath();
  ctx.rect(bx, by, bw, bh);
  ctx.clip();
  if (img) {
    const [sy, sh] = [img.height * top, img.height * (1 - top)];
    const scale = Math.min(bw / img.width, bh / sh);
    const dw = img.width * scale;
    const dh = sh * scale;
    ctx.drawImage(img, 0, sy, img.width, sh, bx + (bw - dw) / 2, by + (bh - dh) / 2, dw, dh);
  }
  if (treat === "snow") {
    // A winter night: colder, darker, and snowing.
    ctx.fillStyle = "rgb(40 70 140 / 0.35)";
    ctx.fillRect(bx, by, bw, bh);
    let seed = 7;
    const random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    ctx.fillStyle = "rgb(255 255 255 / 0.9)";
    for (let i = 0; i < 260; i++) {
      ctx.beginPath();
      ctx.arc(bx + random() * bw, by + random() * bh, 1.5 + random() * 3.5, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.restore();
}

function bands(ctx: CanvasRenderingContext2D, colors: string[], x: number, y: number, w: number, h: number, across = false) {
  colors.forEach((color, i) => {
    ctx.fillStyle = color;
    if (across) ctx.fillRect(x + (w / colors.length) * i, y, Math.ceil(w / colors.length), h);
    else ctx.fillRect(x, y + (h / colors.length) * i, w, Math.ceil(h / colors.length));
  });
}

/** Words broken into lines no wider than `width`, as many as `most`, the last cut short with an ellipsis. */
function lines(ctx: CanvasRenderingContext2D, text: string, width: number, most: number) {
  const out: string[] = [];
  for (const word of text.split(/\s+/)) {
    const line = out.length ? `${out[out.length - 1]} ${word}` : word;
    if (out.length && ctx.measureText(line).width <= width) out[out.length - 1] = line;
    else out.push(word);
  }
  if (out.length > most) out.splice(most - 1, out.length, `${out.slice(most - 1).join(" ").slice(0, 24)}…`);
  return out;
}

/** Ruled lines across a box, as on a blank label. */
function ruled(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, every: number) {
  ctx.strokeStyle = "rgb(42 111 176 / 0.3)";
  ctx.lineWidth = 3;
  for (let at = y + every; at < y + h; at += every) {
    ctx.beginPath();
    ctx.moveTo(x, at);
    ctx.lineTo(x + w, at);
    ctx.stroke();
  }
}

// The sleeve's front, back and spine, laid out at 800 units to its 1.05 of width and drawn at 1.28 pixels a unit,
// so its small print stays sharp at the size the hero shows it.
const SLEEVE_SCALE = 1.28;
function sleeveSheet(width: number) {
  const page = sheet(Math.round(width * SLEEVE_SCALE), Math.round(1448 * SLEEVE_SCALE));
  page.ctx.scale(SLEEVE_SCALE, SLEEVE_SCALE);
  return page;
}

/** The front's "Remix me" button, in the front's units: also where a click on the sleeve opens the remix dialog. */
const REMIX_BUTTON = { x: 56, y: 1280, w: 688, h: 112 };

/** `pointed` draws the "Remix me" button outlined, as it is while the pointer is over it. */
function sleeveFront(sleeve: Sleeve, img: HTMLImageElement | undefined, pointed = false) {
  const { canvas, ctx } = sleeveSheet(800);
  ctx.fillStyle = LABEL;
  ctx.fillRect(0, 0, 800, 1448);
  if (sleeve.look === "blank") {
    ruled(ctx, 0, 0, 800, 1448, 80);
    ctx.fillStyle = "#6f6857";
    ctx.save();
    ctx.translate(70, 640);
    ctx.rotate(-0.05);
    font(ctx, "", 120, MARKER);
    lines(ctx, sleeve.title, 660, 3).forEach((line, i) => ctx.fillText(line, 0, i * 150));
    ctx.restore();
    return canvas;
  }
  ctx.fillStyle = INK;
  font(ctx, "italic 800", 48, SANS, sleeve.by, 520);
  ctx.fillText(sleeve.by, 56, 110);
  ctx.fillStyle = RED;
  font(ctx, "700", 30, MONO);
  ctx.textAlign = "right";
  ctx.fillText(sleeve.kind.toUpperCase(), 744, 104);
  ctx.textAlign = "left";
  ctx.fillStyle = INK;
  font(ctx, "900", 150, SANS, sleeve.title, 688);
  ctx.fillText(sleeve.title, 50, 250);
  // The app itself, without the window's bar across its top.
  ctx.fillRect(56, 290, 688, 430);
  shot(ctx, img, 64, 298, 672, 414, sleeve.treat);
  bands(ctx, WARM, 0, 760, 800, 140);
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.moveTo(800, 730);
  ctx.lineTo(800, 930);
  ctx.lineTo(650, 830);
  ctx.fill();
  // A remix's change, in its marker, under the stripes; what an original is goes on the back, leaving the front room.
  const remix = sleeve.look === "remix";
  if (remix) {
    ctx.fillStyle = sleeve.ink ?? MAGENTA;
    font(ctx, "", 48, MARKER);
    const said = lines(ctx, sleeve.line, 688, 2);
    said.forEach((line, i) => ctx.fillText(line, 56, (said.length > 1 ? 972 : 990) + i * 50));
  }
  // Where it plays: each place's icon over its name.
  const [plays, icon] = remix ? [1078, 76] : [1004, 92];
  ctx.fillStyle = RED;
  font(ctx, "700", 24, MONO);
  ctx.fillText("PLAYS ON", 58, plays);
  sleeve.places.forEach((place, i) => {
    const x = 56 + i * 170;
    ctx.save();
    ctx.translate(x, plays + 20);
    ctx.scale(icon / 256, icon / 256);
    ctx.fillStyle = INK;
    ctx.fill(new Path2D(place.icon));
    ctx.restore();
    ctx.fillStyle = INK;
    font(ctx, "700", remix ? 26 : 30, SANS);
    ctx.fillText(place.label, x + 2, plays + icon + 56);
  });
  // The call to remix it, printed as a button, with an ink outline around it while it's pointed at.
  if (sleeve.remix) {
    const b = REMIX_BUTTON;
    if (pointed) {
      ctx.strokeStyle = INK;
      ctx.lineWidth = 7;
      ctx.beginPath();
      ctx.roundRect(b.x - 9, b.y - 9, b.w + 18, b.h + 18, 24);
      ctx.stroke();
    }
    ctx.fillStyle = "#c23a20";
    ctx.beginPath();
    ctx.roundRect(b.x, b.y, b.w, b.h, 18);
    ctx.fill();
    ctx.fillStyle = "#ffffff";
    ctx.textAlign = "center";
    font(ctx, "900", 54, SANS);
    ctx.fillText("Remix me →", b.x + b.w / 2, b.y + 74);
    ctx.textAlign = "left";
  }
  return canvas;
}

function sleeveBack(sleeve: Sleeve) {
  const { canvas, ctx } = sleeveSheet(800);
  ctx.fillStyle = LABEL;
  ctx.fillRect(0, 0, 800, 1448);
  if (sleeve.look === "blank") {
    ruled(ctx, 0, 0, 800, 1448, 80);
    return canvas;
  }
  ctx.fillStyle = INK;
  font(ctx, "900", 110, SANS, sleeve.title, 688);
  ctx.fillText(sleeve.title, 52, 170);
  font(ctx, "italic 800", 44, SANS, sleeve.by, 688);
  ctx.fillText(sleeve.by, 58, 236);
  // What an original is, in full (a remix's change is on its front).
  let below = 300;
  if (sleeve.look === "original" && sleeve.line) {
    font(ctx, "500", 40, SANS);
    lines(ctx, sleeve.line, 688, 4).forEach((line, i) => ctx.fillText(line, 58, 340 + i * 54));
    below = 340 + lines(ctx, sleeve.line, 688, 4).length * 54;
  }
  ctx.fillStyle = RED;
  font(ctx, "700", 26, MONO);
  ctx.fillText("IDEAS FOR YOUR REMIX", 58, below + 70);
  const inks = [MAGENTA, "#1f7a42", RED];
  sleeve.tweaks.forEach((tweak, i) => {
    ctx.fillStyle = inks[i % inks.length];
    ctx.save();
    ctx.translate(58, below + 170 + i * 110);
    ctx.rotate(i % 2 ? 0.02 : -0.025);
    font(ctx, "", 56, MARKER, tweak, 680);
    ctx.fillText(tweak, 0, 0);
    ctx.restore();
  });
  ctx.fillStyle = INK;
  font(ctx, "italic 800", 40, SANS);
  ctx.fillText("Remix it with Lamp. No code.", 58, 1120);
  bands(ctx, WARM, 0, 1240, 800, 208);
  return canvas;
}

// The spine runs the sleeve's length; it's drawn on its side, 1448 across and 220 high, read from its bottom end up as
// it stands, and from left to right as it lies on the shelf: the screenshot, the name (a remix: its change, in marker,
// over what it's a remix of), and the stripes upright at its far end.
function sleeveSpine(sleeve: Sleeve, img: HTMLImageElement | undefined) {
  const { canvas, ctx } = sleeveSheet(220);
  ctx.translate(0, 1448);
  ctx.rotate(-Math.PI / 2);
  const original = sleeve.look === "original";
  ctx.fillStyle = original ? LABEL : PLASTIC;
  ctx.fillRect(0, 0, 1448, 220);
  if (sleeve.look === "blank") {
    ctx.fillStyle = LABEL;
    ctx.fillRect(24, 24, 1400, 172);
    ruled(ctx, 24, 24, 1400, 172, 44);
    ctx.fillStyle = "#6f6857";
    font(ctx, "", 66, MARKER);
    ctx.fillText(sleeve.title, 60, 134);
    return canvas;
  }
  shot(ctx, img, 0, 0, 340, 220, sleeve.treat);
  bands(ctx, WARM, 1268, 0, 180, 220, true);
  if (original) {
    ctx.fillStyle = INK;
    font(ctx, "900", 96, SANS, sleeve.title, 860);
    ctx.fillText(sleeve.title, 380, 126);
    font(ctx, "700", 26, SANS, sleeve.by.toUpperCase(), 860);
    ctx.fillText(sleeve.by.toUpperCase(), 384, 176);
  } else {
    ctx.fillStyle = LABEL;
    ctx.fillRect(364, 22, 880, 176);
    ctx.textAlign = "center";
    ctx.fillStyle = sleeve.ink ?? MAGENTA;
    font(ctx, "", 64, MARKER, sleeve.line, 840);
    ctx.fillText(sleeve.line, 804, 112);
    ctx.fillStyle = INK;
    font(ctx, "700", 24, SANS, sleeve.by.toUpperCase(), 840);
    ctx.fillText(sleeve.by.toUpperCase(), 804, 166);
    ctx.textAlign = "left";
  }
  return canvas;
}

// MARK: Staging

// A scene lit from the upper left, with an unseen wall behind it that catches the tapes' shadows, so they cast them
// on the page. `reach` is how far the shadows need to go. The canvas runs past its host by `bleed` (a share of the
// host's width and height on each side), so a tape that flies out or hops isn't cut off at the host's edges; the
// tapes stay the size the host gives them. The canvas lets the pointer through to whatever it overlaps, and only a
// press on a tape is the tapes'.
function stage(THREE: Three, host: HTMLElement, { wall, reach, bleed }: { wall: number; reach: number; bleed: { x: number; y: number } }) {
  let renderer: ThreeTypes.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  } catch {
    return undefined;
  }
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  const canvas = renderer.domElement;
  canvas.setAttribute("aria-hidden", "true");
  canvas.className = "tape-canvas";
  const scene = new THREE.Scene();
  const FOV = 30;
  const camera = new THREE.PerspectiveCamera(FOV, 1, 0.1, 100);
  Object.assign(canvas.style, {
    left: `${-bleed.x * 100}%`, top: `${-bleed.y * 100}%`, width: `${(1 + 2 * bleed.x) * 100}%`, height: `${(1 + 2 * bleed.y) * 100}%`,
  });
  const anisotropy = renderer.capabilities.getMaxAnisotropy();
  const texture = (source: HTMLCanvasElement) => {
    const map = new THREE.CanvasTexture(source);
    map.colorSpace = THREE.SRGBColorSpace;
    map.anisotropy = anisotropy;
    return new THREE.MeshStandardMaterial({ map, roughness: 0.62, metalness: 0 });
  };
  const flat = (color: string) => new THREE.MeshStandardMaterial({ color, roughness: 0.42, metalness: 0 });

  // An even light all round and a key light from the upper left. three.js counts light in physical units, where a
  // face lit at 1 shows its color divided by π, so the two add up to about π on a face turned to the key light: the
  // print shows its own colors there, neither washed out nor grey, and the faces turned away fall into shade.
  scene.add(new THREE.AmbientLight(0xffffff, 1.7));
  const sun = new THREE.DirectionalLight(0xfff6ea, 1.75);
  sun.position.set(-2.6, 3.6, 6);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, { left: -reach, right: reach, top: reach, bottom: -reach, near: 0.5, far: 20 });
  sun.shadow.camera.updateProjectionMatrix();
  sun.shadow.radius = 6;
  sun.shadow.blurSamples = 16;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.02;
  scene.add(sun);
  const backdrop = new THREE.Mesh(new THREE.PlaneGeometry(reach * 4, reach * 4), new THREE.ShadowMaterial({ opacity: 0.3 }));
  backdrop.position.z = wall;
  backdrop.receiveShadow = true;
  scene.add(backdrop);
  /** Makes a mesh cast shadows, and catch those of the others. */
  const solid = <T extends ThreeTypes.Mesh>(mesh: T) => {
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    return mesh;
  };

  // Where the pointer is, from -1 to 1 across the host's own box. While a dialog is open over the page (the remix
  // dialog), the tapes behind it hold still and take no clicks.
  const covered = () => !!document.querySelector("dialog[open]");
  const pointer = { x: 0, y: 0 };
  addEventListener("pointermove", (event) => {
    if (covered()) return;
    const box = host.getBoundingClientRect();
    pointer.x = Math.max(-1, Math.min(1, ((event.clientX - box.left) / box.width) * 2 - 1));
    pointer.y = Math.max(-1, Math.min(1, ((event.clientY - box.top) / box.height) * 2 - 1));
  }, { passive: true });

  const raycaster = new THREE.Raycaster();
  const hit = (event: PointerEvent | MouseEvent, objects: ThreeTypes.Object3D[]) => {
    const box = canvas.getBoundingClientRect();
    const ndc = new THREE.Vector2(((event.clientX - box.left) / box.width) * 2 - 1, -((event.clientY - box.top) / box.height) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    return raycaster.intersectObjects(objects, true)[0];
  };

  /** Calls `act` for a press, or `move` as the pointer moves, over the canvas but not on a link or a button. */
  const on = (type: "click" | "pointermove", act: (event: MouseEvent) => void) => {
    document.addEventListener(type, (event) => {
      const box = canvas.getBoundingClientRect();
      const inside = event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom;
      if (inside && !covered() && !(event.target as Element | null)?.closest?.("a, button, input")) act(event);
      else if (type === "pointermove") act(new MouseEvent("pointermove", { clientX: -1e6, clientY: -1e6 }));
    });
  };
  let pointing = false;
  /** Shows the hand while the pointer is over a tape. */
  const hand = (over: boolean) => {
    if (over === pointing) return;
    pointing = over;
    document.documentElement.style.cursor = over ? "pointer" : "";
  };

  const run = (fit: (aspect: number, tan: number) => void, frame: (dt: number, time: number) => void) => {
    const resize = () => {
      const { width, height } = host.getBoundingClientRect();
      if (!width || !height) return;
      const [w, h] = [width * (1 + 2 * bleed.x), height * (1 + 2 * bleed.y)];
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      // The camera is placed to fit the host, then widened to take in the bleed around it.
      const tan = Math.tan((FOV * Math.PI) / 360);
      fit(width / height, tan);
      camera.fov = (Math.atan(tan * (1 + 2 * bleed.y)) * 360) / Math.PI;
      camera.updateProjectionMatrix();
    };
    new ResizeObserver(resize).observe(host);
    resize();
    let visible = false;
    let last = performance.now();
    const tick = (now: number) => {
      if (!visible) return;
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      frame(dt, now / 1000);
      renderer.render(scene, camera);
      requestAnimationFrame(tick);
    };
    new IntersectionObserver(([entry]) => {
      const was = visible;
      visible = entry.isIntersecting;
      if (visible && !was) {
        last = performance.now();
        requestAnimationFrame(tick);
      }
    }).observe(host);
    host.prepend(canvas);
    host.classList.add("is-3d");
  };

  return { THREE, scene, camera, canvas, texture, flat, solid, pointer, hit, on, hand, run };
}

/** Whether a sleeve has been turned over in this browser, after which the arrow that shows the way never shows again. */
const TURNED = "lamp.sleeveTurned";
const turned = {
  once: (() => { try { return localStorage.getItem(TURNED) === "1"; } catch { return false; } })(),
  now() {
    this.once = true;
    try { localStorage.setItem(TURNED, "1"); } catch { /* kept for this visit only */ }
  },
};

/** Eases `value` toward `target`, by how long the frame took. */
const ease = (value: number, target: number, dt: number, speed = 7) => value + (target - value) * (1 - Math.exp(-dt * speed));

// MARK: A sleeve

/** A sleeve as a lit box: its faces (the front twice, plain and with its "Remix me" outlined, for while the pointer is
 * over the button), and whether a hit on it is on that button. */
function buildSleeve(s: NonNullable<ReturnType<typeof stage>>, THREE: Three, sleeve: Sleeve, img: HTMLImageElement | undefined) {
  const spine = s.texture(sleeveSpine(sleeve, img));
  const [front, frontPointed] = [s.texture(sleeveFront(sleeve, img)), s.texture(sleeveFront(sleeve, img, true))];
  const faces = [spine, spine, s.flat(INK), s.flat(INK), front, s.texture(sleeveBack(sleeve))];
  const box = s.solid(new THREE.Mesh(new THREE.RoundedBoxGeometry(1.05, 1.9, 0.3, 3, 0.025), faces));
  const onButton = (found: ThreeTypes.Intersection | undefined) => {
    if (!sleeve.remix || found?.object !== box || !found.uv || found.face?.materialIndex !== 4) return false;
    const [x, y] = [found.uv.x * 800, (1 - found.uv.y) * 1448];
    const b = REMIX_BUTTON;
    return x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h;
  };
  /** Outlines the button, or not. */
  const point = (on: boolean) => {
    faces[4] = on ? frontPointed : front;
    box.material = faces;
  };
  const remix = () => { if (sleeve.remix) document.dispatchEvent(new CustomEvent("lamp:remix", { detail: sleeve.remix })); };

  // The turn it takes when clicked (its right side swinging toward the viewer), shown by a flat magenta arrow round
  // its right side, from the back to the front, its tail fading in from nothing and its head in front pointing the way
  // the front goes: seen while the pointer is on the sleeve and not on its button, until a sleeve has been turned over
  // once (`turnedOnce`). It's placed by whoever shows the sleeve, at its place and lean but never its turn, and fades
  // in and out as `aim` asks.
  const arrow = new THREE.Group();
  const fadeIn = sheet(256, 1);
  const ramp = fadeIn.ctx.createLinearGradient(0, 0, 256, 0);
  ramp.addColorStop(0, "rgb(255 255 255 / 0)");
  ramp.addColorStop(0.75, "rgb(255 255 255 / 1)");
  fadeIn.ctx.fillStyle = ramp;
  fadeIn.ctx.fillRect(0, 0, 256, 1);
  const ink = new THREE.MeshBasicMaterial({
    color: "#d23778", map: new THREE.CanvasTexture(fadeIn.canvas), transparent: true, opacity: 0,
    side: THREE.DoubleSide, depthWrite: false,
  });
  const along = (t: number) => new THREE.Vector3(0.86 * Math.cos(t), 0, 0.48 * Math.sin(t));
  const [from, to, steps, band] = [-1.25, 1.25, 48, 0.07];
  // A band standing round the sleeve, as tall as `band`, its texture running from the tail (0) to the head (1).
  const ribbon: number[] = [], uvs: number[] = [], order: number[] = [];
  for (let i = 0; i < steps; i++) {
    const at = along(from + ((to - from) * i) / (steps - 1));
    ribbon.push(at.x, -band / 2, at.z, at.x, band / 2, at.z);
    uvs.push(i / (steps - 1), 0, i / (steps - 1), 1);
    if (i) order.push(2 * i - 2, 2 * i - 1, 2 * i, 2 * i - 1, 2 * i + 1, 2 * i);
  }
  // Its head: a flat triangle in the band, twice as tall, pointing on along the curve.
  const end = along(to);
  const ahead = end.clone().sub(along(to - 0.05)).normalize();
  const tip = end.clone().addScaledVector(ahead, 0.2);
  const base = steps * 2;
  ribbon.push(end.x, -band * 1.6, end.z, end.x, band * 1.6, end.z, tip.x, 0, tip.z);
  uvs.push(1, 0, 1, 1, 1, 0.5);
  order.push(base, base + 1, base + 2);
  const shape = new THREE.BufferGeometry();
  shape.setAttribute("position", new THREE.Float32BufferAttribute(ribbon, 3));
  shape.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));
  shape.setIndex(order);
  arrow.add(new THREE.Mesh(shape, ink));
  arrow.visible = false;
  let aimed = false;
  /** Shows the arrow, or not; never again once a sleeve has been turned. */
  const aim = (on: boolean) => { aimed = on && !turned.once; };
  /** Fades the arrow toward what `aim` asked, by how long the frame took. */
  const fade = (dt: number) => {
    if (turned.once) aimed = false;
    ink.opacity = ease(ink.opacity, aimed ? 1 : 0, dt, aimed ? 10 : 6);
    arrow.visible = ink.opacity > 0.01;
  };
  return { box, onButton, point, remix, arrow, aim, fade };
}

// MARK: The hero's sleeve

export async function mountSleeve(host: HTMLElement) {
  const sleeve = JSON.parse(host.dataset.sleeve!) as Sleeve;
  const [THREE, img] = await Promise.all([three(), sleeve.shot ? image(sleeve.shot) : Promise.resolve(undefined), fontsReady()]);
  const s = stage(THREE, host, { wall: -0.75, reach: 3, bleed: { x: 0.15, y: 0.2 } });
  if (!s) return;
  const built = buildSleeve(s, THREE, sleeve, img);
  const box = built.box;
  // On its own, it only casts its shadow: catching its own would shade its front with the slightest error.
  box.receiveShadow = false;
  const sleeveGroup = new THREE.Group();
  sleeveGroup.add(box);
  s.scene.add(sleeveGroup, built.arrow);

  // Clicked, it flips over: half a turn, onto whichever side it wasn't on. A click on the front's printed "Remix me"
  // button opens the remix dialog instead. The button that turns it (for a keyboard) says which
  // way up it is.
  const button = host.querySelector<HTMLButtonElement>("[data-turn]");
  let spin = 0;
  let back = false;
  const turn = () => {
    turned.now();
    spin -= Math.PI;
    back = !back;
    button?.setAttribute("aria-pressed", String(back));
  };
  s.on("click", (event) => {
    const found = s.hit(event, [box]);
    if (built.onButton(found)) built.remix();
    else if (found) turn();
  });
  s.on("pointermove", (event) => {
    const found = s.hit(event, [box]);
    s.hand(!!found);
    const onButton = built.onButton(found);
    built.point(onButton);
    built.aim(!!found && !onButton);
  });
  button?.addEventListener("click", turn);

  let rotation = { x: 0, y: -0.35 };
  let spun = 0;
  s.run(
    (aspect, tan) => {
      s.camera.position.set(0, 0, Math.max(2.15 / (2 * tan), 1.45 / (2 * tan * aspect)));
    },
    (dt, time) => {
      const tilt = reduced ? { x: 0, y: 0 } : s.pointer;
      // It turns toward the pointer across, and leans back from it up and down: below it, the front tips up.
      rotation = { x: ease(rotation.x, 0.06 - tilt.y * 0.3, dt, 5), y: ease(rotation.y, -0.35 + tilt.x * 0.6, dt, 5) };
      spun = ease(spun, spin, dt, reduced ? 12 : 5);
      sleeveGroup.rotation.set(rotation.x, rotation.y + spun, 0);
      sleeveGroup.position.y = reduced ? 0 : Math.sin(time * 1.3) * 0.04;
      built.arrow.rotation.set(rotation.x, rotation.y, 0);
      built.arrow.position.copy(sleeveGroup.position);
      built.fade(dt);
    },
  );
}

// MARK: The shelf

const STACK_BLEED = { x: 0.12, y: 0.3 };

// The shelf: the same sleeves, lying flat in a stack with their spines out, each original with its remix under it, a
// little untidy, as a real stack is. One that's clicked comes out and stands up facing the viewer, as the hero's does:
// it leans toward the pointer, turns over when clicked again, and its "Remix me" opens the remix dialog. Clicked
// anywhere else, it goes back.
export async function mountStack(host: HTMLElement) {
  const sleeves = JSON.parse(host.dataset.sleeves!) as Sleeve[];
  const [THREE, shots] = await Promise.all([
    three(),
    Promise.all(sleeves.map((sleeve) => (sleeve.shot ? image(sleeve.shot) : Promise.resolve(undefined)))),
    fontsReady(),
  ]);
  const s = stage(THREE, host, { wall: -1.6, reach: 6, bleed: STACK_BLEED });
  if (!s) return;
  // Lying flat, a sleeve's length runs across, its depth is its height in the stack, and its spine faces the viewer.
  const [W, H, GAP] = [1.9, 0.3, 0.05];
  const flat = new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(
    new THREE.Vector3(0, 0, 1), new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 1, 0)));
  const stack = new THREE.Group();
  s.scene.add(stack);

  const jitter = [0.06, -0.05, 0.09, -0.03, 0.04, -0.08, 0.02];
  const height = sleeves.length * (H + GAP);
  const up = new THREE.Vector3(0, 1, 0);
  const items = sleeves.map((sleeve, i) => {
    const built = buildSleeve(s, THREE, sleeve, shots[i]);
    stack.add(built.box, built.arrow);
    const home = {
      position: new THREE.Vector3(jitter[i % jitter.length], height / 2 - H / 2 - i * (H + GAP), 0),
      quaternion: new THREE.Quaternion().setFromAxisAngle(up, jitter[(i + 2) % jitter.length] * 0.4).multiply(flat),
    };
    built.box.position.copy(home.position);
    built.box.quaternion.copy(home.quaternion);
    return { built, home, turns: 0 };
  });

  let chosen = -1;
  let hovered = -1;
  /** The sleeve under the pointer, and whether it's on the chosen one's "Remix me". */
  const pointedAt = (event: MouseEvent) => {
    const found = s.hit(event, items.map(({ built }) => built.box));
    const i = items.findIndex(({ built }) => built.box === found?.object);
    return { i, onButton: i >= 0 && i === chosen && items[i].built.onButton(found) };
  };
  s.on("click", (event) => {
    const { i, onButton } = pointedAt(event);
    if (onButton) items[i].built.remix();
    else if (i >= 0 && i === chosen) {
      items[i].turns += 1;
      turned.now();
    }
    else if (i >= 0) {
      chosen = i;
      items[i].turns = 0;
    } else chosen = -1;
  });
  s.on("pointermove", (event) => {
    const { i, onButton } = pointedAt(event);
    hovered = i;
    s.hand(i >= 0);
    items.forEach(({ built }, j) => {
      built.point(onButton && j === i);
      built.aim(j === i && i === chosen && !onButton);
    });
  });
  // For a keyboard, a button for each sleeve that can be remixed opens the remix dialog for it, as its "Remix me" does.
  host.querySelectorAll<HTMLButtonElement>("[data-sleeve]").forEach((button) => {
    button.addEventListener("click", () => items[Number(button.dataset.sleeve)]?.built.remix());
  });

  let tilt = { x: 0, y: 0 };
  // How far in front of the stack a chosen sleeve stands.
  let held = 2.2;
  const target = new THREE.Vector3();
  const facing = new THREE.Quaternion();
  const euler = new THREE.Euler();
  s.run(
    (aspect, tan) => {
      // The whole stack fits the host, and so does a chosen sleeve standing in front of it, with room to lean.
      const distance = Math.max((height + 0.5) / (2 * tan), (W + 1.2) / (2 * tan * aspect));
      const near = Math.max(2.35 / (2 * tan), 1.6 / (2 * tan * aspect));
      held = Math.max(0, distance - near);
      s.camera.position.set(0, 0, distance);
    },
    (dt) => {
      const p = reduced ? { x: 0, y: 0 } : s.pointer;
      tilt = { x: ease(tilt.x, 0.14 + p.y * 0.18, dt, 4), y: ease(tilt.y, p.x * 0.3, dt, 4) };
      stack.rotation.set(tilt.x, tilt.y, 0);
      const k = 1 - Math.exp(-dt * (reduced ? 14 : 5));
      items.forEach((item, i) => {
        const box = item.built.box;
        if (i === chosen) {
          // Standing in front of the stack, square to the viewer whatever the stack's lean, turned toward the pointer
          // across and tipped back from it up and down, as the hero's sleeve is; turned over as many times as asked.
          euler.set(-p.y * 0.25, p.x * 0.4 - item.turns * Math.PI, 0);
          facing.setFromEuler(euler).premultiply(stack.quaternion.clone().invert());
          target.set(0, 0, held).applyQuaternion(stack.quaternion.clone().invert());
          box.position.lerp(target, k);
          box.quaternion.slerp(facing, k);
          // The arrow round it leans as it does, but never turns with it.
          euler.set(-p.y * 0.25, p.x * 0.4, 0);
          item.built.arrow.quaternion.setFromEuler(euler).premultiply(stack.quaternion.clone().invert());
          item.built.arrow.position.copy(box.position);
        } else {
          // In its place; pulled out a little under the pointer, pushed back a little while another is out.
          target.copy(item.home.position);
          target.z += chosen >= 0 ? -0.2 : hovered === i ? 0.3 : 0;
          box.position.lerp(target, k);
          box.quaternion.slerp(item.home.quaternion, k);
          item.built.aim(false);
        }
        item.built.fade(dt);
      });
    },
  );
}
