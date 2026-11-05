// "Lamplighter": the small game the homepage's chat adds when someone says they're bored, made the way Lamp's 2D game
// skills make one (Phaser 3.90, Arcade physics, art and sound made in code, moving by the time since the last frame). A
// lamplighter runs the rooftops of a dark town at night: one button jumps (held, higher), every lamppost touched comes
// on in one of the stripes' colors and lights the roof around it, posts lit one after another build a combo that climbs
// a scale, and a gap missed or a chimney hit ends the run. The town is made fresh as you run, a little faster all the
// time; the score is how much of it you lit.
//
// It's there to be changed while it's played: `set` gives a double jump, makes it rain, makes it faster or lights the
// whole street, and takes any of those back, without restarting the run or losing the score. Phaser loads only when
// the game first comes in (this module is imported on demand), keys reach it only while its board has focus, and it
// sleeps while it's out of sight.

import type * as PhaserTypes from "phaser";

export type Change = "double" | "rain" | "faster" | "lit";

const W = 960, H = 540;
const STRIPES = [0x1f8a4a, 0x7cbf3a, 0xf6b81c, 0xf08a1c, 0xe2402a, 0xd23778];
const NIGHT = 0x14131a, BUILDING = 0x26242b, EDGE = 0x3a3741, CREAM = 0xf2ecda;
const SCALE = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28];
const RUNNER_X = 280;

type Post = PhaserTypes.GameObjects.Container & { lit: boolean; passed: boolean; byStreet?: boolean; head: PhaserTypes.GameObjects.Image; pool: PhaserTypes.GameObjects.Image };

/** A few short sounds made in code, as the game skill says for effects nothing ready-made fits. */
function makeSound() {
  let audio: AudioContext | undefined;
  const tone = (freq: number, length: number, type: OscillatorType, volume: number, slide = 1, delay = 0) => {
    audio ??= new AudioContext();
    const now = audio.currentTime + delay;
    const osc = audio.createOscillator(), gain = audio.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, now);
    osc.frequency.exponentialRampToValueAtTime(freq * slide, now + length);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(volume, now + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + length);
    osc.connect(gain).connect(audio.destination);
    osc.start(now);
    osc.stop(now + length + 0.02);
  };
  return {
    light: (step: number) => tone(392 * 2 ** (SCALE[Math.min(step, SCALE.length - 1)] / 12), 0.22, "triangle", 0.16),
    jump: () => tone(330, 0.12, "sine", 0.06, 1.6),
    land: () => tone(120, 0.06, "sine", 0.05, 0.7),
    crash: () => { tone(180, 0.4, "sawtooth", 0.1, 0.3); tone(70, 0.5, "square", 0.05, 0.5); },
    street: () => [0, 4, 7, 12, 16, 19, 24].forEach((n, i) => tone(392 * 2 ** (n / 12), 0.3, "triangle", 0.1, 1, i * 0.07)),
    resume: () => audio?.resume(),
  };
}

