/**
 * Forge's tools for the bundled pi agent, loaded with `pi -e` (see Agent.command).
 *
 * - `look_at_app`: the agent can't run anything itself. This asks Forge (over its local gateway) to build
 *   the app with the agent's changes, open it, and report back: a picture of each window, what the app
 *   printed, and any build errors or crash.
 * - `use_app`: clicks, types and presses keys in the open app's front window, at points in its latest picture.
 *   Forge passes the actions to the app, which performs them on itself (ForgeDriver in ForgeSupport), so no
 *   Accessibility permission is needed. The reply is what happened and a fresh picture.
 * - `delete_file`: pi's own tools can write and edit files but not remove one. This deletes a single file
 *   inside the app's folder, leaving alone the files Forge owns. The app's git history can bring it back
 *   (Undo).
 * - `list_versions`, `name_version`, `restore_version`: Forge saves a version of the app after every request.
 *   These let the agent see them, name one, and bring one back when the user asks. Forge does the work.
 * - `web_fetch`: reads a web page (or any URL) as text. Reading needs no approval.
 * - pi's file tools (read, edit, write, grep, find, ls) are checked before they run: inside the app's folder
 *   they need nothing, outside it Forge decides (system files are fine, Forge's own keys never, the rest asks
 *   the user), and the running app's log and pictures follow the user's privacy settings.
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
		"interface, or to check a fix you can't verify by reading the code. Each look that has to rebuild takes " +
		"a while, so make your edits first and don't use it for small changes you're sure of.",
	parameters: Type.Object({}),

	async execute(_toolCallId, _params, signal, _onUpdate, ctx) {
		const url = process.env.FORGE_LOOK_URL;
		if (!url) throw new Error("Lamp isn't available to look at the app.");
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.FORGE_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: "{}",
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(600_000)]) : AbortSignal.timeout(600_000),
		});
		return pictureReply(response, ctx.model, "Lamp couldn't look at the app.");
	},
});

/** Forge's answer to look_at_app or use_app: its text, then the pictures it names (if the model can see them). */
async function pictureReply(response: Response, model: { input: string[] } | undefined, failure: string) {
	const reply = (await response.json()) as { text?: string; error?: string; screenshots?: string[] };
	if (!response.ok) throw new Error(reply.error ?? failure);

	const content: ({ type: "text"; text: string } | { type: "image"; data: string; mimeType: string })[] = [
		{ type: "text", text: reply.text ?? "" },
	];
	const pictures = reply.screenshots ?? [];
	if (pictures.length > 0 && model && !model.input.includes("image")) {
		content.push({ type: "text", text: "This model can't view images, so the pictures of the windows were left out." });
	} else {
		for (const path of pictures) {
			content.push({ type: "image", data: (await readFile(path)).toString("base64"), mimeType: "image/png" });
		}
	}
	return { content, details: { screenshots: pictures } };
}

