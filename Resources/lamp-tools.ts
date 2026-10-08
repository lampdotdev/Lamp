/**
 * Lamp's tools for the bundled pi agent, loaded with `pi -e` (see Agent.command).
 *
 * - `look_at_app`: the agent can't run anything itself. This asks Lamp (over its local gateway) to build
 *   the app with the agent's changes, open it, and report back: a picture of each window, what the app
 *   printed, and any build errors or crash.
 * - `use_app`: clicks, types and presses keys in the open app's front window, at points in its latest picture.
 *   Lamp passes the actions to the app, which performs them on itself (LampDriver in LampSupport), so no
 *   Accessibility permission is needed. The reply is what happened and a fresh picture.
 * - `delete_file`: pi's own tools can write and edit files but not remove one. This deletes a single file
 *   inside the app's folder, leaving alone the files Lamp owns. The app's git history can bring it back
 *   (Undo).
 * - `list_versions`, `name_version`, `restore_version`: Lamp saves a version of the app after every request.
 *   These let the agent see them, name one, and bring one back when the user asks. Lamp does the work.
 * - `read_notes`, `save_notes`: Lamp keeps short notes about the person and about this app, and tells the agent
 *   in a line what they cover. These open them when a request needs them, and replace them.
 * - `offer_setup`: asks Lamp to show the person a card in the chat for setting up a kind of AI the app can't
 *   use yet (a key, a download, a sign-in). Lamp decides whether to show it and says what happened.
 * - `web_fetch`: reads a web page (or any URL) as text. Reading needs no approval.
 * - pi's file tools (read, edit, write, grep, find, ls) are checked before they run: inside the app's folder
 *   they need nothing, outside it Lamp decides (system files are fine, Lamp's own keys never, the rest asks
 *   the user), and the running app's log and pictures follow the user's privacy settings.
 * - Shell commands (pi's `bash` tool) need the user's approval: before each one runs, this asks Lamp, which
 *   shows the command in the app's chat with Allow / Allow All This Turn / Deny, and blocks it if denied.
 * - `plan`: the agent's checklist of what it's building, with the files behind each part. Lamp reads the
 *   list from pi's event stream, shows it on the build card, and ticks parts as their files are written,
 *   so the tool itself has nothing to do.
 */

import { readFileSync } from "node:fs";
import { lstat, readFile, realpath, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * The tools' names, descriptions and schemas come from lamp-tools.json, next to this file in Lamp's bundle
 * (Lamp says where with LAMP_TOOLS_JSON). Lamp's MCP endpoint serves the same file to Claude Code and Codex,
 * so there is one definition of each tool. Only the `execute` bodies live here.
 */
const registryPath = process.env.LAMP_TOOLS_JSON ?? path.join(path.dirname(fileURLToPath(import.meta.url)), "lamp-tools.json");
const registry = JSON.parse(readFileSync(registryPath, "utf8")) as {
	name: string; label: string; description: string; inputSchema: Record<string, unknown>;
}[];
function spec(name: string) {
	const tool = registry.find((t) => t.name === name);
	if (!tool) throw new Error(`lamp-tools.json has no tool named ${name}`);
	// biome-ignore lint/suspicious/noExplicitAny: the schema is JSON, typed where each tool uses its params
	return { name: tool.name, label: tool.label, description: tool.description, parameters: Type.Unsafe<any>(tool.inputSchema) };
}

const lookAtApp = defineTool({
	...spec("look_at_app"),
	async execute(_toolCallId, _params, signal, _onUpdate, ctx) {
		const url = process.env.LAMP_LOOK_URL;
		if (!url) throw new Error("Lamp isn't available to look at the app.");
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.LAMP_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: "{}",
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(600_000)]) : AbortSignal.timeout(600_000),
		});
		return pictureReply(response, ctx.model, "Lamp couldn't look at the app.");
	},
});

/** Lamp's answer to look_at_app or use_app: its text, then the pictures it names (if the model can see them). */
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
	...spec("use_app"),
	async execute(_toolCallId, params, signal, _onUpdate, ctx) {
		const url = process.env.LAMP_USE_URL;
		if (!url) throw new Error("Lamp isn't available to use the app.");
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.LAMP_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: JSON.stringify({ actions: params.actions }),
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(120_000)]) : AbortSignal.timeout(120_000),
		});
		return pictureReply(response, ctx.model, "Lamp couldn't use the app.");
	},
});

