import { isTypingInField } from './city-config.js';

const DEAD_ZONE = 0.15;
const BUTTON_COUNT = 17;

function axis(value) {
  return Number.isFinite(value) ? Math.max(-1, Math.min(1, value)) : 0;
}

function stick(pad, offset) {
  const x = axis(pad.axes?.[offset]), y = axis(pad.axes?.[offset + 1]);
  const distance = Math.hypot(x, y);
  const strength = Math.max(0, (Math.min(distance, 1) - DEAD_ZONE) / (1 - DEAD_ZONE));
  return distance ? { x: x / distance * strength, y: y / distance * strength } : { x: 0, y: 0 };
}

function buttonValue(pad, index) {
  const button = pad.buttons?.[index];
  return Number.isFinite(button?.value) ? Math.max(0, Math.min(1, button.value)) : button?.pressed ? 1 : 0;
}

function buttons(pad) {
  return Array.from({ length: BUTTON_COUNT }, (_, i) => Boolean(pad.buttons?.[i]?.pressed) || buttonValue(pad, i) > 0.5);
}

class GamepadControls {
  constructor(controllerManager, cameraSystem, callbacks = {}) {
    this.controller = controllerManager;
    this.camera = cameraSystem;
    this.callbacks = callbacks;
    this.connected = false;
    this.enabled = true;
    this.padIndex = null;
    this.padId = null;
    this.previousButtons = [];
    this.suppressedButtons = [];
    this.syncButtons = true;
    this.revision = 0;
    this.focused = typeof document.hasFocus !== 'function' || document.hasFocus();
    this.lastRumble = 0;
    this.boostPulse = 0;

    window.addEventListener('blur', () => {
      this.focused = false;
      this.reset();
    });
    window.addEventListener('focus', () => {
      this.focused = true;
      this.reset();
    });
    document.addEventListener('visibilitychange', () => this.reset());
  }

  readPad() {
    // Some browsers expose the API but reject it through Permissions Policy.
    try {
      if (typeof navigator === 'undefined' || typeof navigator.getGamepads !== 'function') return null;
      const pads = navigator.getGamepads();
      let first = null;
      for (let i = 0; i < (pads?.length || 0); i++) {
        const pad = pads[i];
        if (!pad?.connected || pad.mapping !== 'standard') continue;
        if (pad.index === this.padIndex && pad.id === this.padId) return pad;
        if (!first) first = pad;
      }
      return first;
    } catch {
      return null;
    }
  }

  reset() {
    this.revision++;
    this.controller.clearGamepadInput();
    const pad = this.readPad();
    if (pad && pad.index === this.padIndex && pad.id === this.padId) {
      this.previousButtons = buttons(pad);
      this.suppressedButtons = this.previousButtons.slice();
      this.syncButtons = false;
    } else {
      this.syncButtons = true;
    }
  }

  // Lamp: shakes the controller. strong is the big low motor, weak the small fast one, each 0-1, for ms milliseconds
  rumble(strong, weak, ms, force = false) {
    const now = performance.now();
    if (!force && now - this.lastRumble < 90) return;
    this.lastRumble = now;
    const pad = this.readPad();
    const actuator = pad?.vibrationActuator;
    if (!actuator || typeof actuator.playEffect !== 'function') return;
    actuator.playEffect('dual-rumble', {
      startDelay: 0,
      duration: Math.round(ms),
      strongMagnitude: Math.max(0, Math.min(1, strong)),
      weakMagnitude: Math.max(0, Math.min(1, weak))
    }).catch(() => {});
  }

  setEnabled(enabled) {
    enabled = Boolean(enabled);
    if (enabled === this.enabled) return;
    this.enabled = enabled;
    this.reset();
  }

