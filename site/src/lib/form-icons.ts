import type { Form } from "./ideas";

// Where an idea lives, as a small line drawing in the manner of SF Symbols, on a 24-point grid. Shared by the
// ideas page as built and the script that fills in an opened wish.
const paths: Record<Form, string> = {
  Mac: '<rect x="4" y="5" width="16" height="11" rx="1.6"/><path d="M2.5 19h19"/>',
  "Menu bar": '<rect x="3" y="3.5" width="18" height="17" rx="2.5"/><path d="M3 7.5h18"/><rect x="12.5" y="10" width="6" height="7" rx="1.2"/>',
  Widget: '<rect x="3.5" y="3.5" width="7.5" height="7.5" rx="2"/><rect x="13" y="3.5" width="7.5" height="7.5" rx="2"/><rect x="3.5" y="13" width="17" height="7.5" rx="2"/>',
  iPhone: '<rect x="6.5" y="2.5" width="11" height="19" rx="2.8"/><path d="M10.5 5h3"/>',
  iPad: '<rect x="4" y="2.5" width="16" height="19" rx="2.4"/><path d="M11 18.8h2"/>',
  Game: '<path d="M7.5 8h9a4.5 4.5 0 0 1 4.5 4.5v1.2a3.3 3.3 0 0 1-6 1.9L14.2 14H9.8l-.8 1.6a3.3 3.3 0 0 1-6-1.9v-1.2A4.5 4.5 0 0 1 7.5 8z"/><path d="M8 10.3v3.4M6.3 12h3.4"/><path d="M15.2 11.2h.01M17 12.8h.01" stroke-width="2.4"/>',
};

const names: Record<Form, string> = {
  Mac: "A Mac app",
  "Menu bar": "In the menu bar",
  Widget: "A desktop widget",
  iPhone: "An iPhone app",
  iPad: "An iPad app",
  Game: "A game",
};

/** The drawing for where an idea lives, sized by `size` (Tailwind classes), with its meaning as its title. */
export const formIcon = (form: Form, size = "size-5") =>
  `<svg role="img" aria-label="${names[form]}" viewBox="0 0 24 24" class="${size} shrink-0 fill-none stroke-current stroke-[1.5] [stroke-linecap:round] [stroke-linejoin:round]"><title>${names[form]}</title>${paths[form]}</svg>`;
