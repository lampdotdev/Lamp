// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { DIFFICULTY } from "./sim/ai/commander.js";
import { MAPS, isKnownMapId, mapById } from "./sim/maps.js";
import { BIOMES, RANDOM_MAP_SIZE, RANDOM_PREFIX, isRandomMapId, parseRandomMapId, randomMapId, rollRandomMapId, seedCode, seedFromText } from "./sim/mapgen.js";
import { sfx } from "./game/audio.js";
import { music } from "./game/music.js";
import { loadTerrainArt, mapThumbUrl } from "./game/assets.js";
import { GameScene } from "./game/GameScene.js";
import { gameMode, loadSettings, saveSettings, unchartedMatch } from "./game/mode.js";
import { loadBest } from "./game/survival.js";
import { HELP_HTML } from "./ui/hud.js";
import { mountMenuCareer, openSheet, starsText } from "./ui/career.js";
import { dailyOp, today } from "./game/daily.js";
import { opById } from "./sim/ops.js";
import { mountMenuOps } from "./ui/ops.js";
import { fullscreen, resetAudioSession } from "./ui/fullscreen.js";
import { scrollCue } from "./ui/hscroll.js";
import { showReplayPicker } from "./ui/replay-picker.js";
import { openMapPreview } from "./ui/map-preview.js";
import { aiStrategy } from "./game/meta.js";
import { game, pendingRestore } from "../lamp-game.js";
import { makeRenderer } from "./game/three/stage.js";
import { frame as padFrame } from "./lamp/pads.js";
import { frame as partyFrame, matchStarted, openLobby, partySnapshot, restoreParty, seatsFor } from "./lamp/party.js";

document.addEventListener("contextmenu", (e) => e.preventDefault());

// iOS Safari ignores user-scalable=no: pinch zooms the PAGE (scaling the
// HUD with it) and offers no way back. Kill browser zoom at the source —
// the game camera handles all zooming.
for (const type of ["gesturestart", "gesturechange", "gestureend"])
    document.addEventListener(type, (e) => e.preventDefault(), { passive: false });
document.addEventListener("touchmove", (e) => {
    // (only iOS has a pinch scale; elsewhere it's undefined, and an uncancelable
    // move — a scroll already under way — just logs an intervention)
    const scale = e.scale;
    if (e.cancelable && typeof scale === "number" && scale !== 1)
        e.preventDefault();
}, { passive: false });
document.addEventListener("dblclick", (e) => e.preventDefault(), { passive: false });

// Safety net: if browser page-zoom happens anyway (iOS finds ways), show a
// rescue button pinned inside the VISUAL viewport (fixed-position elements
// live in the layout viewport and can be off-screen while zoomed).
function setupPageZoomRescue() {
    const vv = window.visualViewport;
    if (!vv)
        return;
    const btn = document.createElement("button");
    btn.id = "unzoom";
    btn.textContent = "⤺ Zoom back out";
    btn.hidden = true;
    document.body.appendChild(btn);

    const place = () => {
        const zoomed = vv.scale > 1.05;
        btn.hidden = !zoomed;
        if (!zoomed)
            return;
        const s = 1 / vv.scale;
        btn.style.left = `${vv.offsetLeft}px`;
        btn.style.top = `${vv.offsetTop + vv.height - 56 * s}px`;
        btn.style.width = `${vv.width}px`;
        btn.style.height = `${56 * s}px`;
        btn.style.fontSize = `${17 * s}px`;
    };
    vv.addEventListener("resize", place);
    vv.addEventListener("scroll", place);
    place();

    btn.addEventListener("click", () => {
        // rewriting the viewport meta forces Safari to re-clamp scale to 1
        const meta = document.querySelector("meta[name=viewport]");
        if (!meta)
            return;
        const content = meta.content;
        meta.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0";
        requestAnimationFrame(() => {
            meta.content = content;
            place();
        });
    });
}
setupPageZoomRescue();
// iOS's audio session back to "auto" before any audio context exists, on every boot: a sound duel's page that
// went without letting it go (its rig sets play-and-record) left it so for this one, as Safari keeps the type
// in the tab while this page reads "auto" (ui/fullscreen.ts resetAudioSession). A context made under it can
// take a low rate (src/link/rig.ts "The rate"); the rig sets play-and-record again only after making its own.
resetAudioSession();
const REMATCH_KEY = "battledrones.rematch";

