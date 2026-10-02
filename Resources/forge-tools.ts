/**
 * Forge's tools for the bundled pi agent, loaded with `pi -e` (see Agent.command).
 *
 * - `look_at_app`: the agent can't run anything itself. This asks Forge (over its local gateway) to build
 *   the app with the agent's changes, open it, and report back: a picture of each window, what the app
 *   printed, and any build errors or crash.
 * - `delete_file`: pi's own tools can write and edit files but not remove one. This deletes a single file
 *   inside the app's folder, leaving alone the files Forge owns. The app's git history can bring it back
 *   (Undo).
 * - `list_versions`, `name_version`, `restore_version`: Forge saves a version of the app after every request.
 *   These let the agent see them, name one, and bring one back when the user asks. Forge does the work.
 * - `web_fetch`: reads a web page (or any URL) as text. Reading needs no approval.
 * - Shell commands (pi's `bash` tool) need the user's approval: before each one runs, this asks Forge, which
 *   shows the command in the app's chat with Allow / Allow All This Turn / Deny, and blocks it if denied.
 * - `plan`: the agent's checklist of what it's building, with the files behind each part. Forge reads the
 *   list from pi's event stream, shows it on the build card, and ticks parts as their files are written,
 *   so the tool itself has nothing to do.
 */

import { lstat, readFile, realpath, rm } from "node:fs/promises";
import path from "node:path";
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

const plan = defineTool({
	name: "plan",
	label: "Plan",
	description:
		"Shows the user what you're building, as a short checklist in Forge while they wait. For a new app, " +
		"call it once before writing any code with the 3 to 5 main parts, each in plain words the user would " +
		"use (what they'll be able to do, not file or type names), and the files you'll write for each part. " +
		"Forge ticks a part off when all of its files are written, so there's no need to call it again. " +
		"Call it again only if the plan changes; every call replaces the whole list.",
	parameters: Type.Object({
		parts: Type.Array(
			Type.Object({
				title: Type.String({ description: "One part of the app, under ten words, in the user's words" }),
				files: Type.Array(Type.String(), {
					description: "File names you'll write for this part, e.g. Scanner.swift. Each file belongs to one part.",
				}),
				done: Type.Optional(Type.Boolean({ description: "True to tick this part yourself" })),
			}),
		),
	}),

	async execute() {
		return { content: [{ type: "text", text: "The user can see the plan." }], details: undefined };
	},
});

const webFetch = defineTool({
	name: "web_fetch",
	label: "Read web page",
	description:
		"Reads a web page or other URL and returns its text (HTML is converted to plain text). Use it to read " +
		"documentation, a GitHub page, or an API response. Long pages are cut off at about 40,000 characters.",
	parameters: Type.Object({
		url: Type.String({ description: "The full URL, starting with http:// or https://" }),
	}),

	async execute(_toolCallId, params, signal) {
		if (!/^https?:\/\//i.test(params.url)) throw new Error("Only http and https URLs can be read.");
		const response = await fetch(params.url, {
			headers: { "User-Agent": "Forge (pi web_fetch)", Accept: "text/html,text/plain,application/json,*/*" },
			redirect: "follow",
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(60_000)]) : AbortSignal.timeout(60_000),
		});
		const type = response.headers.get("content-type") ?? "";
		let text = await response.text();
		if (type.includes("html")) {
			text = text
				.replace(/<(script|style|noscript|svg)[\s\S]*?<\/\1>/gi, " ")
				.replace(/<br\s*\/?>|<\/(p|div|li|h[1-6]|tr|section|article|pre)>/gi, "\n")
				.replace(/<[^>]+>/g, " ")
				.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
				.replace(/&quot;/g, '"').replace(/&#39;/g, "'")
				.replace(/[ \t]+/g, " ").replace(/\n\s*\n+/g, "\n\n").trim();
		}
		const limit = 40_000;
		const cut = text.length > limit;
		const body = cut ? text.slice(0, limit) + `\n\n[Cut off: showed ${limit} of ${text.length} characters.]` : text;
		const status = response.ok ? "" : `HTTP ${response.status}\n\n`;
		return { content: [{ type: "text", text: status + body }], details: undefined };
	},
});

/** Asks Forge to approve a shell command; resolves to an error message when it isn't approved. */
async function askForge(command: string, signal?: AbortSignal): Promise<string | undefined> {
	const url = process.env.FORGE_APPROVE_URL;
	if (!url) return "Shell commands need approval in Forge, and Forge isn't available.";
	try {
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.FORGE_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: JSON.stringify({ command }),
			// The user may take a while to answer; Forge itself never times out on their behalf.
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(3_600_000)]) : AbortSignal.timeout(3_600_000),
		});
		const reply = (await response.json()) as { allow?: boolean; reason?: string };
		return reply.allow ? undefined : (reply.reason ?? "The user didn't approve this command.");
	} catch {
		return "Couldn't ask the user to approve this command.";
	}
}

/** Files and folders Forge generates or depends on: never the agent's to delete. */
const protectedPaths = [".forge", ".git", ".build", "build", ".gitignore", "Package.swift", "build.sh", "Sources/ForgeSupport.swift"];

/** Files written or edited since this agent run started, as absolute paths. */
const writtenThisRun = new Set<string>();