const useApp = defineTool({
	name: "use_app",
	label: "Use the app",
	description:
		"Uses the open app the way a person would: clicks, types, presses keys, scrolls and picks from menus in its " +
		"front window, then shows you what each action landed on, whether anything changed, a fresh picture, and " +
		"what the app printed meanwhile. x and y are pixels in the latest picture of the front window from " +
		"look_at_app or use_app: aim at the middle of what you want. Use it to check that something works, not " +
		"just how it looks: click a column header and see whether the list re-sorts, fill in a form and submit it. " +
		"Clicking a row of a list, table or sidebar selects it; double-clicking opens it. Keys and typing go to " +
		"whatever has keyboard focus. " +
		"Menus are read out to you, never opened: click a pop-up or pull-down button, or right_click something, and " +
		"you get its items; repeat the same action with `item` set to pick one (\"Sub > Deep\" for a submenu). " +
		"`menu` does the same for the menu bar: without `item` it lists every command, with `item` like " +
		"\"File > Export…\" it picks one. " +
		"`bar_icon` is for an app that lives in the menu bar: it opens the panel behind the app's icon there, which " +
		"becomes the first picture and takes clicks and keys like a window (escape closes it); if the icon shows a " +
		"menu instead, it lists it, and `item` picks from it. " +
		"When a dialog or sheet opens it becomes the first picture and takes the clicks and keys: click one of its " +
		"buttons, or press escape to cancel. The system's save panel can only be answered with return (save where " +
		"it says) or escape. It can't drag. It uses the app as last built: after editing code, call look_at_app " +
		"first so your changes are built and open. If it says nothing changed, the click most likely missed: look " +
		"at the picture and aim again before changing any code.",
	parameters: Type.Object({
		actions: Type.Array(
			Type.Object({
				action: Type.Union([
					Type.Literal("click"), Type.Literal("double_click"), Type.Literal("right_click"), Type.Literal("menu"),
					Type.Literal("bar_icon"),
					Type.Literal("type"), Type.Literal("key"), Type.Literal("scroll"), Type.Literal("wait"),
				]),
				x: Type.Optional(Type.Number({ description: "click, double_click, right_click, scroll: pixels from the picture's left" })),
				y: Type.Optional(Type.Number({ description: "click, double_click, right_click, scroll: pixels from the picture's top" })),
				item: Type.Optional(Type.String({ description: "click, right_click, menu, bar_icon: the menu item to pick by name, e.g. \"Export…\" or \"View > Zoom In\". Leave out to list the items." })),
				text: Type.Optional(Type.String({ description: "type: the text, typed into whatever has focus (click a field first)" })),
				key: Type.Optional(Type.String({ description: "key: return, escape, tab, delete, space, up, down, left, right, or a letter, with modifiers like cmd+a" })),
				amount: Type.Optional(Type.Number({ description: "scroll: points, positive scrolls down; wait: seconds" })),
			}),
			{ minItems: 1, maxItems: 30 },
		),
	}),

	async execute(_toolCallId, params, signal, _onUpdate, ctx) {
		const url = process.env.FORGE_USE_URL;
		if (!url) throw new Error("Lamp isn't available to use the app.");
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.FORGE_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: JSON.stringify({ actions: params.actions }),
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(120_000)]) : AbortSignal.timeout(120_000),
		});
		return pictureReply(response, ctx.model, "Lamp couldn't use the app.");
	},
});

const plan = defineTool({
	name: "plan",
	label: "Plan",
	description:
		"Shows the user what you're building, as a short checklist in Lamp while they wait. For a new app, " +
		"call it once before writing any code with the 3 to 5 main parts, each in plain words the user would " +
		"use (what they'll be able to do, not file or type names), and the files you'll write for each part. " +
		"Lamp ticks a part off when all of its files are written, so there's no need to call it again. " +
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
			headers: { "User-Agent": "Lamp (pi web_fetch)", Accept: "text/html,text/plain,application/json,*/*" },
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
	if (!url) return "Shell commands need approval in Lamp, and Lamp isn't available.";
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

/** pi's own file tools: where each one points is checked before it runs. */
const fileTools = new Set(["read", "edit", "write", "grep", "find", "ls"]);

/** The path with `~`, `..` and links worked out; a link inside the app's folder could lead out of it. */
async function resolved(given: string): Promise<string> {
	const expanded = given === "~" || given.startsWith("~/") ? path.join(process.env.HOME ?? "", given.slice(1)) : given;
	let existing = path.resolve(expanded);
	const rest: string[] = [];
	// A file about to be created doesn't exist yet: work out the nearest folder that does.
	for (;;) {
		try {
			return path.join(await realpath(existing), ...rest);
		} catch {
			const parent = path.dirname(existing);
			if (parent === existing) return path.resolve(expanded);
			rest.unshift(path.basename(existing));
			existing = parent;
		}
	}
}

/**
 * Asks Forge whether a file tool may touch a path; resolves to an error message when it may not. Paths inside the
 * app's folder need no asking, except what the running app saves there (its log and pictures), which the user
 * can keep from the agent in Forge's settings.
 */
async function checkFile(tool: string, given: string, signal?: AbortSignal): Promise<string | undefined> {
	const [target, home] = await Promise.all([resolved(given), resolved(".")]);
	const inside = target === home || target.startsWith(home + path.sep);
	if (inside && !target.startsWith(path.join(home, ".forge", "runtime") + path.sep)) return undefined;
	const url = process.env.FORGE_APPROVE_URL;
	if (!url) return inside ? undefined : "Files outside the app's folder need approval in Lamp, and Lamp isn't available.";
	try {
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.FORGE_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: JSON.stringify({ file_tool: tool, path: given }),
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(3_600_000)]) : AbortSignal.timeout(3_600_000),
		});
		const reply = (await response.json()) as { allow?: boolean; reason?: string };
		return reply.allow ? undefined : (reply.reason ?? "The user didn't allow that.");
	} catch {
		return "Couldn't ask the user about that file.";
	}
}

