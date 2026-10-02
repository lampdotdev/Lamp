/**
 * Forge's `look_at_app` tool for the bundled pi agent.
 *
 * The agent can't run anything itself. This tool asks Forge (over its local gateway) to build the app
 * with the agent's changes, open it, and report back: a picture of each window, what the app printed,
 * and any build errors or crash. Forge loads it with `pi -e` (see Agent.command).
 */

import { readFile } from "node:fs/promises";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

const lookAtApp = defineTool({
	name: "look_at_app",
	label: "Look at the app",
	description:
		"Builds the app with your changes, opens it, and shows you the result: a picture of its windows, " +
		"what it printed, and any build errors or crash. Takes up to a minute. Use it after a change to the " +
		"interface, or to check a fix you can't verify by reading the code. You get a few looks per request, " +
		"so make your edits first and don't use it for small changes you're sure of.",
	parameters: Type.Object({}),

	async execute(_toolCallId, _params, signal, _onUpdate, ctx) {
		const url = process.env.FORGE_LOOK_URL;
		if (!url) throw new Error("Forge isn't available to look at the app.");
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.FORGE_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: "{}",
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(600_000)]) : AbortSignal.timeout(600_000),
		});
		const reply = (await response.json()) as { text?: string; error?: string; screenshots?: string[] };
		if (!response.ok) throw new Error(reply.error ?? "Forge couldn't look at the app.");

		const content: ({ type: "text"; text: string } | { type: "image"; data: string; mimeType: string })[] = [
			{ type: "text", text: reply.text ?? "" },
		];
		const pictures = reply.screenshots ?? [];
		if (pictures.length > 0 && ctx.model && !ctx.model.input.includes("image")) {
			content.push({ type: "text", text: "This model can't view images, so the pictures of the windows were left out." });
		} else {
			for (const path of pictures) {
				content.push({ type: "image", data: (await readFile(path)).toString("base64"), mimeType: "image/png" });
			}
		}
		return { content, details: { screenshots: pictures } };
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(lookAtApp);
}
