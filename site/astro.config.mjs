// lamp.dev: one static page, deployed as its own Vercel project.
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  site: "https://lamp.dev",
  output: "static",
  vite: { plugins: [tailwindcss()] },
});
