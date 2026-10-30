// The card shown while the game is made. A part that changes as the game is played looks like this: a class whose
// object holds its state, its look read where it's used, and the module ending with hot(import.meta).accept(), so a
// change to its methods goes into the running game (lamp-game.js, "Changes while it's played").
import { hot } from './lamp-game.js';

const LOOK = `
  .lamp-making { position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 12px; pointer-events: none; z-index: 5; color: #fff;
    font-family: -apple-system, system-ui, sans-serif; }
  .lamp-making svg { width: 64px; height: 64px; color: rgba(255, 255, 255, 0.55); }
  .lamp-making h1 { margin: 0; font-size: 34px; font-weight: 700; }
  .lamp-making p { margin: 0; font-size: 20px; color: rgba(255, 255, 255, 0.55); }`;

export class Making {
    constructor(name) {
        this.style = document.createElement('style');
        this.card = document.createElement('div');
        this.card.className = 'lamp-making';
        this.card.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round">'
            + '<g transform="rotate(40 12 12)"><rect x="10.8" y="8.5" width="2.4" height="13" rx="1.2"/>'
            + '<path d="M7 3.5h8.5l2.5 2.2v2.8H7z"/></g></svg>'
            + '<h1></h1><p>Lamp is making this game.</p>';
        this.card.querySelector('h1').textContent = name;
        document.head.append(this.style);
        document.body.append(this.card);
    }

    update() {
        if (this.style.textContent !== LOOK) this.style.textContent = LOOK;
    }
}

hot(import.meta).accept();
