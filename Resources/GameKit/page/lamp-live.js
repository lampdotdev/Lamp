// Lamp's changes for a web game whose page doesn't run on Lamp's game runtime (lamp-game.js), put in while it's played.
// The app around a game's page (LampPage.swift) and lamp dev (cli/page.js) give it to the page before any script of
// the page's own; a web app's or a screen's page goes without it and opens again for each change, as ever.
//
// A game that runs on the runtime never uses any of this: lamp-game.js sets `window.__lampLive` as it loads, and
// what was handed here before it did (a change saved while the page opened) is handed on to it, in order, generations
// and all.
//
// What goes into the running game, with every object it made and its fields where they are:
// - a stylesheet the page links: the new one replaces it;
// - a change inside one method of a class a module of the game exports (a getter, setter or static method too), when
//   the new method uses nothing of its module but what the module imports and constants written as a plain number,
//   string, true, false or null: the method is made again from those alone (the module itself never runs again, so
//   nothing at its top level happens twice) and put on the running class, so every object made from it runs the new
//   code from its next call.
// Anything else waits for Reload, and Lamp is told what and why: the page, a script that isn't a module, a constructor,
// a field, a new method or class, code outside a class, a method that uses `super`, `import()` or `import.meta` (each read
// from where the code is), a private member (#name) or anything at its module's top level (its own copy, which the running game holds, would be another), two
// methods changed at once, and any file the game read or names. A file the game never read and nothing it runs names
// is no part of the change: the app around the page says with each change every file it served the page (`read`).
//
// The game is started before anything goes in: the page has loaded, without an error as it started, and the sources
// of its modules have been read as they ran. A game that takes longer to be ready says so with
// `lampLive.waitForReady()` as it starts and `lampLive.ready()` once it is; until then a change waits, and goes in then.
// A page that stopped with an error as it started has nothing to keep: a change opens it again.
(() => {
    if (window.__lampLiveHelper) return;
    window.__lampLiveHelper = true;

    // The browser's own, before the page's code can change them.
    const read = window.fetch.bind(window), later = window.setTimeout.bind(window);
    const tell = (gen, state, why, more) => {
        try {
            const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lampLive;
            if (h) h.postMessage({ gen, state, ...(why ? { why } : {}), ...more });
        } catch (e) {}
    };
    const log = text => { try { console.log(text); } catch (e) {} };
    try { performance.setResourceTimingBufferSize(100000); } catch (e) {}

    const clean = path => String(path).replace(/^\.?\//, '').split(/[?#]/)[0];
    const pageBase = () => new URL('.', location.href.split(/[?#]/)[0]);
    const pathOf = url => {
        try {
            const u = new URL(url, location.href), base = pageBase();
            if (u.origin !== base.origin || !u.pathname.startsWith(base.pathname)) return null;
            return decodeURIComponent(u.pathname.slice(base.pathname.length));
        } catch (e) { return null; }
    };
    const addressOf = path => new URL(path, pageBase()).href;
    const pagePath = () => pathOf(location.href.split(/[?#]/)[0]) || 'index.html';
    // Lamp's own files beside the page (the runtime, three.js, which is large) aren't read for the game's modules; a change
    // to one the page uses still waits for Reload.
    const lampOwn = path => /^(three|rapier|phaser)\//.test(path) || /^lamp(-[\w-]+)?\.js$/.test(path);

    // MARK: Is the game started

    let ready = false, loaded = false, waitAsked = false, readyCalled = false, broken = null;
    window.addEventListener('error', e => {
        if (ready || broken) return;
        // A script of the page's that didn't load, or threw as it ran: the game never started as it should.
        if (e instanceof ErrorEvent) broken = e.message || 'an error';
        else if (e.target && e.target.tagName === 'SCRIPT') broken = `${pathOf(e.target.src) || 'a script'} didn't load`;
    }, true);
    window.addEventListener('unhandledrejection', e => {
        if (!ready && !broken) broken = String(e.reason && e.reason.message || e.reason);
    });
    window.lampLive = Object.freeze({
        waitForReady() { if (!ready) waitAsked = true; },
        ready() { readyCalled = true; settle(); },
    });
    window.addEventListener('load', () => { loaded = true; later(settle, 0); }, { once: true });

    // MARK: What the page runs, as it started

    const texts = new Map();          // a module's or stylesheet's address → its source as the page runs it
    const graph = new Set();          // the addresses of the game's modules, from the page's module scripts down
    let pageText = '', sourcesRead = false, sourcesOk = false;
    // Files changed before their sources were read: what the page runs of them can't be told from what's new.
    const unsure = new Set();

    async function readText(url) {
        const r = await read(url, { cache: 'no-store' });
        if (!r.ok) throw new Error(`${pathOf(url) || url} couldn't be read (${r.status})`);
        return r.text();
    }

    let importMap = null;
    function resolve(specifier, from) {
        if (/^\.{0,2}\//.test(specifier)) return new URL(specifier, from).href;
        if (/^[a-z][\w+.-]*:/i.test(specifier)) return specifier;
        if (!importMap) {
            importMap = {};
            for (const s of document.querySelectorAll('script[type="importmap"]')) { try { Object.assign(importMap, JSON.parse(s.textContent).imports || {}); } catch (e) {} }
        }
        if (importMap[specifier]) return new URL(importMap[specifier], location.href).href;
        const prefix = Object.keys(importMap).filter(k => k.endsWith('/') && specifier.startsWith(k)).sort((a, b) => b.length - a.length)[0];
        return prefix ? new URL(importMap[prefix] + specifier.slice(prefix.length), location.href).href : null;
    }

    async function readSources() {
        pageText = document.documentElement ? document.documentElement.outerHTML : '';
        const visit = async url => {
            const path = pathOf(url);
            if (graph.has(url) || path == null || lampOwn(path)) return;
            graph.add(url);
            const text = await readText(url);
            texts.set(url, text);
            await Promise.all(importsOf(text).map(i => resolve(i.specifier, url)).filter(Boolean).map(visit));
        };
        const scripts = [...document.querySelectorAll('script[type="module"]')];
        // A module script written in the page: what it imports is the game's too.
        const roots = scripts.flatMap(s => s.getAttribute('src') ? [new URL(s.getAttribute('src'), location.href).href]
            : importsOf(s.textContent).map(i => resolve(i.specifier, location.href)).filter(Boolean));
        const styles = [...document.querySelectorAll('link[rel~="stylesheet"]')].map(l => l.href).filter(h => pathOf(h) != null);
        await Promise.all([...roots.map(visit), ...styles.map(async url => { try { texts.set(url, await readText(url)); } catch (e) {} })]);
    }
    // Read as soon as the page's own scripts are known, while they're the ones it runs.
    const readAtStart = () => readSources().then(() => { sourcesOk = true; }, e => log(`Lamp: the game's code couldn't be read as it started (${e && e.message || e}).`))
        .finally(() => { sourcesRead = true; settle(); });
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', readAtStart, { once: true });
    else later(readAtStart, 0);

    function settle() {
        if (ready || runtime || !loaded || !sourcesRead || (waitAsked && !readyCalled)) return;
        ready = true;
        run();
    }

    // MARK: Changes

    let runtime = null;               // lamp-game.js's own, once it takes over
    const pending = [];               // changes handed here and not yet put in, in order
    let held = null;                  // what waits for Reload: { gen, changed, removed, why }
    let active = null;                // the change being put in now, until it's in or held
    let queue = Promise.resolve(), pill = null;
    // Thrown out of a change being put in once the runtime has taken over, which is handed that change instead: from
    // there nothing more of it is put in here, nor said.
    const HANDED = new Error('handed to the game runtime');
    const stillMine = () => { if (runtime) throw HANDED; };

    const take = change => {
        if (runtime) return runtime(change);
        // The person's Reload goes in at once, whatever waits: nothing queued here is worth keeping over it.
        if (change.now) { reopen(change, 'Reload'); return true; }
        if (!sourcesRead) for (const path of [...(change.changed || []), ...(change.removed || [])]) unsure.add(clean(path));
        pending.push(change);
        // Not started yet: it goes in once the game is, by itself.
        if (!ready && !change.now && !broken) tell(change.gen || 0, 'held', 'the game is still starting', { pause: true });
        run();
        return true;
    };
    take.lampHelper = true;
    // The game runtime, as it loads, takes every change from here on, and those handed here meanwhile.
    Object.defineProperty(window, '__lampLive', {
        configurable: true, enumerable: true,
        get: () => runtime || take,
        set: given => {
            if (given === take || typeof given !== 'function') return;
            runtime = given;
            hidePill();
            // What waits for Reload, then the change being put in (it stops at its next step: `stillMine`), then those
            // not begun, each with its own generation.
            const handed = [];
            if (held) handed.push({ gen: held.gen, changed: [...held.changed], removed: [...held.removed], now: false, pill: held.pill });
            if (active) handed.push(active);
            handed.push(...pending.splice(0));
            held = null;
            active = null;
            for (const change of handed) { try { runtime(change); } catch (e) { log(`Lamp: ${e && e.message || e}`); } }
        },
    });

    function run() {
        queue = queue.then(async () => {
            while (pending.length && !runtime) {
                const change = pending[0];
                if (broken) return reopen(change, `the game stopped with an error as it started (${broken})`);
                if (!ready) return;
                active = pending.shift();
                await put(active);
                active = null;
            }
        }).catch(e => { if (e !== HANDED) log(`Lamp: ${e && e.message || e}`); });
    }

    function reopen(change, why) {
        pending.length = 0;
        tell(change.gen || 0, 'reloading', why);
        location.reload();
    }

    async function put(change) {
        const gen = change.gen || 0, went = [], waits = [];
        const hold = (path, why) => waits.push({ path, why });
        for (const raw of change.changed || []) {
            const path = clean(raw), url = addressOf(path);
            try {
                if (path === pagePath()) hold(path, `${path} is the page itself`);
                else if (graph.has(url)) {
                    const r = await swapModule(url, path);
                    stillMine();
                    if (typeof r === 'string') hold(path, r);
                    else if (r) went.push(r.went);
                } else if (/\.css$/i.test(path) && linksTo(path).length) {
                    await swapStyle(path, gen);
                    stillMine();
                    went.push(path);
                } else if (!unused(path, change.read)) {
                    hold(path, /\.m?js$/i.test(path) ? `${path} is code the game runs that isn't one of its modules` : `the game uses ${path}`);
                }
            } catch (e) {
                if (e === HANDED) throw e;
                hold(path, `${path} couldn't be put in (${e && e.message || e})`);
            }
        }
        for (const raw of change.removed || []) {
            const path = clean(raw);
            if (!unused(path, change.read)) hold(path, `${path}, which the game uses, was taken away`);
        }
        if (went.length) log(`Lamp: put in ${went.join('; ')} while the game ran.`);
        if (waits.length) {
            held = held || { gen, changed: new Set(), removed: new Set(), why: [], pill: false };
            held.gen = gen;
            held.pill = held.pill || !!change.pill;
            for (const w of waits) held.why.push(w.why);
            for (const raw of change.changed || []) held.changed.add(clean(raw));
            for (const raw of change.removed || []) held.removed.add(clean(raw));
        } else if (held) held.gen = gen;
        if (held) {
            const why = [...new Set(held.why)].join('; ') + (went.length ? `. Put in meanwhile: ${went.join('; ')}` : '');
            log(`Lamp: a change waits for Reload: ${why}.`);
            tell(gen, 'held', why);
            if (held.pill) showPill();
        } else tell(gen, 'swapped');
    }

    // A file the game has no use for: the page never asked for it (`read`, every file the app around it served the
    // page, which the page can't see for itself), and nothing of the page's names it. Anything else may be in use, and
    // so is everything when the host doesn't say what it served.
    function unused(path, read) {
        if (!sourcesOk || !Array.isArray(read) || read.map(clean).includes(path)) return false;
        try { if (performance.getEntriesByType('resource').some(e => pathOf(e.name) === path)) return false; } catch (e) {}
        const name = path.split('/').pop();
        const named = new RegExp(`(^|[^\\w.-])${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^\\w-])`);
        return ![pageText, ...texts.values()].some(text => named.test(text));
    }

    function linksTo(path) {
        return [...document.querySelectorAll('link[rel~="stylesheet"]')].filter(l => pathOf(l.href.split(/[?#]/)[0]) === path);
    }
    async function swapStyle(path, gen) {
        await Promise.all(linksTo(path).map(old => new Promise((done, failed) => {
            const next = old.cloneNode();
            next.href = `${addressOf(path)}?lamp=${gen}`;
            next.onload = () => { old.remove(); done(); };
            next.onerror = () => { next.remove(); failed(new Error(`${path} didn't load`)); };
            old.after(next);
        })));
    }

    function showPill() {
        if (pill) { pill.style.display = 'block'; return; }
        if (!document.body) return;
        pill = document.createElement('button');
        pill.textContent = 'Reload to apply';
        pill.style.cssText = 'position:fixed;z-index:2147483646;left:50%;transform:translateX(-50%);bottom:calc(14px + env(safe-area-inset-bottom));'
            + 'padding:8px 16px;border:0;border-radius:18px;background:rgba(20,20,24,.72);color:#fff;font:600 15px -apple-system,system-ui,sans-serif;'
            + '-webkit-backdrop-filter:blur(12px);backdrop-filter:blur(12px)';
        pill.addEventListener('pointerdown', e => { e.stopPropagation(); e.preventDefault(); reopen({ gen: held ? held.gen : 0 }, 'Reload'); });
        document.body.append(pill);
    }
    function hidePill() { if (pill) pill.style.display = 'none'; }

    // MARK: A method made again

    const source = f => Function.prototype.toString.call(f);
    // A method put in here, by its source as its module writes it: its own reads `lampMethod() {…}` (below).
    const written = new WeakMap();
    const sourceOf = f => written.get(f) ?? source(f);
    const isClass = v => typeof v === 'function' && /^class\b/.test(source(v));

    // Every method, accessor and static method of a class, by where it's kept.
    function methodsOf(C) {
        const out = [];
        for (const [target, skip] of [[C.prototype, ['constructor']], [C, ['length', 'name', 'prototype']]]) {
            for (const key of Reflect.ownKeys(target)) {
                if (skip.includes(key)) continue;
                const d = Object.getOwnPropertyDescriptor(target, key);
                for (const kind of ['value', 'get', 'set']) if (typeof d[kind] === 'function' && !isClass(d[kind])) out.push({ C, target, key, kind, fn: d[kind] });
            }
        }
        return out;
    }

    // A module whose change is inside one method of a class it exports: that method, made again, goes on the running
    // class. Returns what went in, null for no change, or why it waits.
    async function swapModule(url, path) {
        if (unsure.has(path)) return `${path} changed while the game was starting, so what it runs of it isn't known`;
        const old = texts.get(url);
        if (old == null) return `${path} couldn't be read as the game started`;
        const now = await readText(url);
        stillMine();
        if (now === old) return null;
        // The module the game runs: the same one every import of it has, so it doesn't run again.
        const ns = await import(url);
        stillMine();
        let a = 0;
        while (a < old.length && a < now.length && old[a] === now[a]) a++;
        let b = 0;
        while (b < old.length - a && b < now.length - a && old[old.length - 1 - b] === now[now.length - 1 - b]) b++;
        const from = a, to = old.length - b;
        let found = null;
        for (const C of new Set(Object.values(ns).filter(isClass))) {
            for (const m of methodsOf(C)) {
                const text = sourceOf(m.fn), at = old.indexOf(text);
                if (at < 0) continue;
                const head = header(tokens(text));
                if (!head || from < at + head.body + 1 || to > at + text.length - 1) continue;
                if (old.indexOf(text, at + 1) >= 0) return `${path} has more than one method written as ${C.name}.${String(m.key)} is`;
                found = { ...m, at, text };
            }
        }
        if (!found) return `${path} changed outside the body of one method of a class it exports (a constructor, a field, a new method, code outside a class, or more than one method)`;
        const name = `${found.C.name}.${String(found.key)}`;
        const fresh = now.slice(found.at, found.at + found.text.length + now.length - old.length);
        // Read as code, so a color in a string ('#ffffff') isn't taken for one.
        const scan = tokens(fresh), head = header(scan);
        if (!head) return `${name} can't be read as a method`;
        const body = scan.filter(t => t.at > head.body);
        if (body.some(t => t.t === 'priv')) return `${name} uses a private member (#name), which only a fresh start can give a new method`;
        if (scan.some(t => t.v === 'super')) return `${name} uses super`;
        // Both are read from where the code is: the new method's would be read from somewhere other than its module.
        const importAt = scan.findIndex((t, i) => t.v === 'import' && scan[i + 1] && (scan[i + 1].v === '(' || scan[i + 1].v === '.'));
        if (importAt >= 0) return `${name} uses ${scan[importAt + 1].v === '(' ? 'import()' : 'import.meta'}, which a new method would read from somewhere other than ${path}`;
        const top = topLevel(now);
        const { free, declared } = freeNames(scan, head.params);
        const both = [...declared].filter(n => top.declared.has(n) || top.imports.has(n));
        if (both.length) return `${name} declares ${both.join(', ')}, a name its module has too, so which one it means can't be told`;
        const kept = free.filter(n => top.declared.has(n) && !top.constants.has(n));
        if (kept.length) return `${name} uses ${kept.join(', ')} from ${path}'s top level, which the running game has its own copy of`;
        const unknown = free.filter(n => !top.imports.has(n) && !top.constants.has(n) && !(n in globalThis));
        if (unknown.length) return `${name} uses ${unknown.join(', ')}, which Lamp can't tell is safe to give a new method`;
        // The method again, beside the module's imports (the same modules the game runs) and the constants it reads.
        const lines = [];
        for (const i of top.importList) if (free.some(n => i.names.includes(n))) {
            const target = resolve(i.specifier, url);
            if (!target) return `${name} uses ${i.names.join(', ')}, imported from ${i.specifier}, which nothing resolves`;
            lines.push(`${i.clause.length ? `import ${i.clause} from` : 'import'} ${JSON.stringify(target)};`);
        }
        for (const [n, text] of top.constants) if (free.includes(n)) lines.push(text);
        // Under a name of its own: its key, unchanged (the change is inside its body), is never worked out again, so a
        // computed key's expression doesn't run a second time. It keeps the name the running one has.
        const unnamed = fresh.slice(0, head.key) + 'lampMethod' + fresh.slice(head.keyEnd);
        lines.push(`export default ({\n${unnamed}\n});`);
        const blob = URL.createObjectURL(new Blob([lines.join('\n')], { type: 'text/javascript' }));
        let made;
        try { made = (await import(blob)).default; }
        catch (e) { stillMine(); return `the new ${name} doesn't run (${e && e.message || e})`; }
        finally { URL.revokeObjectURL(blob); }
        stillMine();
        const d = Object.getOwnPropertyDescriptor(made, 'lampMethod'), was = Object.getOwnPropertyDescriptor(found.target, found.key);
        if (!d || typeof d[found.kind] !== 'function') return `${name} is another kind of member now`;
        try { Object.defineProperty(d[found.kind], 'name', { value: found.fn.name, configurable: true }); } catch (e) {}
        written.set(d[found.kind], fresh);
        Object.defineProperty(found.target, found.key, { ...was, [found.kind]: d[found.kind] });
        texts.set(url, now);
        return { went: `${path} (${name})` };
    }

    // A method as its source reads (`async *[key](…) {`, `get name() {`): where its key starts and ends in the text, the
    // token its parameters open with, and where its body opens. Its modifiers are those words only when a key follows
    // them (`get() {}` is a method named get). Null for anything else.
    function header(scan) {
        let i = 0;
        const keyNext = j => scan[j] && scan[j].v !== '(';
        while (scan[i] && ((scan[i].t === 'id' && ['async', 'get', 'set'].includes(scan[i].v)) || scan[i].v === '*') && keyNext(i + 1)) i++;
        const key = scan[i];
        if (!key) return null;
        let end = i;
        if (key.v === '[') {
            let depth = 0;
            for (; end < scan.length; end++) {
                if (['(', '[', '{'].includes(scan[end].v)) depth++;
                else if ([')', ']', '}'].includes(scan[end].v) && --depth === 0) break;
            }
        }
        const params = end + 1;
        if (!scan[params] || scan[params].v !== '(') return null;
        let depth = 0;
        for (let j = params; j < scan.length; j++) {
            if (scan[j].v === '(') depth++;
            else if (scan[j].v === ')' && --depth === 0) {
                if (!scan[j + 1] || scan[j + 1].v !== '{') return null;
                return { key: key.at, keyEnd: scan[params].at, params, body: scan[j + 1].at };
            }
        }
        return null;
    }

    // MARK: Reading code

    // JavaScript as tokens: names, punctuation (with `...` and `?.` as one), and strings, numbers, templates and regular
    // expressions as `lit`, with what a template's `${}` holds read as code. Comments go.
    const KEYWORDS_BEFORE_REGEX = new Set(['return', 'typeof', 'case', 'do', 'else', 'in', 'of', 'new', 'delete', 'void', 'throw', 'yield', 'await', 'instanceof']);
    function tokens(text) {
        const out = [], braces = [];
        let i = 0, nl = false;
        const n = text.length;
        // `nl`: a line ends between this token and the one before, which some words' meaning turns on (`async` before
        // a line break is a name).
        const push = (t, v, at) => { out.push({ t, v, at, nl }); nl = false; };
        const template = () => {
            const at = i;
            while (i < n) {
                const c = text[i];
                if (c === '\\') { i += 2; continue; }
                if (c === '`') { i++; push('lit', '`', at); return; }
                if (c === '$' && text[i + 1] === '{') { i += 2; push('lit', '`', at); braces.push('tpl'); return; }
                i++;
            }
            push('lit', '`', at);
        };
        while (i < n) {
            const c = text[i];
            if (/\s/.test(c)) { if (c === '\n' || c === '\r') nl = true; i++; continue; }
            if (c === '/' && text[i + 1] === '/') { const e = text.indexOf('\n', i); i = e < 0 ? n : e; continue; }
            if (c === '/' && text[i + 1] === '*') {
                const e = text.indexOf('*/', i + 2), end = e < 0 ? n : e + 2;
                if (/[\n\r]/.test(text.slice(i, end))) nl = true;
                i = end;
                continue;
            }
            const at = i;
            if (c === '"' || c === "'") {
                i++;
                while (i < n && text[i] !== c) { if (text[i] === '\\') i++; i++; }
                i++;
                push('lit', 'str', at);
                continue;
            }
            if (c === '`') { i++; template(); continue; }
            if (/[A-Za-z_$\u0080-￿]/.test(c)) {
                let e = i + 1;
                while (e < n && /[\w$\u0080-￿]/.test(text[e])) e++;
                push('id', text.slice(i, e), at);
                i = e;
                continue;
            }
            if (c === '#') {
                let e = i + 1;
                while (e < n && /[\w$]/.test(text[e])) e++;
                push('priv', text.slice(i, e), at);
                i = e;
                continue;
            }
            if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(text[i + 1]))) {
                let e = i + 1;
                while (e < n && /[\w.]/.test(text[e])) e++;
                push('lit', 'num', at);
                i = e;
                continue;
            }
            if (c === '/') {
                const prev = out[out.length - 1];
                const regex = !prev || (prev.t === 'punct' && !/^[)\]}]$/.test(prev.v)) || (prev.t === 'id' && KEYWORDS_BEFORE_REGEX.has(prev.v));
                if (regex) {
                    i++;
                    let inClass = false;
                    while (i < n && (inClass || text[i] !== '/') && text[i] !== '\n') {
                        if (text[i] === '\\') i++;
                        else if (text[i] === '[') inClass = true;
                        else if (text[i] === ']') inClass = false;
                        i++;
                    }
                    i++;
                    while (i < n && /[a-z]/i.test(text[i])) i++;
                    push('lit', 're', at);
                    continue;
                }
            }
            if (text.startsWith('...', i)) { push('punct', '...', at); i += 3; continue; }
            if (c === '?' && text[i + 1] === '.' && !/[0-9]/.test(text[i + 2])) { push('punct', '?.', at); i += 2; continue; }
            if (text.startsWith('=>', i)) { push('punct', '=>', at); i += 2; continue; }
            if (c === '{') braces.push('{');
            if (c === '}' && braces.length && braces[braces.length - 1] === 'tpl') { braces.pop(); i++; template(); continue; }
            if (c === '}') braces.pop();
            push('punct', c, at);
            i++;
        }
        return out;
    }

    // The words that are never a name in a module's code, which is strict: the language's reserved words. A word that's
    // a keyword only somewhere (`async`, `get`, `set`, `of`, `target` in `new.target`) is told by where it stands
    // (`freeNames`), and `undefined`, `NaN` and `Infinity` are names like any other, which a module can declare.
    const RESERVED = new Set(['await', 'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default', 'delete', 'do',
        'else', 'enum', 'export', 'extends', 'false', 'finally', 'for', 'function', 'if', 'implements', 'import', 'in', 'instanceof',
        'interface', 'let', 'new', 'null', 'package', 'private', 'protected', 'public', 'return', 'static', 'super', 'switch', 'this',
        'throw', 'true', 'try', 'typeof', 'var', 'void', 'while', 'with', 'yield']);

    // The names a method reads that it doesn't declare (`free`), and those it declares (`declared`): what it needs from
    // around it. Read from its parameters on, so its own name isn't one. Not scoped: a name declared anywhere in the
    // method counts as declared throughout, which is why one that's also a name of its module's holds the change.
    function freeNames(scan, start) {
        const declared = new Set(), used = new Set();
        // Where each bracket closes, by where it opens.
        const closes = new Map(), open = [];
        scan.forEach((t, i) => {
            if (['(', '[', '{'].includes(t.v)) open.push(i);
            else if ([')', ']', '}'].includes(t.v) && open.length) closes.set(open.pop(), i);
        });
        // `of` is a keyword only in a for loop's head, after what it declares: `for (const v of list)`.
        const ofKeyword = new Set();
        scan.forEach((t, i) => {
            if (t.v !== 'for') return;
            const at = scan[i + 1] && scan[i + 1].v === 'await' ? i + 2 : i + 1;
            if (!scan[at] || scan[at].v !== '(') return;
            let depth = 0;
            for (let j = at; j < (closes.get(at) ?? scan.length); j++) {
                if (['(', '[', '{'].includes(scan[j].v)) depth++;
                else if ([')', ']', '}'].includes(scan[j].v)) depth--;
                else if (depth === 1 && scan[j].v === 'of' && scan[j - 1] && (scan[j - 1].t === 'id' || [']', '}'].includes(scan[j - 1].v))) ofKeyword.add(j);
            }
        });
        const arrowAfter = i => scan[i] && scan[i].v === '(' && scan[(closes.get(i) ?? -2) + 1] && scan[closes.get(i) + 1].v === '=>';
        // A word that says what follows it, rather than naming anything: `async` before a function, an arrow or a
        // method's key on its line; `get` and `set` before an accessor's key in an object or class.
        // A method's definition from its key on: the key (a word, a string or number, `#name`, or `[…]`), its parameters,
        // and the brace its body opens with. `async * 2` and `get[0]` are expressions, with no such thing after them.
        const methodAt = j => {
            const key = scan[j];
            if (!key || !(key.t === 'id' || key.t === 'lit' || key.t === 'priv' || key.v === '[')) return false;
            const params = key.v === '[' ? (closes.get(j) ?? -2) + 1 : j + 1;
            if (!scan[params] || scan[params].v !== '(') return false;
            const after = scan[(closes.get(params) ?? -2) + 1];
            return !!after && after.v === '{';
        };
        const modifier = i => {
            const t = scan[i], next = scan[i + 1], prev = scan[i - 1];
            if (!next || next.nl) return false;
            if (t.v === 'async') return next.v === 'function' || arrowAfter(i + 1) || (next.v === '*' ? methodAt(i + 2) : methodAt(i + 1))
                // `async x => …`: a word after it on its line is an arrow's parameter, as nothing else can be there.
                || (next.t === 'id' && scan[i + 2] && scan[i + 2].v === '=>');
            if (t.v === 'get' || t.v === 'set') return (!prev || ['{', ',', ';', '}'].includes(prev.v)) && methodAt(i + 1);
            return false;
        };
        // Parameters: of the method, of a function, of an arrow, of a catch.
        const group = open => {
            let depth = 0;
            for (let i = open; i < scan.length; i++) {
                const t = scan[i];
                if (t.v === '(' || t.v === '[' || t.v === '{') depth++;
                else if (t.v === ')' || t.v === ']' || t.v === '}') { if (--depth === 0) return i; }
                else if (t.t === 'id' && depth >= 1) {
                    const next = scan[i + 1] && scan[i + 1].v, prev = scan[i - 1] && scan[i - 1].v;
                    if (prev !== '.' && prev !== '?.' && prev !== '=' && [',', ')', '=', '}', ']'].includes(next)) declared.add(t.v);
                }
            }
            return scan.length;
        };
        for (let i = Math.max(start, 0); i < scan.length; i++) {
            const t = scan[i], prev = scan[i - 1], next = scan[i + 1];
            if (t.v === '(') {
                // A group of parameters: the method's own, or one that's followed by =>, or after function or catch.
                const end = (() => { let d = 0; for (let j = i; j < scan.length; j++) { if (scan[j].v === '(') d++; else if (scan[j].v === ')' && --d === 0) return j; } return scan.length; })();
                const after = scan[end + 1], before = scan[i - 1], beforeThat = scan[i - 2];
                if (i === start || (after && after.v === '=>') || (before && (before.v === 'function' || before.v === 'catch'))
                    || (before && before.t === 'id' && beforeThat && beforeThat.v === 'function')
                    || (after && after.v === '{' && before && before.t === 'id' && !RESERVED.has(before.v) && (!beforeThat || [',', '{', '}', ';'].includes(beforeThat.v)))) group(i);
                continue;
            }
            if (t.t !== 'id') continue;
            if (next && next.v === '=>' && (!prev || prev.v !== '.')) { declared.add(t.v); continue; }
            if (prev && (prev.v === 'let' || prev.v === 'const' || prev.v === 'var' || prev.v === 'function' || prev.v === 'class')) { declared.add(t.v); continue; }
            if (prev && (prev.v === '.' || prev.v === '?.')) continue;
            // A key in an object, or a label.
            if (next && next.v === ':' && prev && ['{', ',', ';'].includes(prev.v)) continue;
            if (RESERVED.has(t.v) || ofKeyword.has(i) || modifier(i)) continue;
            // Bound in every function that isn't an arrow, and the method is one.
            if (t.v === 'arguments') continue;
            used.add(t.v);
        }
        // Destructured declarations: `const { a, b: c } = …`, `let [x, y] = …`.
        for (let i = 0; i < scan.length; i++) {
            if (!['let', 'const', 'var'].includes(scan[i].v) || !scan[i + 1] || !['{', '['].includes(scan[i + 1].v)) continue;
            let depth = 0;
            for (let j = i + 1; j < scan.length; j++) {
                const t = scan[j];
                if (t.v === '{' || t.v === '[') depth++;
                else if (t.v === '}' || t.v === ']') { if (--depth === 0) break; }
                else if (t.t === 'id' && scan[j + 1] && [',', '}', ']', '='].includes(scan[j + 1].v)) declared.add(t.v);
            }
        }
        return { free: [...used].filter(n => !declared.has(n)), declared };
    }

    // What a module declares at its top level: every name (`declared`), its imports with the names they give, and its
    // constants written as a plain value, each with its declaration.
    function topLevel(text) {
        const scan = tokens(text), declared = new Set(), imports = new Set(), constants = new Map(), importList = [];
        let depth = 0;
        for (let i = 0; i < scan.length; i++) {
            const t = scan[i];
            if (t.v === '(' || t.v === '[' || t.v === '{') { depth++; continue; }
            if (t.v === ')' || t.v === ']' || t.v === '}') { depth--; continue; }
            if (depth !== 0 || t.t !== 'id') continue;
            const prev = scan[i - 1];
            if (prev && (prev.v === '.' || prev.v === '?.')) continue;
            if (t.v === 'import' && scan[i + 1] && scan[i + 1].v !== '(' && scan[i + 1].v !== '.') {
                const i0 = i;
                let j = i + 1;
                while (j < scan.length && !(scan[j].t === 'lit' && scan[j].v === 'str')) j++;
                if (j >= scan.length) break;
                const lit = scan[j];
                const end = text.indexOf(text[lit.at], lit.at + 1);
                const specifier = text.slice(lit.at + 1, end);
                const clauseTokens = scan.slice(i0 + 1, j).filter(x => x.v !== 'from');
                const names = [];
                for (let k = 0; k < clauseTokens.length; k++) {
                    const c = clauseTokens[k];
                    if (c.t !== 'id' || c.v === 'as') continue;
                    const after = clauseTokens[k + 1];
                    if (after && after.v === 'as') continue;
                    names.push(c.v);
                }
                const fromToken = scan.slice(i0 + 1, j).find(x => x.v === 'from');
                const clause = fromToken ? text.slice(scan[i0 + 1].at, fromToken.at).trim() : '';
                for (const name of names) imports.add(name);
                importList.push({ specifier, clause, names });
                i = j;
                continue;
            }
            if (t.v === 'function' || t.v === 'class') {
                const name = scan[i + 1] && scan[i + 1].v === '*' ? scan[i + 2] : scan[i + 1];
                if (name && name.t === 'id') declared.add(name.v);
                continue;
            }
            if (t.v === 'const' || t.v === 'let' || t.v === 'var') {
                // Every name up to the end of the declaration, erring toward more.
                let d = 0, naming = true;
                for (let j = i + 1; j < scan.length; j++) {
                    const s = scan[j];
                    if (s.v === '(' || s.v === '[' || s.v === '{') d++;
                    else if (s.v === ')' || s.v === ']' || s.v === '}') { if (--d < 0) break; }
                    else if (d === 0 && s.v === ';') break;
                    else if (d === 0 && s.v === '=') naming = false;
                    else if (d === 0 && s.v === ',') naming = true;
                    else if (d === 0 && s.t === 'id' && ['const', 'let', 'var', 'function', 'class', 'export', 'import'].includes(s.v)) break;
                    else if (naming && s.t === 'id' && scan[j - 1].v !== ':') declared.add(s.v);
                    if (d === 0 && !naming && j > i + 3 && text.slice(scan[j - 1].at, s.at).includes('\n') && s.t === 'id' && !['instanceof', 'in', 'of'].includes(s.v)
                        && !['.', '?.', '+', '-', '*', '/', '%', '=', '&', '|', '?', ':', ',', '(', '[', '<', '>', '!', '^', '~'].includes(scan[j - 1].v)) break;
                }
                // A constant that's a plain value: `const SPEED = 3;`, `const NAME = 'x'`, `const OFF = -1`.
                const [name, eq, a, b] = [scan[i + 1], scan[i + 2], scan[i + 3], scan[i + 4]];
                if (t.v === 'const' && name && name.t === 'id' && eq && eq.v === '=' && a) {
                    const literal = x => x && ((x.t === 'lit' && (x.v === 'num' || x.v === 'str')) || ['true', 'false', 'null'].includes(x.v));
                    const one = literal(a) ? a : a.v === '-' && b && b.t === 'lit' && b.v === 'num' ? b : null;
                    const after = one && scan[scan.indexOf(one) + 1];
                    const ends = !after || after.v === ';' || (text.slice(one.at, after.at).includes('\n') && !['.', '?.', '+', '-', '*', '/', '%', '?', '[', '(', '`', ',', '&', '|', '<', '>', '=', 'instanceof', 'in'].includes(after.v));
                    if (one && ends) {
                        const endAt = after ? (after.v === ';' ? after.at + 1 : after.at) : text.length;
                        constants.set(name.v, text.slice(t.at, endAt).trim().replace(/;?$/, ';'));
                    }
                }
            }
        }
        return { declared, imports, constants, importList };
    }

    function importsOf(text) { return topLevel(text).importList; }
})();
