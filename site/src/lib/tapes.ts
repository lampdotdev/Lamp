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

/** One tape in the stack, as index.astro describes it. */
export type Tape = {
  /** How its spine is printed: a printed original, a remix written on in marker, or a blank one. */
  look: "original" | "marker" | "blank";
  title: string;
  caption: string;
  /** The tag at the spine's end (A1, B2…). */
  side?: string;
  /** The color of the marker it's written in. */
  ink?: string;
  /** An original's stripes. */
  stripes?: "warm" | "cool";
  /** Its screenshot, and what the remix did to it. */
  shot?: string;
  treat?: "snow" | "frame";
};

/** The hero's sleeve: its screenshot and where it plays on the front, the changes it suggests on the back, and the
 * query its printed "Remix me" button opens the remix dialog with (`lamp:remix`, RemixDialog.astro). Each place's icon
 * is the `d` of a 256-unit SVG path. */
export type Sleeve = {
  title: string; by: string; kind: string; line: string; shot: string; tweaks: string[];
  places: { label: string; icon: string }[]; remix: string;
};

const INK = "#1b1a17";
const PAPER = "#f2ecda";
const LABEL = "#f7f2e3";
const PLASTIC = "#26241f";
const RED = "#a8361f";
const MAGENTA = "#b8264f";
const WARM = ["#1f8a4a", "#7cbf3a", "#f6b81c", "#f08a1c", "#e2402a", "#d23778"];
const COOL = ["#1f8a4a", "#f6b81c", "#e2402a"];

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

/** A screenshot filling a box, cropped to it, with what a remix did to it. `top` is how much of the picture's top to
 * leave out (a window's own bar). */
