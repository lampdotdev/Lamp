// Lamp's skills as `lamp skill` prints them: read from Lamp's own folder (Resources/skills), and put together the way
// Lamp's app puts them together (`Skills.parse`, `Skills.assembled`, `Skills.section`). A skill made of sections of
// others names them in its frontmatter ("game#Fun; game-ui#Proof") and has them put where its body says
// `{{sections}}`, so each section is written in one place.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const SKILLS = join(dirname(fileURLToPath(import.meta.url)), "..", "Resources", "skills");

/** A SKILL.md: frontmatter between `---` lines, a field a line, then the instructions. */
function parse(text) {
  const lines = text.split("\n");
  const close = lines.indexOf("---", 1);
  if (lines[0] !== "---" || close < 0) return null;
  const fields = {};
  for (const line of lines.slice(1, close)) {
    const colon = line.indexOf(":");
    if (colon > 0) fields[line.slice(0, colon).trim()] = line.slice(colon + 1).trim();
  }
  if (!fields.name || !fields.description) return null;
  return { name: fields.name, description: fields.description, sections: fields.sections ?? null, body: lines.slice(close + 1).join("\n").trim() };
}

/** One section of a skill, as "skill#Heading": its heading, made a second-level one, and what's under it. */
function section(name, skills) {
  const at = name.indexOf("#");
  const source = at < 0 ? null : skills.get(name.slice(0, at))?.body;
  if (source == null) return null;
  const title = name.slice(at + 1), lines = source.split("\n");
  // A line of a code block is never a heading, whatever it starts with.
  let fenced = false;
  const headings = [];
  lines.forEach((line, index) => {
    if (line.startsWith("```")) { fenced = !fenced; return; }
    const marks = /^(#+) /.exec(line);
    if (!fenced && marks) headings.push({ index, level: marks[1].length, title: line.slice(marks[1].length).trim() });
  });
  if (!title) {
    // The text before the skill's first section.
    const first = headings.find((heading) => heading.level === 1), second = headings.find((heading) => heading.level === 2);
    const start = first ? first.index + 1 : 0, end = second ? second.index : lines.length;
    return lines.slice(start, Math.max(start, end)).join("\n").trim() || null;
  }
  const found = headings.findIndex((heading) => heading.title === title && heading.level > 1);
  if (found < 0) return null;
  const heading = headings[found], next = headings.slice(found + 1).find((later) => later.level <= heading.level);
  return `## ${heading.title}\n\n${lines.slice(heading.index + 1, next ? next.index : lines.length).join("\n").trim()}`;
}

/** Every skill by name, each as Lamp's app hands it over. Empty when Lamp's skills aren't beside this copy of lamp. */
export function allSkills() {
  const skills = new Map();
  if (!existsSync(SKILLS)) return skills;
  for (const entry of readdirSync(SKILLS, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    let skill = null;
    try { skill = parse(readFileSync(join(SKILLS, entry.name, "SKILL.md"), "utf8")); } catch {}
    if (skill) skills.set(skill.name, skill);
  }
  // Sections come from the skills as they're written, never from one already put together.
  const written = new Map(skills);
  for (const skill of written.values()) {
    if (!skill.sections) continue;
    const text = skill.sections.split(";").map((name) => name.trim()).filter(Boolean).map((name) => section(name, written)).filter(Boolean).join("\n\n");
    skills.set(skill.name, { ...skill, body: skill.body.includes("{{sections}}") ? skill.body.replaceAll("{{sections}}", text) : `${skill.body}\n\n${text}` });
  }
  return skills;
}