/** Render at device resolution (capped at 2× for phone GPUs) for crisp art. */
const dpr = () => Math.min(2, Math.max(1, window.devicePixelRatio || 1));

/** The match being played, which Lamp's runtime runs each frame; null in the menus. */
let scene = null;

/** `resume`: a match opened again after a change of the game's code, from Lamp's snapshot. */
async function startGame(feed, resume = null) {
    const hud = document.getElementById("hud");
    const loading = document.createElement("div");
    loading.id = "loading";
    loading.className = "screen";
    const def = mapById(gameMode.mapId);
    // (Uncharted: not even the name gives the map away)
    const where = unchartedMatch() ? "uncharted territory" : def.id === gameMode.mapId ? def.name : "battlefield";
    loading.innerHTML = `<div class="loadbox"><p>Deploying to ${where}…</p><div class="loadtrack"><div id="loadbar"></div></div></div>`;
    hud.appendChild(loading);
    const bar = loading.querySelector("#loadbar");
    // the painted terrain is draped over the 3D landscape; a failed chunk falls back to flat colours
    const art = await loadTerrainArt(def.id, def.size, def.biome, (k) => {
        if (bar)
            bar.style.width = `${Math.round(k * 90)}%`;
    });
    if (bar)
        bar.style.width = "100%";
    // (let the full bar paint before the scene build blocks the main thread)
    await new Promise((r) => requestAnimationFrame(() => setTimeout(r, 0)));
    scene = new GameScene(document.getElementById("game"), dpr(), art, feed, { resume, seats: seatsFor() });
    matchStarted(scene);
    window.addEventListener("resize", () => scene.resize());
    window.addEventListener("orientationchange", () => setTimeout(() => scene.resize(), 200));
}

// ------------------------------------------------------------ random maps ---

const BIOME_ICON = { temperate: "🌳", desert: "🏜️", arctic: "❄️", volcanic: "🌋", tropical: "🌴" };
const RANDOM_KEY = "battledrones.randommaps";
/** A transparent pixel: the Uncharted card keeps its image box (the fog sits on it) with nothing of the map in it. */
const BLANK_IMG = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";
const RECENT_MAX = 6;

function loadRandomPrefs() {
    const prefs = { biome: null, recent: [] };
    try {
        const s = JSON.parse(localStorage.getItem(RANDOM_KEY) ?? "{}");
        if (BIOMES.includes(s.biome))
            prefs.biome = s.biome;
        // (names are kept so the chips don't regrow six maps on every menu visit)
        if (Array.isArray(s.recent))
            prefs.recent = s.recent
                .filter((r) => typeof r?.id === "string" && typeof r.name === "string" && parseRandomMapId(r.id) !== null)
                .slice(0, RECENT_MAX);
    }
    catch {
        /* storage unavailable — start fresh */
    }
    return prefs;
}

function saveRandomPrefs(prefs) {
    try {
        localStorage.setItem(RANDOM_KEY, JSON.stringify(prefs));
    }
    catch {
        /* ignore */
    }
}

/** A shareable link to this game with a map preselected (?map=<id>, read on boot). */
function mapLink(id) {
    const url = new URL(location.href);
    url.search = "";
    url.hash = "";
    url.searchParams.set("map", id);
    return url.toString();
}

/**
 * What a player typed into the seed box: a whole random map id (or a pasted
 * link holding one) picks that map; a code of any length is taken as is (the
 * longest 32-bit codes are 7 characters); other text is hashed into a seed.
 */
function idFromSeedText(text, biome) {
    const t = text.trim().toLowerCase();
    const whole = /random-[a-z]+-[0-9a-z]+/.exec(t)?.[0];
    if (whole && parseRandomMapId(whole))
        return whole;
    const code = t.replace(/^#/, "");
    const exact = parseRandomMapId(`${RANDOM_PREFIX}${biome}-${code}`);
    return randomMapId(biome, exact ? exact.seed : seedFromText(code));
}

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const esc = (s) => s.replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[ch]);