function shot(ctx: CanvasRenderingContext2D, img: HTMLImageElement | undefined, x: number, y: number, w: number, h: number, treat?: Tape["treat"], top = 0) {
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
    const scale = Math.max(bw / img.width, bh / sh);
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

function tag(ctx: CanvasRenderingContext2D, text: string, right: number, middle: number) {
  font(ctx, "700", 34, MONO);
  const w = ctx.measureText(text).width + 24;
  ctx.strokeStyle = "#a39c88";
  ctx.lineWidth = 3;
  ctx.strokeRect(right - w, middle - 26, w, 52);
  ctx.fillStyle = PAPER;
  ctx.textAlign = "left";
  ctx.fillText(text, right - w + 12, middle + 12);
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
  ctx.fillStyle = INK;
  font(ctx, "italic 800", 48, SANS);
  ctx.fillText(sleeve.by, 56, 110);
  ctx.fillStyle = RED;
  font(ctx, "700", 30, MONO);
  ctx.textAlign = "right";
  ctx.fillText(sleeve.kind.toUpperCase(), 744, 104);
  ctx.textAlign = "left";
  ctx.fillStyle = INK;
  font(ctx, "900", 150, SANS, sleeve.title, 688);
  ctx.fillText(sleeve.title, 50, 250);
  // The game itself, without the window's bar across its top.
  ctx.fillRect(56, 290, 688, 430);
  shot(ctx, img, 64, 298, 672, 414, undefined, 0.09);
  bands(ctx, WARM, 0, 760, 800, 140);
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.moveTo(800, 730);
  ctx.lineTo(800, 930);
  ctx.lineTo(650, 830);
  ctx.fill();
  font(ctx, "italic 800", 42, SANS, sleeve.line, 688);
  ctx.fillText(sleeve.line, 56, 990);
  // Where it plays: each place's icon over its name.
  ctx.fillStyle = RED;
  font(ctx, "700", 24, MONO);
  ctx.fillText("PLAYS ON", 58, 1058);
  sleeve.places.forEach((place, i) => {
    const x = 56 + i * 170;
    ctx.save();
    ctx.translate(x, 1082);
    ctx.scale(84 / 256, 84 / 256);
    ctx.fillStyle = INK;
    ctx.fill(new Path2D(place.icon));
    ctx.restore();
    ctx.fillStyle = INK;
    font(ctx, "700", 28, SANS);
    ctx.fillText(place.label, x + 2, 1206);
  });
  // The call to remix it, printed as a button, with an ink outline around it while it's pointed at.
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
  return canvas;
}

function sleeveBack(sleeve: Sleeve) {
  const { canvas, ctx } = sleeveSheet(800);
  ctx.fillStyle = LABEL;
  ctx.fillRect(0, 0, 800, 1448);
  ctx.fillStyle = INK;
  font(ctx, "900", 110, SANS, sleeve.title, 688);
  ctx.fillText(sleeve.title, 52, 170);
  font(ctx, "italic 800", 44, SANS);
  ctx.fillText(`by ${sleeve.by.replace(/^Made by /, "")}`, 58, 236);
  ctx.fillStyle = RED;
  font(ctx, "700", 26, MONO);
  ctx.fillText("IDEAS FOR YOUR REMIX", 58, 360);
  const inks = [MAGENTA, "#1f7a42", RED];
  sleeve.tweaks.forEach((tweak, i) => {
    ctx.fillStyle = inks[i % inks.length];
    ctx.save();
    ctx.translate(58, 460 + i * 110);
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

function sleeveSpine(sleeve: Sleeve) {
  const { canvas, ctx } = sleeveSheet(220);
  ctx.fillStyle = INK;
  ctx.fillRect(0, 0, 220, 1448);
  bands(ctx, WARM, 0, 0, 220, 300);
  ctx.save();
  ctx.translate(140, 1360);
  ctx.rotate(-Math.PI / 2);
  ctx.fillStyle = PAPER;
  font(ctx, "900", 96, SANS, sleeve.title.toUpperCase(), 1000);
  ctx.fillText(sleeve.title.toUpperCase(), 0, 0);
  ctx.restore();
  return canvas;
}

// A tape's spine, at 1480 by 200, and the top of the cassette with its label, at 1480 by 826.
// An original shows its screenshot at the spine's left end and the sleeve's stripes, upright, at its right.
function tapeSpine(tape: Tape, img?: HTMLImageElement) {
  const { canvas, ctx } = sheet(1480, 200);
  const printed = tape.look === "original" && tape.stripes !== "cool";
  ctx.fillStyle = printed ? LABEL : PLASTIC;
  ctx.fillRect(0, 0, 1480, 200);
  if (printed) {
    shot(ctx, img, 0, 0, 440, 200, undefined, 0.06);
    bands(ctx, WARM, 1300, 0, 180, 200, true);
    ctx.fillStyle = INK;
    font(ctx, "900", 92, SANS, tape.title, 780);
    ctx.fillText(tape.title, 490, 112);
    font(ctx, "700", 28, SANS, tape.caption, 780);
    ctx.fillText(tape.caption, 494, 160);
  } else if (tape.look === "original") {
    shot(ctx, img, 50, 26, 280, 148, undefined, 0.06);
    bands(ctx, COOL, 1330, 26, 120, 148, true);
    ctx.fillStyle = PAPER;
    font(ctx, "900", 78, SANS, tape.title.toUpperCase(), 760);
    ctx.fillText(tape.title.toUpperCase(), 370, 112);
    ctx.fillStyle = "#cfc8b2";
    font(ctx, "700", 26, SANS, tape.caption, 760);
    ctx.fillText(tape.caption, 372, 156);
  } else {
    ctx.save();
    ctx.translate(58, 150);
    ctx.rotate(-Math.PI / 2);
    ctx.fillStyle = "#a39c88";
    font(ctx, "500", 24, MONO);
    ctx.fillText(tape.look === "blank" ? "T‑120" : "E‑180", 0, 0);
    ctx.restore();
    ctx.fillStyle = LABEL;
    ctx.fillRect(100, 20, 1180, 160);
    if (tape.look === "blank") {
      ctx.strokeStyle = "rgb(42 111 176 / 0.35)";
      ctx.lineWidth = 2;
      for (let y = 60; y < 180; y += 38) {
        ctx.beginPath();
        ctx.moveTo(100, y);
        ctx.lineTo(1280, y);
        ctx.stroke();
      }
    }
    ctx.textAlign = "center";
    ctx.fillStyle = tape.look === "blank" ? "#6f6857" : (tape.ink ?? MAGENTA);
    font(ctx, "", 72, MARKER, tape.title, 1100);
    ctx.fillText(tape.title, 690, tape.look === "blank" ? 125 : 105);
    if (tape.look !== "blank") {
      ctx.fillStyle = INK;
      font(ctx, "700", 26, SANS);
      ctx.fillText(tape.caption, 690, 160);
    }
    ctx.textAlign = "left";
  }
  if (tape.look === "blank") {
    ctx.fillStyle = "#c23a20";
    ctx.fillRect(1310, 62, 150, 76);
    ctx.fillStyle = PAPER;
    font(ctx, "900", 34, SANS);
    ctx.fillText("● REC", 1326, 112);
  } else if (tape.side && !printed) {
    tag(ctx, tape.side, tape.look === "original" ? 1300 : 1450, 100);
  }
  return canvas;
}

function tapeTop(tape: Tape, img: HTMLImageElement | undefined) {
  const { canvas, ctx } = sheet(1480, 826);
  ctx.fillStyle = PLASTIC;
  ctx.fillRect(0, 0, 1480, 826);
  // The plastic's ribs.
  ctx.fillStyle = "rgb(255 255 255 / 0.04)";
  for (let y = 0; y < 826; y += 14) ctx.fillRect(0, y, 1480, 6);
  ctx.fillStyle = LABEL;
  ctx.fillRect(40, 40, 1020, 746);
  if (tape.look === "blank") {
    ctx.strokeStyle = "rgb(42 111 176 / 0.35)";
    ctx.lineWidth = 3;
    for (let y = 120; y < 780; y += 60) {
      ctx.beginPath();
      ctx.moveTo(40, y);
      ctx.lineTo(1060, y);
      ctx.stroke();
    }
    ctx.fillStyle = "#6f6857";
    ctx.save();
    ctx.translate(90, 440);
    ctx.rotate(-0.04);
    font(ctx, "", 110, MARKER);
    ctx.fillText(tape.title, 0, 0);
    ctx.restore();
  } else {
    shot(ctx, img, 70, 70, 960, 540, tape.treat);
    ctx.fillStyle = tape.look === "marker" ? (tape.ink ?? MAGENTA) : INK;
    if (tape.look === "marker") font(ctx, "", 64, MARKER, tape.title, 940);
    else font(ctx, "900", 70, SANS, tape.title, 940);
    ctx.fillText(tape.title, 72, 692);
    ctx.fillStyle = INK;
    font(ctx, "700", 30, SANS, tape.caption, 940);
    ctx.fillText(tape.caption, 74, 748);
  }
  // The tape's window, with its two reels.
  ctx.fillStyle = "#0f0e0c";
  ctx.fillRect(1110, 300, 330, 230);
  ctx.strokeStyle = "#5c574a";
  ctx.lineWidth = 6;
  for (const x of [1190, 1360]) {
    ctx.beginPath();
    ctx.arc(x, 415, 56, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.fillStyle = PAPER;
  font(ctx, "900", 84, SANS);
  ctx.fillText("VHS", 1150, 200);
  ctx.fillStyle = "#a39c88";
  font(ctx, "500", 28, MONO);
  ctx.fillText(tape.side ? `SIDE ${tape.side}` : "T‑120", 1152, 640);
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

/** Eases `value` toward `target`, by how long the frame took. */
const ease = (value: number, target: number, dt: number, speed = 7) => value + (target - value) * (1 - Math.exp(-dt * speed));

// MARK: The hero's sleeve

export async function mountSleeve(host: HTMLElement) {
  const sleeve = JSON.parse(host.dataset.sleeve!) as Sleeve;
  const [THREE, img] = await Promise.all([three(), image(sleeve.shot), fontsReady()]);
  const s = stage(THREE, host, { wall: -0.75, reach: 3, bleed: { x: 0.15, y: 0.2 } });
  if (!s) return;
  const spine = s.texture(sleeveSpine(sleeve));
  // The front twice: as it is, and with its "Remix me" outlined, for while the pointer is over the button.
  const [front, frontPointed] = [s.texture(sleeveFront(sleeve, img)), s.texture(sleeveFront(sleeve, img, true))];
  const faces = [spine, spine, s.flat(INK), s.flat(INK), front, s.texture(sleeveBack(sleeve))];
  const box = s.solid(new THREE.Mesh(new THREE.RoundedBoxGeometry(1.05, 1.9, 0.3, 3, 0.025), faces));
  // On its own, it only casts its shadow: catching its own would shade its front with the slightest error.
  box.receiveShadow = false;
  const sleeveGroup = new THREE.Group();
  sleeveGroup.add(box);
  s.scene.add(sleeveGroup);

  // Clicked, it turns over: a turn and a half, landing on whichever side it wasn't on, with a hop. A click on the
  // front's printed "Remix me" button opens the remix dialog instead. The button that turns it (for a keyboard) says which
  // way up it is.
  const button = host.querySelector<HTMLButtonElement>("[data-turn]");
  let spin = 0;
  let hop = 0;
  let back = false;
  const turn = () => {
    spin += Math.PI * 3;
    hop = 1;
    back = !back;
    button?.setAttribute("aria-pressed", String(back));
  };
  const onRemix = (found: ThreeTypes.Intersection | undefined) => {
    if (!found?.uv || found.face?.materialIndex !== 4) return false;
    const [x, y] = [found.uv.x * 800, (1 - found.uv.y) * 1448];
    const b = REMIX_BUTTON;
    return x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h;
  };
  s.on("click", (event) => {
    const found = s.hit(event, [box]);
    if (onRemix(found)) document.dispatchEvent(new CustomEvent("lamp:remix", { detail: sleeve.remix }));
    else if (found) turn();
  });
  s.on("pointermove", (event) => {
    const found = s.hit(event, [box]);
    s.hand(!!found);
    faces[4] = onRemix(found) ? frontPointed : front;
    box.material = faces;
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
      spun = ease(spun, spin, dt, reduced ? 12 : 3.2);
      hop = ease(hop, 0, dt, 2.5);
      sleeveGroup.rotation.set(rotation.x, rotation.y + spun, Math.sin(spun) * 0.12);
      sleeveGroup.position.y = (reduced ? 0 : Math.sin(time * 1.3) * 0.04) + Math.sin(hop * Math.PI) * 0.35;
    },
  );
}

// MARK: The shelf

const STACK_BLEED = { x: 0.12, y: 0.3 };

// The shelf: a stack of a few starters' tapes, each original with its remix under it, a little untidy, as a real
// stack is. The originals' spines carry their screenshots, so those are loaded up front; a tape's top, with the
// screenshot on its label, is drawn the first time it's chosen.
export async function mountStack(host: HTMLElement) {
  const tapes = JSON.parse(host.dataset.tapes!) as Tape[];
  const [THREE, spineShots] = await Promise.all([
    three(),
    Promise.all(tapes.map((tape) => (tape.look === "original" && tape.shot ? image(tape.shot) : Promise.resolve(undefined)))),
    fontsReady(),
  ]);
  const s = stage(THREE, host, { wall: -1.6, reach: 7, bleed: STACK_BLEED });
  if (!s) return;
  const [W, H, D, GAP] = [3.4, 0.46, 1.9, 0.06];
  const side = s.flat("#1f1d19");
  const back = s.flat("#2c2a25");
  const stack = new THREE.Group();
  s.scene.add(stack);

  const jitter = [0.1, -0.08, 0.14, -0.05, 0.06, -0.12, 0.03];
  const height = tapes.length * (H + GAP);
  const meshes = tapes.map((tape, i) => {
    const mesh = s.solid(new THREE.Mesh(new THREE.RoundedBoxGeometry(W, H, D, 3, 0.035), [
      side, side, back, back, s.texture(tapeSpine(tape, spineShots[i])), back,
    ]));
    const home = { x: jitter[i % jitter.length], y: height / 2 - H / 2 - i * (H + GAP), z: 0, rx: 0, ry: jitter[(i + 2) % jitter.length] * 0.3, rz: 0 };
    stack.add(mesh);
    // Turned about the upright first, so a tape tipped up to show its top still spins like a record, and turning it
    // back by the stack's own lean holds it square to the viewer.
    mesh.rotation.order = "YXZ";
    mesh.position.set(home.x, home.y, home.z);
    return { tape, mesh, home, now: { ...home }, spins: 0, drawn: false };
  });

  let chosen = -1;
  let hovered = -1;
  const choose = (i: number) => {
    if (chosen === i) {
      chosen = -1;
      return;
    }
    chosen = i;
    const tape = meshes[i];
    tape.spins += 1;
    if (!tape.drawn) {
      tape.drawn = true;
      const shot = tape.tape.shot;
      (shot ? image(shot) : Promise.resolve(undefined)).then((img) => {
        (tape.mesh.material as ThreeTypes.Material[])[2] = s.texture(tapeTop(tape.tape, img));
      });
    }
  };
  const which = (event: MouseEvent) => {
    const object = s.hit(event, meshes.map(({ mesh }) => mesh))?.object;
    return meshes.findIndex(({ mesh }) => mesh === object);
  };
  s.on("click", (event) => {
    const i = which(event);
    if (i >= 0) choose(i);
    else chosen = -1;
  });
  s.on("pointermove", (event) => {
    hovered = which(event);
    s.hand(hovered >= 0);
  });
  // For a keyboard, a button for each tape with a picture does what a click on the tape does.
  host.querySelectorAll<HTMLButtonElement>("[data-tape]").forEach((button) => {
    button.addEventListener("click", () => choose(Number(button.dataset.tape)));
  });

  let tilt = { x: 0, y: 0 };
  // How far in front of the stack a chosen tape is held.
  let held = 2.2;
  s.run(
    (aspect, tan) => {
      // The whole stack fits the host, and so does a chosen tape held up close in front of it, which may only rise
      // into the bleed above and below.
      const distance = Math.max((height + 0.4) / (2 * tan), 4.6 / (2 * tan * aspect));
      const near = Math.max(2.4 / (2 * tan * (1 + STACK_BLEED.y)), 4 / (2 * tan * aspect));
      held = Math.max(0, distance - near);
      s.camera.position.set(0, 0, distance);
    },
    (dt, time) => {
      const p = reduced ? { x: 0, y: 0 } : s.pointer;
      tilt = { x: ease(tilt.x, 0.14 + p.y * 0.18, dt, 4), y: ease(tilt.y, p.x * 0.32, dt, 4) };
      stack.rotation.set(tilt.x, tilt.y, 0);
      meshes.forEach((tape, i) => {
        const up = chosen === i;
        const near = hovered === i && !up;
        // Chosen, it flies out, spins once and shows its top; the rest sit back a little.
        const target = up
          ? { x: 0, y: 0.05 + (reduced ? 0 : Math.sin(time * 1.6) * 0.03), z: held, rx: Math.PI / 2 - 0.22 - tilt.x, ry: tape.spins * Math.PI * 2 - tilt.y, rz: -0.05 }
          : { ...tape.home, z: chosen >= 0 ? -0.3 : near ? 0.35 : 0, rx: near ? -0.12 : 0, ry: tape.home.ry + tape.spins * Math.PI * 2 };
        const speed = up ? 4.5 : 6;
        for (const key of ["x", "y", "z", "rx", "ry", "rz"] as const) tape.now[key] = ease(tape.now[key], target[key], dt, reduced ? 14 : speed);
        tape.mesh.position.set(tape.now.x, tape.now.y, tape.now.z);
        tape.mesh.rotation.set(tape.now.rx, tape.now.ry, tape.now.rz);
      });
    },
  );
}
