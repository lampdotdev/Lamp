// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.

export function mountCineToggle(root, onToggle) {
    const b = document.createElement("button");
    b.className = "zb cine";
    b.innerHTML = `<span class="ci">🎥</span>`;
    const stack = root.querySelector(".zoombtns");
    const jump = stack?.querySelector(".jump");
    if (jump)
        stack.insertBefore(b, jump);
    else
        stack?.appendChild(b);
    b.addEventListener("pointerdown", (e) => e.stopPropagation());
    b.addEventListener("click", () => onToggle());
    let last = "";
    return {
        set(on, held) {
            const key = `${on}|${held}`;
            if (key === last)
                return;
            last = key;
            b.classList.toggle("on", on);
            b.classList.toggle("held", on && held);
            b.setAttribute("aria-pressed", String(on));
            b.title = !on
                ? "Cinematic camera: off (C)"
                : held
                    ? "Cinematic camera: back in a moment — or tap to switch off (C)"
                    : "Cinematic camera: on (C)";
        },
        destroy() {
            b.remove();
        }
    };
}