function showMenu(linkedMap) {
    loadSettings();
    // "Rematch" from an end screen: what to skip straight into (read below)
    let token = null;
    try {
        token = sessionStorage.getItem(REMATCH_KEY);
        sessionStorage.removeItem(REMATCH_KEY);
    }
    catch {
        /* ignore */
    }
    // ?map=<id> (a shared random map, or any built-in): preselect it and keep it as the pick
    if (linkedMap && isKnownMapId(linkedMap)) {
        gameMode.mapId = linkedMap;
        if (gameMode.mode === "ops")
            gameMode.mode = "skirmish";
        saveSettings();
    }
    const rnd = loadRandomPrefs();
    /** The map behind the 🎲 card: the pick if it's generated, else the last one seen, else a fresh roll. */
    let randomId = isRandomMapId(gameMode.mapId) && isKnownMapId(gameMode.mapId)
        ? gameMode.mapId
        : rnd.recent[0]?.id ?? rollRandomMapId(rnd.biome ?? undefined);
    const remember = (id) => {
        rnd.recent = [{ id, name: mapById(id).name }, ...rnd.recent.filter((r) => r.id !== id)].slice(0, RECENT_MAX);
        saveRandomPrefs(rnd);
    };
    if (randomId === gameMode.mapId)
        remember(randomId);
    const hud = document.getElementById("hud");
    const menu = document.createElement("div");
    menu.id = "splash";
    menu.className = "menu";
    const diffs = Object.keys(DIFFICULTY);
    menu.innerHTML = `
    <div class="keyart"></div>
    <button class="round menu-mute" id="menu-mute" title="Mute all">🔊</button>
    <div class="menu-inner">
      <h1 class="logo">BATTLE<br/><span>DRONES</span></h1>
      <div class="menu-side" id="menuside">
        <button class="rankbadge" id="rankbadge"></button>
        <div class="dailyop" id="dailyop"></div>
        <button class="mutbtn side"></button>
      </div>
      <p class="sub" id="sub"></p>
      <div class="seg modes" id="gmode">
        <button data-m="skirmish">⚔ Skirmish</button>
        <button data-m="survival">🛡 Last Stand</button>
        <button data-m="ops">🎖 Ops</button>
      </div>
      <p class="lsbest" id="lsbest" hidden></p>
      <p class="lsbest opsum" id="opsum" hidden></p>
      <div class="maps opcards" id="opcards" hidden></div>
      <p class="blurb opblurb" id="opblurb" hidden></p>
      <div class="maps" id="maps">
        ${MAPS.map((m) => `
          <button class="mapcard" data-id="${m.id}">
            <img src="${mapThumbUrl(m.id)}" alt="" draggable="false" />
            <span class="mn">${m.name}</span>
            <span class="mb">${m.size}×${m.size} · ${m.players === 4 ? "4 players" : m.biome}</span>
            <span class="mbest" hidden></span>
            <span class="mstars" hidden></span>
          </button>`).join("")}
        <button class="mapcard rndcard" data-id="${randomId}" id="rndcard">
          <img src="" alt="" draggable="false" />
          <span class="mfog" aria-hidden="true"><b>?</b></span>
          <span class="mzoom" aria-hidden="true"><i>🔍</i></span>
          <span class="mn"></span>
          <span class="mb"></span>
          <span class="mbest" hidden></span>
          <span class="mstars" hidden></span>
          <span class="mrnd">🎲 Random</span>
        </button>
      </div>
      <div class="rndpanel" id="rndpanel" hidden>
        <div class="seg rndbiome" id="rndbiome">
          <button data-b="" title="Rerolls pick any biome">🎲 Any</button>
          ${BIOMES.map((b) => `<button data-b="${b}" title="${cap(b)}">${BIOME_ICON[b]}<span> ${cap(b)}</span></button>`).join("")}
        </div>
        <div class="rndrow">
          <label class="rndseed" title="Seed: type or paste a code to grow that map">#<input id="rndseed" type="text" inputmode="text" autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="40" /></label>
          <button class="cta alt" id="rndroll">🎲 Reroll</button>
          <button class="cta alt" id="rndcopy">🔗 Copy link</button>
        </div>
        <p class="rndhint"><b>Before you play</b> <span id="rndhint"></span></p>
        <div class="rndrow">
          <div class="seg rndview" id="rndview" role="radiogroup" aria-label="Before you play">
            <button data-u="0" role="radio" title="See the whole map before the match">👁️ Preview</button>
            <button data-u="1" role="radio" title="The map stays black until you scout it">🌫️ Uncharted</button>
          </div>
          <button class="cta alt" id="rndfull">🔍 View<span class="wide"> full</span> map</button>
        </div>
        <div class="rndrecent" id="rndrecent"></div>
      </div>
      <p class="blurb" id="blurb"></p>
      <div class="seg" id="diff">
        ${diffs.map((d) => `<button data-d="${d}">${DIFFICULTY[d].label}</button>`).join("")}
      </div>
      <button class="mutbtn main"></button>
      <button class="cta big" id="play">▶ Play</button>
      <div class="row" id="duelrow">
        <button class="cta alt" id="play-together">📱 Play together</button>
      </div>
      <div class="row">
        <button class="cta alt" id="play-spectate">🤖 Watch AI vs AI</button>
        <button class="cta alt" id="play-replay">🎬 Watch a replay</button>
        <button class="cta alt" id="howto">? How to play</button>
        <button class="cta alt" id="about">ⓘ About</button>
      </div>
      <div class="help" id="helpbox" hidden>${HELP_HTML}</div>
      <p class="credits">Based on Battle Drones by Simon Willison · Art generated with OpenAI gpt-image-2.5 · sound synthesized live</p>
    </div>
  `;
    hud.appendChild(menu);
    // inline, document-relative URLs keep GitHub Pages subpaths working
    const art = menu.querySelector(".keyart");
    const landscape = window.matchMedia("(orientation: landscape)");
    const setArt = () => (art.style.backgroundImage = `url(assets/ui/keyart-${landscape.matches ? "landscape" : "portrait"}.webp)`);
    setArt();
    landscape.addEventListener("change", setArt);

    // menu music: a gentle take on the selected map's theme, from the first touch
    const biomeOf = (id) => mapById(id).biome;
    sfx.unlockOnGesture();
    const muteBtn = menu.querySelector("#menu-mute");
    const syncMute = () => (muteBtn.textContent = sfx.muted ? "🔇" : "🔊");
    syncMute();
    const offMute = sfx.onChange(syncMute);
    muteBtn.addEventListener("click", () => sfx.setMuted(!sfx.muted));
    // career: rank badge, Daily Op card, mutator picker, map stars (ui/career.ts)
    const career = mountMenuCareer(menu, {
        playDaily: (op) => void begin(false, () => startDaily(op)),
        changed: () => saveSettings()
    });
    // Ops: op cards, progress line and the briefing sheet (ui/ops.ts)
    const ops = mountMenuOps(menu, {
        start: (op) => void begin(false, () => startOp(op)),
        selectedId: () => gameMode.opId,
        select: (id) => {
            gameMode.opId = id;
            saveSettings();
            sync(); // the Play button names the picked op
        }
    });
    /** Is this map offered in the mode picked (Last Stand isn't played on the island map)? */
    const offered = (id) => gameMode.mode !== "survival" || mapById(id).lastStand !== false;
    /** The map the menu shows and Play starts: the pick, or the first one offered in this mode. */
    const shownMap = () => (offered(gameMode.mapId) ? gameMode.mapId : MAPS.find((x) => offered(x.id)).id);
    let menuBiome = null;
    // the map and Ops rows scroll sideways on phones: fade + chevrons say so
    const mapRow = scrollCue(menu.querySelector("#maps"));
    scrollCue(menu.querySelector("#opcards"));
    let revealed = "";
    let shownRandom = "";
    /**
     * The 🎲 card and the random-map panel follow randomId. Uncharted, the card
     * wears fog over a "?" and goes by "Uncharted": only the biome and the code
     * (to share or replay the seed) give anything away, and the thumbnail is
     * never painted.
     */
    function syncRandom() {
        const card = menu.querySelector("#rndcard");
        const def = mapById(randomId);
        const code = def.random?.code ?? seedCode(def.seed);
        const blind = gameMode.uncharted;
        const key = `${randomId}:${blind}`;
        if (shownRandom !== key) {
            shownRandom = key;
            card.dataset.id = randomId;
            card.dataset.biome = def.biome;
            card.classList.toggle("uncharted", blind);
            const img = card.querySelector("img");
            img.src = blind ? BLANK_IMG : mapThumbUrl(randomId);
            card.querySelector(".mn").textContent = blind ? "Uncharted" : def.name;
            card.querySelector(".mb").textContent = `${RANDOM_MAP_SIZE}×${RANDOM_MAP_SIZE} · ${def.biome} · #${code}`;
            card.title = blind ? `Uncharted (${def.biome}, seed ${code})` : `${def.name} (${def.biome}, seed ${code}) · tap again to view the whole map`;
        }
        menu.querySelectorAll("#rndview button").forEach((el) => {
            const on = (el.dataset.u === "1") === blind;
            el.classList.toggle("on", on);
            el.setAttribute("aria-checked", String(on));
        });
        menu.querySelector("#rndfull").hidden = blind;
        menu.querySelector("#rndhint").textContent = blind
            ? "Go in blind: scout to reveal the map."
            : "Study the whole map first.";
        const box = menu.querySelector("#rndseed");
        if (document.activeElement !== box)
            box.value = code;
        menu.querySelectorAll("#rndbiome button").forEach((el) => el.classList.toggle("on", (el.dataset.b || null) === rnd.biome));
        menu.querySelector("#rndrecent").innerHTML = rnd.recent
            .map((r) => {
            const p = parseRandomMapId(r.id);
            const on = r.id === randomId ? " on" : "";
            // (uncharted: code and biome only, no names)
            const name = blind ? "" : `${esc(r.name)} `;
            const title = blind ? `Uncharted · ${p.biome}` : `${esc(r.name)} · ${p.biome}`;
            return `<button class="rndchip${on}" data-id="${r.id}" title="${title}">${BIOME_ICON[p.biome]} ${name}<b>#${seedCode(p.seed)}</b></button>`;
        })
            .join("");
    }
    const sync = () => {
        const survival = gameMode.mode === "survival";
        const opsMode = gameMode.mode === "ops";
        career.sync();
        for (const id of ["#opsum", "#opcards", "#opblurb"])
            menu.querySelector(id).hidden = !opsMode;
        for (const id of ["#maps", "#blurb", "#diff"])
            menu.querySelector(id).hidden = opsMode;
        syncRandom();
        ops.sync();
        menu.querySelector("#play-spectate").hidden = opsMode;
        menu.querySelector("#duelrow").hidden = gameMode.mode !== "skirmish";
        menu.classList.toggle("ops-mode", opsMode);
        // Last Stand isn't offered on every map (the island map): show the first that is, without
        // losing the skirmish pick (Play points the match at the shown map: see begin)
        const shown = shownMap();
        menu.querySelectorAll("#maps .mapcard").forEach((el) => {
            el.hidden = !offered(el.dataset.id);
            el.classList.toggle("on", el.dataset.id === shown);
            // Last Stand: each map card shows its best for the chosen difficulty
            const badge = el.querySelector(".mbest");
            const rec = survival ? loadBest(el.dataset.id, gameMode.difficulty) : null;
            badge.hidden = !rec;
            badge.textContent = rec ? `🛡 ${rec.best}` : "";
            // (generated maps earn no stars: there are endlessly many)
            const stars = el.querySelector(".mstars");
            const noStars = survival || isRandomMapId(el.dataset.id);
            const mask = noStars ? 0 : career.starsFor(el.dataset.id);
            stars.hidden = noStars;
            stars.textContent = starsText(mask);
            stars.classList.toggle("got", mask > 0);
        });
        // bring the picked map into view when the row first shows (or shows again)
        const pick = menu.querySelector(`#maps .mapcard[data-id="${shown}"]`);
        const key = opsMode ? "" : `${gameMode.mode}:${shown}`;
        if (key && key !== revealed && pick) {
            const smooth = revealed !== ""; // (opening the menu: already centred, no slide)
            requestAnimationFrame(() => mapRow.reveal(pick, smooth));
            revealed = key;
        }
        // the menu theme follows the map on show
        const biome = biomeOf(shown);
        if (biome !== menuBiome) {
            menuBiome = biome;
            music.play("menu", biome);
        }
        menu.querySelectorAll("#diff button").forEach((el) => el.classList.toggle("on", el.dataset.d === gameMode.difficulty));
        menu.querySelectorAll("#gmode button").forEach((el) => el.classList.toggle("on", el.dataset.m === gameMode.mode));
        const m = mapById(shown);
        const blind = gameMode.uncharted && isRandomMapId(shown);
        menu.querySelector("#blurb").textContent = blind ? "An unknown battlefield. Scout it to learn its shape." : m.blurb;
        menu.querySelector("#rndpanel").hidden = opsMode || !isRandomMapId(shown);
        const four = m.players === 4;
        menu.querySelector("#sub").textContent = opsMode
            ? "Short missions with a twist. Three stars each — can you take them all?"
            : survival
                ? "Hold your base against endless, themed waves. How long can you last?"
                : four
                    ? "Four commanders, one survivor. Knock out every rival's HQ and Goliaths."
                    : "Mine scrap. Build your swarm. Destroy the enemy HQ and its Goliaths.";
        // a four-player map seats four commanders, every other map two
        menu.querySelector("#play-together").textContent = four ? "📱 Play together (up to 4)" : "📱 Play together";
        const best = menu.querySelector("#lsbest");
        best.hidden = !survival;
        if (survival) {
            const rec = loadBest(shown, gameMode.difficulty);
            const where = `${blind ? `Uncharted #${m.random?.code ?? ""}` : m.name} · ${DIFFICULTY[gameMode.difficulty].label}`;
            best.innerHTML = rec
                ? `🏆 Best on ${where}: <b>${rec.best} wave${rec.best === 1 ? "" : "s"}</b>`
                : `No record yet on ${where} — set one!`;
        }
        const sel = ops.selected();
        menu.querySelector("#play").textContent = opsMode
            ? ops.locked(sel) ? "🔒 Locked" : `▶ Op: ${sel.title}`
            : survival ? "▶ Start Last Stand" : "▶ Play";
        menu.querySelector("#play").classList.toggle("locked", opsMode && ops.locked(sel));
        menu.querySelector("#play-spectate").textContent = survival ? "🤖 Watch AI defend" : "🤖 Watch AI vs AI";
    };
    sync();
    menu.querySelectorAll("#maps .mapcard").forEach((el) => el.addEventListener("click", () => {
        // a second tap on the picked 🎲 card opens the full-map preview
        if (el.id === "rndcard" && el.classList.contains("on") && !gameMode.uncharted)
            return previewRandom();
        gameMode.mapId = el.dataset.id;
        if (isRandomMapId(gameMode.mapId))
            remember(gameMode.mapId);
        saveSettings();
        sync();
    }));
    // random maps: biome, seed, reroll, link, recent picks
    const pickRandom = (id) => {
        randomId = gameMode.mapId = id;
        remember(id);
        saveSettings();
        sfx.play("click", 0.5);
        sync();
    };
    menu.querySelectorAll("#rndbiome button").forEach((el) => el.addEventListener("click", () => {
        const b = (el.dataset.b || null);
        rnd.biome = b;
        saveRandomPrefs(rnd);
        // a biome keeps the seed (same code, new world); "Any" just frees the rerolls
        const p = parseRandomMapId(randomId);
        if (b && p && p.biome !== b)
            pickRandom(randomMapId(b, p.seed));
        else
            syncRandom();
    }));
    const seedBox = menu.querySelector("#rndseed");
    seedBox.addEventListener("change", () => {
        const biome = rnd.biome ?? parseRandomMapId(randomId)?.biome ?? "temperate";
        if (seedBox.value.trim())
            pickRandom(idFromSeedText(seedBox.value, biome));
        else
            syncRandom(); // (emptied: show the code back)
    });
    seedBox.addEventListener("keydown", (e) => e.key === "Enter" && seedBox.blur());
    menu.querySelector("#rndroll").addEventListener("click", () => pickRandom(rollRandomMapId(rnd.biome ?? undefined)));
    const copyBtn = menu.querySelector("#rndcopy");
    let copiedTimer = 0;
    copyBtn.addEventListener("click", () => {
        sfx.play("click", 0.5);
        void navigator.clipboard
            ?.writeText(mapLink(randomId))
            .then(() => {
            copyBtn.textContent = "✓ Copied!";
            clearTimeout(copiedTimer);
            copiedTimer = window.setTimeout(() => (copyBtn.textContent = "🔗 Copy link"), 1600);
        })
            .catch(() => {
            /* no clipboard (insecure context, denied): fail quietly */
        });
    });
    // before you play: see the whole map (Preview), or go in blind (Uncharted)
    menu.querySelectorAll("#rndview button").forEach((el) => el.addEventListener("click", () => {
        const blind = el.dataset.u === "1";
        if (blind === gameMode.uncharted)
            return;
        gameMode.uncharted = blind;
        saveSettings();
        sfx.play("click", 0.5);
        sync();
    }));
    /** The full-map preview of the 🎲 card's map: Play starts it as Play does, Reroll keeps the menu in step. */
    const previewRandom = () => {
        if (gameMode.uncharted)
            return;
        sfx.play("click", 0.5);
        openMapPreview(mapById(randomId), {
            host: menu,
            playLabel: gameMode.mode === "survival" ? "▶ Start Last Stand" : "▶ Play this map",
            onPlay: () => {
                gameMode.mapId = randomId;
                saveSettings(); // (a Rematch reloads the saved pick)
                void begin(false);
            },
            onReroll: () => {
                pickRandom(rollRandomMapId(rnd.biome ?? undefined));
                return mapById(randomId);
            }
        });
    };
    menu.querySelector("#rndfull").addEventListener("click", previewRandom);
    menu.querySelector("#rndrecent").addEventListener("click", (e) => {
        const id = e.target.closest("[data-id]")?.dataset.id;
        if (id && isKnownMapId(id))
            pickRandom(id);
    });
    menu.querySelectorAll("#diff button").forEach((el) => el.addEventListener("click", () => {
        gameMode.difficulty = el.dataset.d;
        saveSettings();
        sync();
    }));
    menu.querySelectorAll("#gmode button").forEach((el) => el.addEventListener("click", () => {
        gameMode.mode = el.dataset.m;
        sfx.play("click", 0.5);
        saveSettings();
        sync();
    }));
    menu.querySelector("#howto").addEventListener("click", () => {
        const h = menu.querySelector("#helpbox");
        h.hidden = !h.hidden;
    });

    // one match per page: a second tap while the full-screen request is
    // pending (Android takes a moment) must not boot a second game
    let starting = false;
    const begin = async (spectator, setup, feed) => {
        if (starting)
            return;
        starting = true;
        // a Last Stand on a map it isn't offered on plays the shown one (not saved: the pick stays)
        if (!setup && !offered(gameMode.mapId))
            gameMode.mapId = shownMap();
        gameMode.party = false;
        setup?.(); // (the Daily Op / an op points the match at its map and rules)
        gameMode.spectator = spectator;
        sfx.unlock();
        sfx.play("click");
        offMute();
        menu.remove();
        void startGame(feed);
    };
    menu.querySelector("#play").addEventListener("click", () => {
        if (gameMode.mode !== "ops")
            return void begin(false);
        const op = ops.selected();
        sfx.play("click", 0.5);
        if (!ops.locked(op))
            ops.openBrief(op);
    });
    menu.querySelector("#play-spectate").addEventListener("click", () => begin(true));
    // played together: phones and controllers take sides in the lobby, the screen shows the whole battle
    const together = () => {
        sfx.play("click", 0.5);
        openLobby(menu, shownMap(), () => begin(true, () => (gameMode.party = true)));
    };
    menu.querySelector("#play-together").addEventListener("click", together);
    menu.querySelector("#about").addEventListener("click", () => {
        sfx.play("click", 0.5);
        openSheet(menu, "about", ABOUT_HTML);
    });
    // an agent battle's record, pasted or picked: the viewer loads only now (game/replay.ts)
    menu.querySelector("#play-replay").addEventListener("click", () => {
        sfx.play("click", 0.5);
        showReplayPicker(menu, async (json) => {
            const { replayFromJson } = await import("./game/replay.js");
            const feed = replayFromJson(json);
            await begin(true, () => watchSetup(feed), feed);
        });
    });

    // "Rematch" from the end screen skips straight back into a game
    let rematch = false;
    // a match played together comes back to its lobby, where the phones find their seats again as they rejoin
    if (token === "party")
        together();
    try {
        const op = token?.startsWith("op:") ? opById(token.slice(3)) : null;
        rematch = token === "1" || token === "spectate" || token === "daily" || !!op;
        if (token === "spectate")
            gameMode.spectator = true; // another AI-vs-AI match
        if (token === "daily")
            startDaily(dailyOp(today()));
        if (op)
            startOp(op);
    }
    catch {
        /* ignore */
    }
    if (rematch) {
        offMute();
        menu.remove();
        void startGame();
        // audio needs a gesture: sfx.unlockOnGesture() (above) starts it on the first touch
    }
}