/** Files and folders Forge generates or depends on: never the agent's to delete. */
const protectedPaths = [".forge", ".git", ".build", "build", ".gitignore", "Package.swift", "build.sh", "Sources/ForgeSupport.swift"];

const deleteFile = defineTool({
	name: "delete_file",
	label: "Delete file",
	description:
		"Deletes one file in the app's folder that is no longer needed, such as a source file whose code " +
		"moved elsewhere or a view that was removed. Use it instead of leaving an emptied file behind. " +
		"It can't delete folders, files outside the app's folder, or the files Lamp generates.",
	parameters: Type.Object({
		path: Type.String({ description: "Path of the file, relative to the app's folder, e.g. Sources/CardsView.swift" }),
	}),

	async execute(_toolCallId, params) {
		const root = await realpath(process.cwd());
		const target = path.resolve(root, params.path);
		const relative = path.relative(root, target);
		if (relative === "" || relative.startsWith("..") || path.isAbsolute(relative)) {
			throw new Error("Only files inside the app's folder can be deleted.");
		}
		if (protectedPaths.some((item) => relative === item || relative.startsWith(item + path.sep))) {
			throw new Error(`${relative} belongs to Lamp and can't be deleted.`);
		}
		const info = await lstat(target).catch(() => undefined);
		if (!info) throw new Error(`There's no file at ${relative}.`);
		if (!info.isFile()) throw new Error(`${relative} isn't a file. Only single files can be deleted.`);
		// A folder on the way that is really a link could lead outside the app's folder.
		const folder = await realpath(path.dirname(target));
		if (folder !== root && !folder.startsWith(root + path.sep)) {
			throw new Error("Only files inside the app's folder can be deleted.");
		}
		await rm(target);
		return { content: [{ type: "text", text: `Deleted ${relative}.` }], details: undefined };
	},
});

/** Calls one of Forge's version endpoints and returns its reply as the tool's text. */
async function versions(endpoint: string, body: object, signal?: AbortSignal) {
	const url = process.env.FORGE_VERSIONS_URL;
	if (!url) throw new Error("Lamp isn't available to manage versions.");
	const response = await fetch(url + endpoint, {
		method: "POST",
		headers: { Authorization: `Bearer ${process.env.FORGE_TOKEN ?? ""}`, "Content-Type": "application/json" },
		body: JSON.stringify(body),
		signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(60_000)]) : AbortSignal.timeout(60_000),
	});
	const reply = (await response.json()) as { text?: string; error?: string };
	if (!response.ok) throw new Error(reply.error ?? "Lamp couldn't do that.");
	return { content: [{ type: "text" as const, text: reply.text ?? "" }], details: undefined };
}

const listVersions = defineTool({
	name: "list_versions",
	label: "List versions",
	description:
		"Lists the app's saved versions, newest first: an id, when it was made, its name if it has one, and " +
		"the request that made it. Lamp saves one after every request.",
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
		"sync”. Without `version`, it names the version this request makes, once Lamp saves it. With a " +
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
		if (fileTools.has(event.toolName)) {
			const given = (event.input as { path?: unknown }).path;
			if (typeof given !== "string" || given === "") return undefined;   // no path: the app's own folder
			const reason = await checkFile(event.toolName, given, ctx.signal);
			return reason ? { block: true, reason } : undefined;
		}
		if (event.toolName !== "bash") return undefined;
		const reason = await askForge(String((event.input as { command?: unknown }).command ?? ""), ctx.signal);
		return reason ? { block: true, reason } : undefined;
	});
	pi.registerTool(webFetch);
	pi.registerTool(lookAtApp);
	pi.registerTool(useApp);
	pi.registerTool(plan);
	pi.registerTool(deleteFile);
	pi.registerTool(listVersions);
	pi.registerTool(nameVersion);
	pi.registerTool(restoreVersion);
}
