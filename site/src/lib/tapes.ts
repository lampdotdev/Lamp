// The homepage's tapes in 3D (index.astro): New York's sleeve in the hero, and the stack of tapes beside "Record
// over it". They lean toward the pointer, and turn over when clicked to show what's on them: a screenshot on the
// tape's label. Every picture on them is drawn here on a 2D canvas in the page's own fonts, so they print like the
// rest of the page. The page's HTML version of each stays under the canvas, for anyone without WebGL and for
// screen readers; the canvas only takes over once it's drawn.

import type * as ThreeTypes from "three";

type Three = typeof ThreeTypes;

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

/** The hero's sleeve. */
export type Sleeve = { title: string; by: string; kind: string; line: string; shot: string; tweaks: string[] };

const INK = "#1b1a17";
const PAPER = "#f2ecda";
const LABEL = "#f7f2e3";
const PLASTIC = "#26241f";
const RED = "#a8361f";
const MAGENTA = "#b8264f";
const WARM = ["#f6b81c", "#f08a1c", "#e2402a", "#d23778", "#5a2d8c"];
const COOL = ["#1f8a4a", "#1f6fc4", "#e2402a"];
const ALL = ["#f6b81c", "#f08a1c", "#e2402a", "#d23778", "#5a2d8c", "#2c3592", "#1f6fc4", "#1f8a4a"];

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