/**
 * `/?replay=<record>`, in every build: fetch a battle record by its link
 * (relative to the game, any CORS-enabled URL, a file on GitHub or a Gist) and
 * watch it. Its Menu buttons leave the link behind (ui/fullscreen.ts).
 */
async function watchLinked(url, follow) {
    const note = document.createElement("div");
    note.className = "screen";
    note.innerHTML = `<div class="loadbox"><p>Fetching the battle record…</p></div>`;
    document.getElementById("hud").appendChild(note);
    const feed = await import("./game/replay.js")
        .then((m) => m.loadReplay(url, follow))
        .catch((e) => {
        note.innerHTML = `<div class="panel"><p class="time"></p><button class="cta">Main menu</button></div>`;
        note.querySelector("p").textContent = `Couldn't play that battle record. ${e instanceof Error ? e.message : String(e)}`;
        note.querySelector("button").addEventListener("click", () => location.assign("./"));
        return null;
    });
    if (!feed)
        return;
    note.remove();
    watchSetup(feed);
    sfx.unlockOnGesture(); // (no menu was tapped: the sound starts on the first touch)
    await startGame(feed);
}

/** Point the next match at a battle replay's map and rules (not saved: the player's own picks stay). */
function watchSetup(feed) {
    Object.assign(gameMode, { mapId: feed.record.map, spectator: true, mode: "skirmish", mutators: feed.record.mutators, daily: null, op: null });
}

