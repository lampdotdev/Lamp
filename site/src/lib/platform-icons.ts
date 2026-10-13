import type { Platform } from "./ideas";

// The device an idea runs on, as a small line drawing in the manner of SF Symbols, on a 24-point grid. Shared by
// the ideas page as built and the script that fills in an opened wish.
const paths: Record<Platform, string> = {
  Mac: '<rect x="4" y="5" width="16" height="11" rx="1.6"/><path d="M2.5 19h19"/>',
  iPhone: '<rect x="6.5" y="2.5" width="11" height="19" rx="2.8"/><path d="M10.5 5h3"/>',
  iPad: '<rect x="4" y="2.5" width="16" height="19" rx="2.4"/><path d="M11 18.8h2"/>',
};

const names: Record<Platform, string> = { Mac: "For Mac", iPhone: "For iPhone", iPad: "For iPad" };

/** The drawing for an idea's platform, sized by `size` (Tailwind classes), with its meaning as its title. */
export const platformIcon = (platform: Platform, size = "size-5") =>
  `<svg role="img" aria-label="${names[platform]}" viewBox="0 0 24 24" class="${size} shrink-0 fill-none stroke-current stroke-[1.5] [stroke-linecap:round] [stroke-linejoin:round]"><title>${names[platform]}</title>${paths[platform]}</svg>`;
