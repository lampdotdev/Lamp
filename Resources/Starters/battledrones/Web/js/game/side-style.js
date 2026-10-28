
/** A side's name in a sentence ("Green takes an Uplink"). */
export const SIDE_NAME = { blue: "Blue", red: "Red", green: "Green", purple: "Purple" };

/** A side's text colour on the HUD's dark panels. */
export const SIDE_CSS = { blue: "#7ec1ff", red: "#ff8a7a", green: "#86eea0", purple: "#c9a2ff" };

/** A side's portrait of a unit or building (ICONS.md): blue's in assets/icons, the others' in a folder each. */
export const iconUrl = (kind, f) => `assets/icons/${f === "blue" ? "" : `${f}/`}${kind}.webp`;