/** Point the next match at an op (not saved: the op fixes map, enemy and rules). */
function startOp(op) {
    // remember the pick (and the Ops tab) before the op's own map and difficulty take over
    gameMode.opId = op.id;
    gameMode.mode = "ops";
    saveSettings();
    gameMode.op = op;
    gameMode.mapId = op.map;
    gameMode.difficulty = op.ai && op.ai !== "survival" ? op.ai.difficulty : op.survival?.difficulty ?? "normal";
}

/** Point the next match at the Daily Op (not saved: the player's own picks stay). */
function startDaily(op) {
    gameMode.daily = op;
    gameMode.mapId = op.mapId;
    gameMode.difficulty = op.difficulty;
    gameMode.mode = "skirmish";
}

/** The About sheet: where the game comes from. */
const ABOUT_HTML = `<h2>About Battle Drones</h2>
  <p class="sh-sub">Based on <b>Battle Drones</b> by Simon Willison, a real-time strategy game in the spirit of Command &amp; Conquer,
  released under the Apache License 2.0 (github.com/simonw/battledrones). Its art was generated with OpenAI's gpt-image-2.5 and
  every sound is synthesized live.</p>
  <p class="sh-sub">This version is a starter made with Lamp: played on the Mac with the keyboard and mouse or a controller, and
  together on one screen with phones and controllers. It uses qrcode-generator by Kazuhiko Arase (MIT).</p>
  <div class="sh-actions"><button class="cta alt sheet-close">Close</button></div>`;