/** A screenshot filling a box, cropped to it, with what a remix did to it. */
function shot(ctx: CanvasRenderingContext2D, img: HTMLImageElement | undefined, x: number, y: number, w: number, h: number, treat?: Tape["treat"]) {
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
    const scale = Math.max(bw / img.width, bh / img.height);
    const dw = img.width * scale;
    const dh = img.height * scale;
    ctx.drawImage(img, bx + (bw - dw) / 2, by + (bh - dh) / 2, dw, dh);
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

// The sleeve's front, back and spine, at 800 pixels to its 1.05 units of width.
function sleeveFront(sleeve: Sleeve) {
  const { canvas, ctx } = sheet(800, 1448);
  ctx.fillStyle = LABEL;
  ctx.fillRect(0, 0, 800, 1448);
  ctx.fillStyle = INK;
  font(ctx, "italic 800", 54, SANS);
  ctx.fillText(sleeve.by, 60, 140);
  font(ctx, "900", 170, SANS, sleeve.title, 680);
  ctx.fillText(sleeve.title, 52, 300);
  ctx.fillStyle = RED;
  font(ctx, "700", 30, MONO);
  ctx.textAlign = "right";
  ctx.fillText(sleeve.kind.toUpperCase(), 740, 90);
  ctx.textAlign = "left";
  font(ctx, "700", 30, MONO);
  ctx.fillText("T‑120 · HI‑FI", 60, 420);
  ctx.fillStyle = "#2a6fb0";
  ctx.font = `52px ${MARKER}`;
  ctx.save();
  ctx.translate(60, 560);
  ctx.rotate(-0.05);
  ctx.fillText("turn me over →", 0, 0);
  ctx.restore();
  bands(ctx, WARM, 0, 700, 800, 450);
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.moveTo(800, 640);
  ctx.lineTo(800, 1210);
  ctx.lineTo(470, 925);
  ctx.fill();
  font(ctx, "italic 800", 46, SANS, sleeve.line, 680);
  ctx.fillText(sleeve.line, 60, 1280);
  ctx.fillStyle = MAGENTA;
  ctx.save();
  ctx.translate(450, 1385);
  ctx.rotate(-0.06);
  ctx.font = `56px ${MARKER}`;
  ctx.fillText("remix me!", 0, 0);
  ctx.restore();
  return canvas;
}

function sleeveBack(sleeve: Sleeve, img: HTMLImageElement | undefined) {
  const { canvas, ctx } = sheet(800, 1448);
  ctx.fillStyle = LABEL;
  ctx.fillRect(0, 0, 800, 1448);
  ctx.fillStyle = RED;
  font(ctx, "700", 30, MONO);
  ctx.fillText("SIDE B · REMIX ME", 60, 110);
  ctx.fillStyle = INK;
  ctx.fillRect(56, 156, 688, 438);
  shot(ctx, img, 64, 164, 672, 422);
  font(ctx, "900", 96, SANS, sleeve.title, 680);
  ctx.fillText(sleeve.title, 56, 730);
  font(ctx, "italic 800", 44, SANS);
  ctx.fillText(`by ${sleeve.by.replace(/^Made by /, "")}`, 60, 792);
  const inks = [MAGENTA, "#2a6fb0", "#1f7a42"];
  sleeve.tweaks.forEach((tweak, i) => {
    ctx.fillStyle = inks[i % inks.length];
    ctx.save();
    ctx.translate(60, 900 + i * 92);
    ctx.rotate(i % 2 ? 0.02 : -0.025);
    font(ctx, "", 50, MARKER, tweak, 680);
    ctx.fillText(tweak, 0, 0);
    ctx.restore();
  });
  bands(ctx, ALL, 0, 1240, 800, 208);
  return canvas;
}

function sleeveSpine(sleeve: Sleeve) {
  const { canvas, ctx } = sheet(220, 1448);
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
function tapeSpine(tape: Tape) {
  const { canvas, ctx } = sheet(1480, 200);
  const printed = tape.look === "original" && tape.stripes !== "cool";
  ctx.fillStyle = printed ? LABEL : PLASTIC;
  ctx.fillRect(0, 0, 1480, 200);
  if (printed) {
    bands(ctx, WARM, 0, 0, 440, 200, true);
    ctx.fillStyle = INK;
    font(ctx, "900", 92, SANS, tape.title, 900);
    ctx.fillText(tape.title, 490, 112);
    font(ctx, "700", 28, SANS, tape.caption, 900);
    ctx.fillText(tape.caption, 494, 160);
  } else if (tape.look === "original") {
    bands(ctx, COOL, 60, 40, 260, 120);
    ctx.fillStyle = PAPER;
    font(ctx, "900", 78, SANS, tape.title.toUpperCase(), 900);
    ctx.fillText(tape.title.toUpperCase(), 360, 112);
    ctx.fillStyle = "#cfc8b2";
    font(ctx, "700", 26, SANS, tape.caption, 900);
    ctx.fillText(tape.caption, 362, 156);
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
  } else if (tape.side) {
    tag(ctx, tape.side, 1450, 100);
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

function stage(THREE: Three, host: HTMLElement) {
  let renderer: ThreeTypes.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  } catch {
    return undefined;
  }
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  const canvas = renderer.domElement;
  canvas.setAttribute("aria-hidden", "true");
  canvas.className = "tape-canvas";
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 100);
  const anisotropy = renderer.capabilities.getMaxAnisotropy();
  const texture = (source: HTMLCanvasElement) => {
    const map = new THREE.CanvasTexture(source);
    map.colorSpace = THREE.SRGBColorSpace;
    map.anisotropy = anisotropy;
    return new THREE.MeshBasicMaterial({ map });
  };
  const flat = (color: string) => new THREE.MeshBasicMaterial({ color });

  // Where the pointer is, from -1 to 1 across the host's own box.
  const pointer = { x: 0, y: 0 };
  addEventListener("pointermove", (event) => {
    const box = host.getBoundingClientRect();
    pointer.x = Math.max(-1, Math.min(1, ((event.clientX - box.left) / box.width) * 2 - 1));
    pointer.y = Math.max(-1, Math.min(1, ((event.clientY - box.top) / box.height) * 2 - 1));
  }, { passive: true });

  const raycaster = new THREE.Raycaster();
  const hit = (event: PointerEvent | MouseEvent, objects: ThreeTypes.Object3D[]) => {
    const box = canvas.getBoundingClientRect();
    const ndc = new THREE.Vector2(((event.clientX - box.left) / box.width) * 2 - 1, -((event.clientY - box.top) / box.height) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    return raycaster.intersectObjects(objects, true)[0]?.object;
  };

  const run = (fit: (aspect: number) => void, frame: (dt: number, time: number) => void) => {
    const resize = () => {
      const { width, height } = host.getBoundingClientRect();
      if (!width || !height) return;
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      fit(camera.aspect);
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

  return { THREE, scene, camera, canvas, texture, flat, pointer, hit, run };
}

/** Eases `value` toward `target`, by how long the frame took. */
const ease = (value: number, target: number, dt: number, speed = 7) => value + (target - value) * (1 - Math.exp(-dt * speed));

// MARK: The hero's sleeve

export async function mountSleeve(host: HTMLElement) {
  const sleeve = JSON.parse(host.dataset.sleeve!) as Sleeve;
  const [THREE, img] = await Promise.all([import("three"), image(sleeve.shot), fontsReady()]);
  const s = stage(THREE, host);
  if (!s) return;
  const spine = s.texture(sleeveSpine(sleeve));
  const box = new THREE.Mesh(new THREE.BoxGeometry(1.05, 1.9, 0.3), [
    spine, spine, s.flat(INK), s.flat(INK), s.texture(sleeveFront(sleeve)), s.texture(sleeveBack(sleeve, img)),
  ]);
  const sleeveGroup = new THREE.Group();
  sleeveGroup.add(box);
  s.scene.add(sleeveGroup);

  // A soft shadow on the stripes under it.
  const { canvas: blob, ctx } = sheet(256, 256);
  const glow = ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
  glow.addColorStop(0, "rgb(20 12 40 / 0.45)");
  glow.addColorStop(1, "rgb(20 12 40 / 0)");
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, 256, 256);
  const shadowMap = new THREE.CanvasTexture(blob);
  const shadow = new THREE.Mesh(new THREE.PlaneGeometry(1.8, 0.5), new THREE.MeshBasicMaterial({ map: shadowMap, transparent: true, depthWrite: false }));
  shadow.position.set(0, -1.12, 0);
  shadow.rotation.x = -Math.PI / 2.4;
  s.scene.add(shadow);

  // Clicked, it turns over: a turn and a half, landing on whichever side it wasn't on, with a hop.
  let spin = 0;
  let hop = 0;
  const turn = () => {
    spin += Math.PI * 3;
    hop = 1;
  };
  s.canvas.addEventListener("click", (event) => { if (s.hit(event, [box])) turn(); });
  s.canvas.addEventListener("pointermove", (event) => { s.canvas.style.cursor = s.hit(event, [box]) ? "pointer" : ""; });
  host.querySelector<HTMLButtonElement>("[data-turn]")?.addEventListener("click", turn);

  let rotation = { x: 0, y: -0.35 };
  let spun = 0;
  s.run(
    (aspect) => {
      const tan = Math.tan((s.camera.fov * Math.PI) / 360);
      s.camera.position.set(0, 0, Math.max(2.5 / (2 * tan), 1.7 / (2 * tan * aspect)));
    },
    (dt, time) => {
      const tilt = reduced ? { x: 0, y: 0 } : s.pointer;
      rotation = { x: ease(rotation.x, 0.06 + tilt.y * 0.3, dt, 5), y: ease(rotation.y, -0.35 + tilt.x * 0.6, dt, 5) };
      spun = ease(spun, spin, dt, reduced ? 12 : 3.2);
      hop = ease(hop, 0, dt, 2.5);
      sleeveGroup.rotation.set(rotation.x, rotation.y + spun, Math.sin(spun) * 0.12);
      sleeveGroup.position.y = (reduced ? 0 : Math.sin(time * 1.3) * 0.04) + Math.sin(hop * Math.PI) * 0.35;
      shadow.scale.setScalar(1 - Math.sin(hop * Math.PI) * 0.3);
    },
  );
}

// MARK: The stack

export async function mountStack(host: HTMLElement) {
  const tapes = JSON.parse(host.dataset.tapes!) as Tape[];
  const [THREE, shots] = await Promise.all([
    import("three"),
    Promise.all(tapes.map((tape) => (tape.shot ? image(tape.shot) : Promise.resolve(undefined)))),
    fontsReady(),
  ]);
  const s = stage(THREE, host);
  if (!s) return;
  const [W, H, D, GAP] = [3.4, 0.46, 1.9, 0.07];
  const side = s.flat("#1f1d19");
  const back = s.flat("#2c2a25");
  const stack = new THREE.Group();
  s.scene.add(stack);

  // A little untidy, as a real stack is.
  const jitter = [0.1, -0.08, 0.14, -0.05, 0.06];
  const meshes = tapes.map((tape, i) => {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(W, H, D), [
      side, side, s.texture(tapeTop(tape, shots[i])), back, s.texture(tapeSpine(tape)), back,
    ]);
    const home = { x: jitter[i % jitter.length], y: ((tapes.length - 1) / 2 - i) * (H + GAP), z: 0, rx: 0, ry: jitter[(i + 2) % jitter.length] * 0.3, rz: 0 };
    stack.add(mesh);
    mesh.position.set(home.x, home.y, home.z);
    return { mesh, home, now: { ...home }, spins: 0 };
  });

  let chosen = -1;
  let hovered = -1;
  const choose = (i: number) => {
    if (chosen === i) chosen = -1;
    else {
      chosen = i;
      meshes[i].spins += 1;
    }
  };
  const which = (event: MouseEvent) => meshes.findIndex(({ mesh }) => mesh === s.hit(event, meshes.map(({ mesh }) => mesh)));
  s.canvas.addEventListener("click", (event) => {
    const i = which(event);
    if (i >= 0) choose(i);
    else chosen = -1;
  });
  s.canvas.addEventListener("pointermove", (event) => {
    hovered = which(event);
    s.canvas.style.cursor = hovered >= 0 ? "pointer" : "";
  });
  s.canvas.addEventListener("pointerleave", () => { hovered = -1; });
  host.querySelectorAll<HTMLButtonElement>("[data-tape]").forEach((button) => {
    button.addEventListener("click", () => choose(Number(button.dataset.tape)));
  });

  let tilt = { x: 0, y: 0 };
  s.run(
    (aspect) => {
      const tan = Math.tan((s.camera.fov * Math.PI) / 360);
      // The whole stack, and a chosen tape held up close in front of it, both fit.
      s.camera.position.set(0, 0, Math.max(3.4 / (2 * tan), 4.4 / (2 * tan * aspect), 2.2 + 2.3 / (2 * tan), 2.2 + 3.9 / (2 * tan * aspect)));
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
          ? { x: 0, y: 0.05 + (reduced ? 0 : Math.sin(time * 1.6) * 0.03), z: 2.2, rx: Math.PI / 2 - 0.22 - tilt.x, ry: tape.spins * Math.PI * 2 - tilt.y, rz: -0.05 }
          : { ...tape.home, z: chosen >= 0 ? -0.3 : near ? 0.35 : 0, rx: near ? -0.12 : 0, ry: tape.home.ry + tape.spins * Math.PI * 2 };
        const speed = up ? 4.5 : 6;
        for (const key of ["x", "y", "z", "rx", "ry", "rz"] as const) tape.now[key] = ease(tape.now[key], target[key], dt, reduced ? 14 : speed);
        tape.mesh.position.set(tape.now.x, tape.now.y, tape.now.z);
        tape.mesh.rotation.set(tape.now.rx, tape.now.ry, tape.now.rz);
      });
    },
  );
}