const plan = defineTool({
	...spec("plan"),
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

/** Asks Lamp to approve a shell command: a reason when it isn't approved, else the command to run (Lamp hands
 * it back confined to the app's folder, see Sandbox). */
async function askLamp(command: string, signal?: AbortSignal): Promise<{ reason?: string; command?: string }> {
	const url = process.env.LAMP_APPROVE_URL;
	if (!url) return { reason: "Shell commands need approval in Lamp, and Lamp isn't available." };
	try {
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.LAMP_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: JSON.stringify({ command }),
			// The user may take a while to answer; Lamp itself never times out on their behalf.
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(3_600_000)]) : AbortSignal.timeout(3_600_000),
		});
		const reply = (await response.json()) as { allow?: boolean; reason?: string; command?: string };
		return reply.allow ? { command: reply.command } : { reason: reply.reason ?? "The user didn't approve this command." };
	} catch {
		return { reason: "Couldn't ask the user to approve this command." };
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
 * Asks Lamp whether a file tool may touch a path; resolves to an error message when it may not. Paths inside the
 * app's folder need no asking, except what the running app saves there (its log and pictures), which the user
 * can keep from the agent in Lamp's settings, and the app's history (.git), which only Lamp writes.
 */
async function checkFile(tool: string, given: string, signal?: AbortSignal): Promise<string | undefined> {
	const [target, home] = await Promise.all([resolved(given), resolved(".")]);
	const inside = target === home || target.startsWith(home + path.sep);
	// The app's history is Lamp's to write (see Sandbox), so Lamp is asked about it too; the comparison
	// ignores case, as the Mac's usual file system does.
	const within = path.relative(home, target).toLowerCase();
	const history = inside && (within === ".git" || within.startsWith(".git" + path.sep));
	if (inside && !history && !target.startsWith(path.join(home, ".lamp", "runtime") + path.sep)) return undefined;
	const url = process.env.LAMP_APPROVE_URL;
	if (!url) return inside && !history ? undefined : "Files outside the app's folder need approval in Lamp, and Lamp isn't available.";
	try {
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.LAMP_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: JSON.stringify({ file_tool: tool, path: given }),
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(3_600_000)]) : AbortSignal.timeout(3_600_000),
		});
		const reply = (await response.json()) as { allow?: boolean; reason?: string };
		return reply.allow ? undefined : (reply.reason ?? "The user didn't allow that.");
	} catch {
		return "Couldn't ask the user about that file.";
	}
}

/** Files and folders Lamp generates or depends on: never the agent's to delete. */
const protectedPaths = [".lamp", ".git", ".build", "build", ".gitignore", "Package.swift", "build.sh", "Sources/LampSupport.swift"];

const deleteFile = defineTool({
	...spec("delete_file"),
	async execute(_toolCallId, params) {
		const root = await realpath(process.cwd());
		const target = path.resolve(root, params.path);
		const relative = path.relative(root, target);
		if (relative === "" || relative.startsWith("..") || path.isAbsolute(relative)) {
			throw new Error("Only files inside the app's folder can be deleted.");
		}
		// Compared without regard to case: the Mac's usual file system treats "package.swift" as the same file.
		const lowered = relative.toLowerCase();
		if (protectedPaths.some((item) => lowered === item.toLowerCase() || lowered.startsWith(item.toLowerCase() + path.sep))) {
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

/** Calls one of Lamp's version endpoints and returns its reply as the tool's text. */
async function versions(endpoint: string, body: object, signal?: AbortSignal) {
	const url = process.env.LAMP_VERSIONS_URL;
	if (!url) throw new Error("Lamp isn't available to manage versions.");
	const response = await fetch(url + endpoint, {
		method: "POST",
		headers: { Authorization: `Bearer ${process.env.LAMP_TOKEN ?? ""}`, "Content-Type": "application/json" },
		body: JSON.stringify(body),
		signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(60_000)]) : AbortSignal.timeout(60_000),
	});
	const reply = (await response.json()) as { text?: string; error?: string };
	if (!response.ok) throw new Error(reply.error ?? "Lamp couldn't do that.");
	return { content: [{ type: "text" as const, text: reply.text ?? "" }], details: undefined };
}

const listVersions = defineTool({
	...spec("list_versions"),
	async execute(_toolCallId, _params, signal) {
		return versions("", {}, signal);
	},
});

const nameVersion = defineTool({
	...spec("name_version"),
	async execute(_toolCallId, params, signal) {
		return versions("/name", params, signal);
	},
});

const restoreVersion = defineTool({
	...spec("restore_version"),
	async execute(_toolCallId, params, signal) {
		return versions("/restore", params, signal);
	},
});

/**
 * When Lamp runs pi to use the other apps on the Mac for one of its apps (ComputerUse.viaEngine), the
 * driver's tools come from a file Lamp wrote (LAMP_COMPUTER_TOOLS_JSON), and each call is posted to Lamp
 * (LAMP_COMPUTER_URL), which asks the person before anything that acts and answers with text and pictures.
 */
function computerTools() {
	const file = process.env.LAMP_COMPUTER_TOOLS_JSON;
	const url = process.env.LAMP_COMPUTER_URL;
	if (!file || !url) return [];
	const tools = JSON.parse(readFileSync(file, "utf8")) as { name: string; description: string; inputSchema: Record<string, unknown> }[];
	return tools.map((tool) =>
		defineTool({
			name: tool.name,
			label: tool.name.replace(/_/g, " "),
			description: tool.description,
			// biome-ignore lint/suspicious/noExplicitAny: the schema is JSON from the driver
			parameters: Type.Unsafe<any>(tool.inputSchema),
			async execute(_toolCallId, params, signal, _onUpdate, ctx) {
				const response = await fetch(url, {
					method: "POST",
					headers: { Authorization: `Bearer ${process.env.LAMP_TOKEN ?? ""}`, "Content-Type": "application/json" },
					body: JSON.stringify({ name: tool.name, arguments: params }),
					signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(600_000)]) : AbortSignal.timeout(600_000),
				});
				const reply = (await response.json()) as { text?: string; error?: string; pictures?: { mimeType: string; data: string }[] };
				if (!response.ok) throw new Error(reply.error ?? "Lamp couldn't do that.");
				const content: ({ type: "text"; text: string } | { type: "image"; data: string; mimeType: string })[] = [
					{ type: "text", text: reply.text ?? "" },
				];
				const pictures = reply.pictures ?? [];
				if (pictures.length > 0 && ctx.model && !ctx.model.input.includes("image")) {
					content.push({ type: "text", text: "This model can't view images, so the picture was left out." });
				} else {
					for (const picture of pictures) content.push({ type: "image", data: picture.data, mimeType: picture.mimeType });
				}
				return { content, details: {} };
			},
		}),
	);
}

