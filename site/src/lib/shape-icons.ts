// A small line drawing for each kind of situation in the first-idea section (lib/situations.js), drawn on a
// 24-point grid in the lamp's amber. Shared by the page as built and the script that adds later rounds.
const paths: Record<string, string> = {
  checking: '<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  chasing: '<path d="M4 6h16v10H8l-4 4z"/><path d="M9 11h6"/>',
  remembering: '<path d="M7 3h10v18l-5-4-5 4z"/>',
  copying: '<rect x="3" y="4" width="8" height="10" rx="1.5"/><rect x="13" y="10" width="8" height="10" rx="1.5"/><path d="M9 17h3m0 0-2-2m2 2-2 2"/>',
  gathering: '<path d="M4 4l6 6M20 4l-6 6M12 21v-6"/><circle cx="12" cy="12" r="2.5"/>',
  repeating: '<path d="M4 12a8 8 0 0 1 14-5.3M20 12a8 8 0 0 1-14 5.3"/><path d="M18 3v4h-4M6 21v-4h4"/>',
  tidying: '<path d="M3 7h7l2 2h9v10H3z"/><path d="M8 14h8"/>',
  finding: '<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5.5 5.5"/>',
  collecting: '<path d="M12 20s-7.5-4.5-7.5-10A4 4 0 0 1 12 7.6 4 4 0 0 1 19.5 10c0 5.5-7.5 10-7.5 10z"/>',
  planning: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  habits: '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l3 3 5-6"/>',
  household: '<path d="M3 11l9-7 9 7"/><path d="M5 9.5V20h14V9.5"/><path d="M10 20v-5h4v5"/>',
};

export const shapeIcon = (shape: string) =>
  `<svg aria-hidden="true" viewBox="0 0 24 24" class="mt-0.5 size-5 shrink-0 fill-none stroke-[#ffcf7a] stroke-[1.6] [stroke-linecap:round] [stroke-linejoin:round]">${paths[shape] ?? ""}</svg>`;