const deleteFile = defineTool({
	name: "delete_file",
	label: "Delete file",
	description:
		"Deletes one file in the app's folder that is no longer needed, such as a source file whose code " +
		"moved elsewhere or a view that was removed. Use it instead of leaving an emptied file behind. " +
		"It can't delete folders, files outside the app's folder, or the files Forge generates.",
	parameters: Type.Object({
		path: Type.String({ description: "Path of the file, relative to the app's folder, e.g. Sources/CardsView.swift" }),
		confirm: Type.Optional(
			Type.Boolean({ description: "Set to true to delete a file you wrote or edited earlier in this request" }),
		),
	}),

	async execute(_toolCallId, params) {
		const root = await realpath(process.cwd());
		const target = path.resolve(root, params.path);
		const relative = path.relative(root, target);
		if (relative === "" || relative.startsWith("..") || path.isAbsolute(relative)) {
			throw new Error("Only files inside the app's folder can be deleted.");
		}
		if (protectedPaths.some((item) => relative === item || relative.startsWith(item + path.sep))) {
			throw new Error(`${relative} belongs to Forge and can't be deleted.`);
		}
		const info = await lstat(target).catch(() => undefined);
		if (!info) throw new Error(`There's no file at ${relative}.`);
		if (!info.isFile()) throw new Error(`${relative} isn't a file. Only single files can be deleted.`);
		// A folder on the way that is really a link could lead outside the app's folder.
		const folder = await realpath(path.dirname(target));
		if (folder !== root && !folder.startsWith(root + path.sep)) {
			throw new Error("Only files inside the app's folder can be deleted.");
		}
		// The usual mistake: deleting a "leftover" file that was in fact already replaced with new code.
		if (writtenThisRun.has(target) && !params.confirm) {
			throw new Error(
				`You wrote or edited ${relative} earlier in this request, so it holds your new code. ` +
					"It was not deleted. If it really should go, call delete_file again with confirm: true.",
			);
		}
		await rm(target);
		writtenThisRun.delete(target);
		return { content: [{ type: "text", text: `Deleted ${relative}.` }], details: undefined };
	},
});

/** Calls one of Forge's version endpoints and returns its reply as the tool's text. */
async function versions(endpoint: string, body: object, signal?: AbortSignal) {
	const url = process.env.FORGE_VERSIONS_URL;
	if (!url) throw new Error("Forge isn't available to manage versions.");
	const response = await fetch(url + endpoint, {
		method: "POST",
		headers: { Authorization: `Bearer ${process.env.FORGE_TOKEN ?? ""}`, "Content-Type": "application/json" },
		body: JSON.stringify(body),
		signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(60_000)]) : AbortSignal.timeout(60_000),
	});
	const reply = (await response.json()) as { text?: string; error?: string };
	if (!response.ok) throw new Error(reply.error ?? "Forge couldn't do that.");
	return { content: [{ type: "text" as const, text: reply.text ?? "" }], details: undefined };
}

const listVersions = defineTool({
	name: "list_versions",
	label: "List versions",
	description:
		"Lists the app's saved versions, newest first: an id, when it was made, its name if it has one, and " +
		"the request that made it. Forge saves one after every request.",
	parameters: Type.Object({}),

	async execute(_toolCallId, _params, signal) {
		return versions("", {}, signal);
	},
});

const nameVersion = defineTool({
	name: "name_version",
	label: "Name version",
	description:
		"Gives a version a short name the user will recognise, e.g. “Before the redesign” or “First working " +
		"sync”. Without `version`, it names the version this request makes, once Forge saves it. With a " +
		"version id from list_versions, it names that one: use the current one before a big or risky change.",
	parameters: Type.Object({
		name: Type.String({ description: "A few words, in the user's terms" }),
		version: Type.Optional(Type.String({ description: "A version id from list_versions" })),
	}),

	async execute(_toolCallId, params, signal) {
		return versions("/name", params, signal);
	},
});

const restoreVersion = defineTool({
	name: "restore_version",
	label: "Restore version",
	description:
		"Puts the app's files back as they were in an earlier version. Only use it when the user asks to go " +
		"back to an earlier version, never to undo your own attempt. Find the id with list_versions first. " +
		"Nothing is lost: the versions after it stay, so the user can go forward again.",
	parameters: Type.Object({
		version: Type.String({ description: "A version id from list_versions" }),
	}),

	async execute(_toolCallId, params, signal) {
		return versions("/restore", params, signal);
	},
});

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;
		const reason = await askForge(String((event.input as { command?: unknown }).command ?? ""), ctx.signal);
		return reason ? { block: true, reason } : undefined;
	});
	// Which files this run has written, for delete_file's check.
	pi.on("tool_call", async (event) => {
		const file = (event.input as { path?: unknown }).path;
		if ((event.toolName === "write" || event.toolName === "edit") && typeof file === "string") {
			writtenThisRun.add(path.resolve(await realpath(process.cwd()), file));
		}
		return undefined;
	});
	pi.registerTool(webFetch);
	pi.registerTool(lookAtApp);
	pi.registerTool(plan);
	pi.registerTool(deleteFile);
	pi.registerTool(listVersions);
	pi.registerTool(nameVersion);
	pi.registerTool(restoreVersion);
}