/** One of the notes tools: Lamp keeps the notes, so each call goes to it as it is. */
function notesTool(name: string) {
	return defineTool({
		...spec(name),
		async execute(_toolCallId, params, signal) {
			const url = process.env.LAMP_MEMORY_URL;
			if (!url) throw new Error("Lamp isn't available to keep notes.");
			const response = await fetch(url, {
				method: "POST",
				headers: { Authorization: `Bearer ${process.env.LAMP_TOKEN ?? ""}`, "Content-Type": "application/json" },
				body: JSON.stringify({ tool: name, arguments: params }),
				signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(60_000)]) : AbortSignal.timeout(60_000),
			});
			const reply = (await response.json()) as { text?: string; error?: string };
			if (!response.ok) throw new Error(reply.error ?? "Lamp couldn't do that.");
			return { content: [{ type: "text" as const, text: reply.text ?? "" }], details: undefined };
		},
	});
}

const offerSetup = defineTool({
	...spec("offer_setup"),
	async execute(_toolCallId, params, signal) {
		const url = process.env.LAMP_SETUP_URL;
		if (!url) throw new Error("Lamp isn't available to offer that.");
		const response = await fetch(url, {
			method: "POST",
			headers: { Authorization: `Bearer ${process.env.LAMP_TOKEN ?? ""}`, "Content-Type": "application/json" },
			body: JSON.stringify(params),
			signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(30_000)]) : AbortSignal.timeout(30_000),
		});
		const reply = (await response.json()) as { text?: string; error?: string };
		if (!response.ok) throw new Error(reply.error ?? "Lamp couldn't do that.");
		return { content: [{ type: "text" as const, text: reply.text ?? "" }], details: undefined };
	},
});

export default function (pi: ExtensionAPI) {
	const computer = computerTools();
	if (computer.length > 0) {
		for (const tool of computer) pi.registerTool(tool);
		return;   // a task in other apps: none of the build tools
	}
	pi.on("tool_call", async (event, ctx) => {
		if (fileTools.has(event.toolName)) {
			const given = (event.input as { path?: unknown }).path;
			if (typeof given !== "string" || given === "") return undefined;   // no path: the app's own folder
			const reason = await checkFile(event.toolName, given, ctx.signal);
			return reason ? { block: true, reason } : undefined;
		}
		if (event.toolName !== "bash") return undefined;
		const input = event.input as { command?: unknown };
		const answer = await askLamp(String(input.command ?? ""), ctx.signal);
		if (answer.reason) return { block: true, reason: answer.reason };
		if (answer.command) input.command = answer.command;   // the hook may change the input before it runs
		return undefined;
	});
	pi.registerTool(webFetch);
	pi.registerTool(lookAtApp);
	pi.registerTool(useApp);
	pi.registerTool(plan);
	pi.registerTool(deleteFile);
	pi.registerTool(listVersions);
	pi.registerTool(nameVersion);
	pi.registerTool(restoreVersion);
	pi.registerTool(offerSetup);
	for (const name of ["read_notes", "save_notes"]) pi.registerTool(notesTool(name));
}