/** The menu, or a battle record's link: what the page opens on when there's no match to go back to. */
function boot() {
    const params = new URLSearchParams(location.search);
    const replayLink = params.get("replay")?.trim();
    if (replayLink)
        return void watchLinked(replayLink, false);
    // /?map=<id> (the random map panel's 🔗 link): preselect that map once; the saved pick carries it after
    const linkedMap = params.get("map")?.trim().toLowerCase();
    if (params.has("map")) {
        params.delete("map");
        const q = params.toString();
        history.replaceState(null, "", `${location.pathname}${q ? `?${q}` : ""}${location.hash}`);
    }
    showMenu(linkedMap);
}

/** A match opened again after a change of the game's code: the same rules, seats and world, carrying on from there. */
async function resume(was) {
    loadSettings();
    Object.assign(gameMode, was.mode, { op: was.mode.op ? opById(was.mode.op) : null });
    if (was.party)
        restoreParty(was.party);
    sfx.unlockOnGesture();
    await startGame(null, was.match);
}

// Lamp's runtime runs the game (lamp-game.js): it calls frame about 60 times a second wherever the game is played,
// hands it the controllers, keeps snapshot() while the code changes, and waits for busy() to be false before it opens
// the page again with new code. The page lays itself out at the window's size (`fill`): its HUD is the page's own HTML.
game({
    renderer: makeRenderer(),
    fill: true,
    // The game draws its own touch controls (the map and the HUD are touched directly) and reads the keys itself.
    touch: false,
    keyboard: false,
    async init() {
        const was = pendingRestore();
        if (was?.match)
            await resume(was);
        else
            boot();
    },
    frame(f) {
        partyFrame(f);
        padFrame(f, scene);
        scene?.frame(f.dt * 1000);
    },
    snapshot() {
        const match = scene?.snapshot();
        if (!match)
            return null;
        const { spectator, mapId, difficulty, mode, mutators, uncharted, daily, party } = gameMode;
        return { match, mode: { spectator, mapId, difficulty, mode, mutators, uncharted, daily, party, op: gameMode.op?.id ?? null },
                 party: partySnapshot() };
    },
    busy: () => !!scene?.busy
});