export async function createGame(host: HTMLElement, status: HTMLElement) {
  const Phaser = (await import("phaser")).default;
  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const changes = new Set<Change>();
  const sound = makeSound();
  const best0 = (() => { try { return Number(localStorage.getItem("lamp-lamplighter-best")) || 0; } catch { return 0; } })();
  const state = { mode: "ready" as "ready" | "run" | "over", score: 0, lit: 0, combo: 0, best: best0, hue: 0 };

  class Run extends Phaser.Scene {
    runner!: PhaserTypes.Physics.Arcade.Sprite;
    roofs!: PhaserTypes.Physics.Arcade.StaticGroup;
    chimneys!: PhaserTypes.Physics.Arcade.StaticGroup;
    posts: Post[] = [];
    edge = 0;
    speed = 330;
    airJumps = 0;
    coyote = 0;
    buffer = 0;
    holding = false;
    held = 0;
    grounded = false;
    skyline!: PhaserTypes.GameObjects.TileSprite;
    stars!: PhaserTypes.GameObjects.TileSprite;
    rain!: PhaserTypes.GameObjects.Particles.ParticleEmitter;
    dust!: PhaserTypes.GameObjects.Particles.ParticleEmitter;
    sparks!: PhaserTypes.GameObjects.Particles.ParticleEmitter;
    hud!: PhaserTypes.GameObjects.Text;
    card!: PhaserTypes.GameObjects.Text;
    hint!: PhaserTypes.GameObjects.Text;
    sheen!: PhaserTypes.GameObjects.Rectangle;

    constructor() { super("run"); }

    preload() {
      // The art, made once in code.
      const g = this.make.graphics({ x: 0, y: 0 }, false);
      // The lamplighter: a body, a head and a cap, with a little lantern on a pole.
      g.fillStyle(CREAM); g.fillRoundedRect(8, 14, 16, 22, 5); g.fillCircle(16, 9, 7);
      g.fillStyle(0xe2402a); g.fillRoundedRect(8, 1, 16, 6, 3);
      g.fillStyle(CREAM); g.fillRect(24, 10, 3, 18); g.fillStyle(0xf6b81c); g.fillCircle(27, 9, 4);
      g.fillStyle(CREAM); g.fillRect(10, 36, 5, 8); g.fillRect(18, 36, 5, 8);
      g.generateTexture("runner", 32, 44); g.clear();
      // A lamppost, dark until it's lit, and its lamp.
      g.fillStyle(EDGE); g.fillRect(4, 10, 4, 70); g.fillRect(0, 78, 12, 4); g.fillRect(2, 6, 8, 6);
      g.generateTexture("post", 12, 82); g.clear();
      g.fillStyle(0xffffff); g.fillRoundedRect(0, 0, 18, 14, 4);
      g.generateTexture("lamp", 18, 14); g.clear();
      for (let r = 64; r > 0; r -= 4) { g.fillStyle(0xffffff, 0.04); g.fillCircle(64, 64, r); }
      g.generateTexture("glow", 128, 128); g.clear();
      g.fillStyle(0xffffff); g.fillCircle(3, 3, 3); g.generateTexture("dot", 6, 6); g.clear();
      g.fillStyle(0xffffff, 0.6); g.fillRect(0, 0, 2, 14); g.generateTexture("drop", 2, 14); g.clear();
      // A building's windows, a few warm, most dark.
      g.fillStyle(BUILDING); g.fillRect(0, 0, 64, 64);
      g.fillStyle(0x34313a); g.fillRect(10, 12, 14, 18); g.fillRect(40, 12, 14, 18); g.fillRect(10, 40, 14, 18);
      g.fillStyle(0x5a4a2a); g.fillRect(40, 40, 14, 18);
      g.generateTexture("windows", 64, 64); g.clear();
      // A far skyline and stars, to move slower behind the roofs.
      g.fillStyle(0x1c1b23);
      for (let x = 0; x < 512; x += 64) { const h = 60 + ((x * 37) % 90); g.fillRect(x, 200 - h, 56, h); }
      g.generateTexture("skyline", 512, 200); g.clear();
      g.fillStyle(0xffffff, 0.7);
      for (let i = 0; i < 40; i++) g.fillCircle((i * 97) % 512, (i * 53) % 200, i % 3 === 0 ? 1.5 : 1);
      g.generateTexture("stars", 512, 200); g.clear();
      g.fillStyle(EDGE); g.fillRect(0, 0, 30, 36); g.fillStyle(0x4a4652); g.fillRect(-2, 0, 34, 6);
      g.generateTexture("chimney", 30, 36); g.destroy();
    }

    create() {
      this.cameras.main.setBackgroundColor(NIGHT);
      this.stars = this.add.tileSprite(0, 0, W, 200, "stars").setOrigin(0).setScrollFactor(0);
      this.skyline = this.add.tileSprite(0, H - 330, W, 200, "skyline").setOrigin(0).setScrollFactor(0);
      this.roofs = this.physics.add.staticGroup();
      this.chimneys = this.physics.add.staticGroup();
      this.runner = this.physics.add.sprite(RUNNER_X, 300, "runner").setDepth(5);
      (this.runner.body as PhaserTypes.Physics.Arcade.Body).setSize(18, 40).setOffset(7, 4);
      this.physics.add.collider(this.runner, this.roofs);
      this.physics.add.overlap(this.runner, this.chimneys, () => this.crash());
      this.dust = this.add.particles(0, 0, "dot", { speed: { min: 20, max: 90 }, angle: { min: 180, max: 360 }, lifespan: 400, scale: { start: 1, end: 0 }, alpha: { start: 0.5, end: 0 }, tint: 0x8a8594, emitting: false });
      this.sparks = this.add.particles(0, 0, "dot", { speed: { min: 80, max: 260 }, lifespan: 700, scale: { start: 1.6, end: 0 }, gravityY: 300, blendMode: "ADD", emitting: false }).setDepth(6);
      this.rain = this.add.particles(0, -20, "drop", { x: { min: 0, max: W + 200 }, speedY: { min: 700, max: 900 }, speedX: -160, lifespan: 900, quantity: 3, frequency: 16, alpha: { start: 0.5, end: 0.2 }, emitting: false }).setScrollFactor(0).setDepth(7);
      this.sheen = this.add.rectangle(0, 0, W, H, 0x6a7a9a, 0).setOrigin(0).setScrollFactor(0).setDepth(8);
      const type = { fontFamily: "ui-monospace, Menlo, monospace", fontSize: "20px", color: "#f2ecda" };
      this.hud = this.add.text(24, 20, "", type).setScrollFactor(0).setDepth(9);
      this.card = this.add.text(W / 2, H / 2 - 70, "", { fontFamily: "Inter Tight, Helvetica, sans-serif", fontSize: "56px", fontStyle: "900", color: "#f2ecda", align: "center" }).setOrigin(0.5).setScrollFactor(0).setDepth(9);
      this.hint = this.add.text(W / 2, H / 2 + 10, "", { ...type, fontSize: "18px", align: "center" }).setOrigin(0.5).setScrollFactor(0).setDepth(9);

      // One button: Space, Up or W, a click or a tap. Held, the jump goes higher.
      const press = () => { sound.resume(); if (state.mode !== "run") this.start(); else { this.buffer = 0.12; this.holding = true; } };
      const release = () => { this.holding = false; };
      const kb = this.input.keyboard!;
      for (const key of ["SPACE", "UP", "W"]) { kb.addCapture(key); kb.on(`keydown-${key}`, (e: KeyboardEvent) => { if (!e.repeat) press(); }); kb.on(`keyup-${key}`, release); }
      this.input.on("pointerdown", () => { host.focus({ preventScroll: true }); press(); });
      this.input.on("pointerup", release);
      this.build();
      this.paint();
      this.say();
    }

    /** The first stretch of roofs, with the runner standing on the first. */
    build() {
      this.roofs.clear(true, true);
      this.chimneys.clear(true, true);
      this.posts.forEach((post) => post.destroy());
      this.posts = [];
      this.edge = 0;
      this.speed = 330;
      this.runner.setPosition(RUNNER_X, 300).setVelocity(0, 0).setAngle(0).setAlpha(1);
      this.roof(0, 900, 400, true);
      while (this.edge < W * 2) this.next();
      this.cameras.main.scrollX = 0;
    }

    /** A building: its walls, its windows, its roof to land on, and what's on it. */
    roof(x: number, width: number, top: number, safe = false) {
      const wall = this.add.tileSprite(x, top, width, H - top, "windows").setOrigin(0);
      const rim = this.add.rectangle(x + width / 2, top, width, 8, EDGE).setDepth(1);
      this.roofs.add(rim);
      (rim.body as PhaserTypes.Physics.Arcade.StaticBody).updateFromGameObject();
      rim.setData("wall", wall);
      // Lampposts every so often, and, further on, a chimney between them.
      for (let at = x + 120; at < x + width - 60; at += Phaser.Math.Between(170, 260)) this.post(at, top);
      if (!safe && width > 320 && Math.random() < Math.min(0.75, 0.25 + this.edge / 20000)) {
        const cx = x + Phaser.Math.Between(150, width - 120);
        const chimney = this.chimneys.create(cx, top - 18, "chimney") as PhaserTypes.Physics.Arcade.Sprite;
        (chimney.body as PhaserTypes.Physics.Arcade.StaticBody).setSize(24, 32).updateFromGameObject();
      }
      this.edge = x + width;
    }

    post(x: number, top: number) {
      const pole = this.add.image(0, -41, "post");
      const head = this.add.image(0, -78, "lamp").setTint(0x4a4652);
      const pool = this.add.image(0, -60, "glow").setScale(2.4, 1.8).setBlendMode("ADD").setAlpha(0);
      const post = this.add.container(x, top - 4, [pool, pole, head]).setDepth(2) as Post;
      Object.assign(post, { lit: false, passed: false, head, pool });
      this.posts.push(post);
      if (changes.has("lit")) this.light(post, false);
    }

    /** The next building: a gap a jump can clear at this speed, then a roof a little higher or lower. */
    next() {
      const reach = this.speed * (changes.has("double") ? 0.8 : 0.62);
      const gap = Phaser.Math.Between(70, Math.max(90, Math.min(260, reach)));
      const last = (this.roofs.getChildren().at(-1) as PhaserTypes.GameObjects.Rectangle | undefined)?.y ?? 400;
      const top = Phaser.Math.Clamp(last + Phaser.Math.Between(-70, 70), 300, 460);
      this.roof(this.edge + gap, Phaser.Math.Between(260, 620), top);
    }

    light(post: Post, scored = true) {
      if (post.lit) return;
      post.lit = true;
      post.byStreet = !scored;
      const color = STRIPES[state.hue++ % STRIPES.length];
      post.head.setTint(color);
      post.pool.setTint(color);
      this.tweens.add({ targets: post.pool, alpha: 0.85, duration: 260, ease: "Cubic.Out" });
      this.tweens.add({ targets: post.head, scale: { from: 1.8, to: 1 }, duration: 300, ease: "Back.Out" });
      if (!scored) return;
      state.combo += 1;
      state.lit += 1;
      state.score += state.combo;
      this.sparks.setParticleTint(color);
      this.sparks.explode(calm ? 6 : 16, post.x, post.y - 78);
      sound.light(state.combo - 1);
      if (state.combo > 1) this.pop(post.x, post.y - 110, `×${state.combo}`, color);
      this.say();
    }

    pop(x: number, y: number, words: string, color: number) {
      const t = this.add.text(x, y, words, { fontFamily: "Inter Tight, Helvetica, sans-serif", fontSize: "26px", fontStyle: "900", color: `#${color.toString(16).padStart(6, "0")}` }).setOrigin(0.5).setDepth(9);
      this.tweens.add({ targets: t, y: y - 50, alpha: 0, duration: 650, ease: "Cubic.Out", onComplete: () => t.destroy() });
    }

    start() {
      if (state.mode === "over") Object.assign(state, { score: 0, lit: 0, combo: 0 });
      if (state.mode === "over") this.build();
      state.mode = "run";
      this.say();
    }

    crash() {
      if (state.mode !== "run") return;
      state.mode = "over";
      state.best = Math.max(state.best, state.score);
      try { localStorage.setItem("lamp-lamplighter-best", String(state.best)); } catch { /* fine without it */ }
      sound.crash();
      if (!calm) this.cameras.main.shake(220, 0.01);
      this.runner.setVelocity(-120, -420);
      this.tweens.add({ targets: this.runner, angle: -200, duration: 700 });
      this.say();
    }

    /** What the rain and the lit street look like now. */
    paint() {
      const rain = changes.has("rain");
      this.rain.emitting = rain && !calm;
      this.sheen.setAlpha(rain ? 0.12 : 0);
      if (changes.has("lit")) {
        let delay = 0;
        for (const post of this.posts) if (!post.lit) { this.time.delayedCall(delay, () => this.light(post, false)); delay += 40; }
        sound.street();
      } else {
        // Taken back: the lamps the street lit go dark again; the ones the runner lit stay lit.
        for (const post of this.posts) if (post.byStreet) {
          post.lit = false; post.byStreet = false;
          post.head.setTint(0x4a4652);
          this.tweens.add({ targets: post.pool, alpha: 0, duration: 200 });
        }
      }
    }

    say() {
      const extras = [changes.has("double") && "double jump", changes.has("faster") && "faster"].filter(Boolean).join(" · ");
      this.hud.setText(`${state.score}   ${state.combo > 1 ? `combo ×${state.combo}   ` : ""}best ${state.best}${extras ? `   ${extras}` : ""}`);
      this.card.setVisible(state.mode !== "run").setText(state.mode === "over" ? `${state.score}` : "Lamplighter");
      this.hint.setVisible(state.mode !== "run").setText(state.mode === "over"
        ? `${state.lit} lamps lit · best ${state.best}\npress Space or tap to run again`
        : "Run the rooftops and jump to light every lamp.\nSpace or tap to jump, hold to jump higher.");
      status.textContent = state.mode === "run" ? `${state.score} points · ${state.lit} lamps lit`
        : state.mode === "over" ? `${state.score} points · best ${state.best} · Space or tap to run again` : "Space or tap to jump · hold for higher";
    }

    update(_time: number, delta: number) {
      const dt = Math.min(0.05, delta / 1000);
      const body = this.runner.body as PhaserTypes.Physics.Arcade.Body;
      const cam = this.cameras.main;
      this.stars.tilePositionX = cam.scrollX * 0.05;
      this.skyline.tilePositionX = cam.scrollX * 0.25;
      if (state.mode !== "run") {
        if (state.mode === "ready") body.setVelocityX(0);
        return;
      }
      this.speed = Math.min(640, this.speed + dt * 6);
      body.setVelocityX(this.speed * (changes.has("faster") ? 1.35 : 1));
      cam.scrollX = this.runner.x - RUNNER_X;

      // Jumping: a moment's grace after a roof's edge, a press just before landing kept, a held jump going higher, and
      // a second jump in the air once it's been asked for.
      const wasGrounded = this.grounded;
      this.grounded = body.blocked.down;
      if (this.grounded) { this.coyote = 0.1; this.airJumps = changes.has("double") ? 1 : 0; } else this.coyote -= dt;
      if (this.grounded && !wasGrounded) {
        this.dust.explode(calm ? 2 : 6, this.runner.x, this.runner.y + 22);
        this.tweens.add({ targets: this.runner, scaleY: 0.78, scaleX: 1.18, duration: 70, yoyo: true });
        sound.land();
      }
      this.buffer -= dt;
      if (this.buffer > 0 && (this.coyote > 0 || this.airJumps > 0)) {
        if (this.coyote <= 0) this.airJumps -= 1;
        body.setVelocityY(-700);
        this.buffer = 0; this.coyote = 0; this.held = 0;
        this.tweens.add({ targets: this.runner, scaleY: 1.2, scaleX: 0.85, duration: 90, yoyo: true });
        sound.jump();
      }
      if (this.holding && body.velocity.y < 0 && this.held < 0.22) { this.held += dt; body.velocity.y -= 1500 * dt; }
      this.runner.setAngle(this.grounded ? Math.sin(this.time.now / 60) * 4 : Phaser.Math.Clamp(body.velocity.y / 60, -10, 10));

      // Lamps sit just above a running head, so each one is a jump: touched, it's lit; passed in the dark, the combo's
      // gone.
      for (const post of this.posts) {
        if (!post.lit && Math.abs(post.x - this.runner.x) < 26 && this.runner.y - 20 < post.y - 70) this.light(post);
        if (!post.passed && post.x < this.runner.x - 30) { post.passed = true; if (!post.lit) { state.combo = 0; this.say(); } }
      }
      // The town goes on ahead and is let go behind.
      while (this.edge < cam.scrollX + W * 2) this.next();
      for (const roof of this.roofs.getChildren() as PhaserTypes.GameObjects.Rectangle[]) {
        if (roof.x + roof.width / 2 < cam.scrollX - 100) { (roof.getData("wall") as PhaserTypes.GameObjects.TileSprite).destroy(); roof.destroy(); }
      }
      this.posts = this.posts.filter((post) => (post.x < cam.scrollX - 100 ? (post.destroy(), false) : true));
      for (const chimney of this.chimneys.getChildren() as PhaserTypes.GameObjects.Sprite[]) if (chimney.x < cam.scrollX - 100) chimney.destroy();
      if (this.runner.y > H + 60) this.crash();
    }
  }

  const game = new Phaser.Game({
    type: Phaser.AUTO, parent: host, width: W, height: H, backgroundColor: "#14131a",
    physics: { default: "arcade", arcade: { gravity: { x: 0, y: 2000 } } },
    scale: { mode: Phaser.Scale.FIT, autoCenter: Phaser.Scale.CENTER_HORIZONTALLY },
    // Keys reach the game only while its board has focus, so typing in the chat or scrolling the page is never caught.
    input: { keyboard: { target: host } },
    scene: [Run], audio: { noAudio: true }, banner: false,
  });
  const scene = () => game.scene.getScene("run") as Run | null;

  // Asleep while out of sight, and picked up again where it was.
  new IntersectionObserver(([entry]) => { if (entry.isIntersecting) game.loop.wake(); else game.loop.sleep(); }).observe(host);

  return {
    /** A change made, or taken back, while it plays: no restart, the score kept. */
    set(change: Change, on: boolean) {
      if (on) changes.add(change); else changes.delete(change);
      scene()?.paint();
      scene()?.say();
    },
  };
}