  update(dt) {
    const pad = this.readPad();
    const connected = Boolean(pad);
    const changedPad = pad ? pad.index !== this.padIndex || pad.id !== this.padId : this.connected;
    if (changedPad) {
      this.controller.clearGamepadInput();
      this.padIndex = pad ? pad.index : null;
      this.padId = pad ? pad.id : null;
      this.syncButtons = true;
    }
    this.connected = connected;
    if (!pad) return;

    const pressed = buttons(pad);
    if (this.syncButtons) {
      // Connecting, switching pads, or resetting must not turn a held button into a fresh action.
      this.previousButtons = pressed.slice();
      this.suppressedButtons = pressed.slice();
      this.syncButtons = false;
    }
    for (let i = 0; i < BUTTON_COUNT; i++) if (!pressed[i]) this.suppressedButtons[i] = false;
    const edge = (i) => pressed[i] && !this.previousButtons[i] && !this.suppressedButtons[i];
    const held = (i) => pressed[i] && !this.suppressedButtons[i];
    // Lamp: laid out like GTA V on the Xbox, for any controller paired with the Mac. Standard mapping: 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 LT, 7 RT, 8 View,
    // 9 Menu, 10 L3, 11 R3, 12-15 d-pad up, down, left, right.
    // Capture edges before callbacks: changing mode or opening the map may synchronously call reset().
    const mode = this.controller.activeMode;
    const toggleMap = edge(9), closeMap = edge(1);
    const enterExit = edge(3), cycleCamera = edge(8), recenter = edge(11);
    const horn = mode === 'car' && edge(10);
    const changeVehicle = Number(Boolean(edge(15))) - Number(Boolean(edge(14)));
    const cycleTime = Number(Boolean(edge(12))) - Number(Boolean(edge(13)));
    this.previousButtons = pressed;

    const target = document.activeElement;
    const typing = isTypingInField({ target }) || target?.tagName === 'TEXTAREA' || target?.isContentEditable;
    if (!this.focused || document.hidden || (typeof document.hasFocus === 'function' && !document.hasFocus()) || typing) {
      this.suppressedButtons = pressed.slice();
      this.controller.clearGamepadInput();
      return;
    }

    const revision = this.revision;
    if (toggleMap) {
      this.controller.clearGamepadInput();
      this.callbacks.onToggleMap?.();
      return;
    }
    if (!this.enabled) {
      this.controller.clearGamepadInput();
      for (let i = 0; i < BUTTON_COUNT; i++) if (i !== 1 && i !== 9) this.suppressedButtons[i] = pressed[i];
      if (closeMap) this.callbacks.onCloseMap?.();
      return;
    }
    if (enterExit) {
      this.rumble(0.2, 0.3, 90, true);
      this.callbacks.onEnterExit?.();
    }
    if (revision !== this.revision) return;
    if (changeVehicle) {
      this.rumble(0, 0.25, 60, true);
      this.callbacks.onChangeVehicle?.(changeVehicle);
    }
    if (revision !== this.revision) return;
    if (cycleCamera) this.callbacks.onCycleCamera?.(1);
    if (revision !== this.revision) return;
    if (recenter) this.camera.resetOrbit();
    if (horn) {
      this.callbacks.onHorn?.();
      this.rumble(0, 0.35, 120, true);
    }
    if (cycleTime) this.callbacks.onCycleTime?.(cycleTime);
    if (revision !== this.revision) return;

    const movement = stick(pad, 0), look = stick(pad, 2);
    const rt = buttonValue(pad, 7), lt = buttonValue(pad, 6);
    let drive = 0, turn = movement.x, vertical = 0, boosting = false, jump = false, handbrake = false;
    if (mode === 'person') {
      // LS walks, A sprints, X jumps
      drive = -movement.y;
      boosting = held(0);
      jump = held(2);
    } else if (mode === 'car') {
      // RT gas, LT brake / reverse, LS steers, RB handbrake, A boost, L3 horn
      drive = rt - lt;
      boosting = held(0);
      handbrake = held(5);
    } else if (mode === 'cyclist') {
      // RT pedals, LT brakes, A pedals harder
      drive = Math.max(rt, held(0) ? 1 : 0) - lt;
      boosting = held(0);
    } else if (mode === 'helicopter') {
      // RT climbs, LT descends, LS pitches and turns, LB / RB turn too, A boosts
      drive = -movement.y;
      vertical = rt - lt;
      turn = Math.max(-1, Math.min(1, turn + (held(5) ? 1 : 0) - (held(4) ? 1 : 0)));
      boosting = held(0);
    }
    this.controller.setGamepadInput('forward', Math.max(0, drive));
    this.controller.setGamepadInput('backward', Math.max(0, -drive));
    this.controller.setGamepadInput('left', Math.max(0, -turn));
    this.controller.setGamepadInput('right', Math.max(0, turn));
    this.controller.setGamepadInput('up', mode === 'person' ? Number(jump) : Math.max(0, vertical));
    this.controller.setGamepadInput('down', Math.max(0, -vertical));
    this.controller.setGamepadInput('boost', Number(Boolean(boosting)));
    this.controller.handbrake = handbrake;
    // A light purr while boosting a vehicle that's moving, a rougher one while the handbrake slides the car
    const moving = Math.abs(drive) > 0.2 || Math.abs(vertical) > 0.2;
    const sliding = handbrake && Math.abs(this.controller.getActiveEntity()?.speed || 0) > 3;
    if ((boosting && moving && mode !== 'person') || sliding) {
      this.boostPulse -= Number.isFinite(dt) ? dt : 0;
      if (this.boostPulse <= 0) {
        this.boostPulse = 0.25;
        if (sliding) this.rumble(0.35, 0.15, 260, true);
        else this.rumble(0.12, 0.3, 260, true);
      }
    } else {
      this.boostPulse = 0;
    }
    this.camera.applyGamepadInput(look.x, look.y, 0, Number.isFinite(dt) ? Math.max(0, Math.min(0.1, dt)) : 0);
  }
}

export { GamepadControls };
