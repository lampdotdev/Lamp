#!/usr/bin/env python3
"""Writes a long made-up chat into an app's folder (.lamp/chat.json), to see how Lamp's chat behaves and how long it
takes to draw once a chat is long, without an agent writing one. The lines take the shape a real turn logs them in
(Store.turn): the request (every fifth with a picture), what the agent says it's about to do, tool calls, raw output,
messages between steps, build statuses, the final answer in markdown (often with a code block), the work summary,
and now and then the agent's question card, answered, or a result card. The same seed gives the same chat.

usage: seed-chat.py APP_FOLDER LINES [--seed N] [--picture FILE]
  APP_FOLDER  a Lamp Dev app's folder; quit Lamp Dev first, since it keeps the chat it read
  LINES       about how many lines to write
  --picture   a PNG copied into Attachments/ for the requests that carry one (none without it)
"""
import argparse, json, os, random, shutil, uuid

parser = argparse.ArgumentParser(description="Write a long made-up chat for Lamp.")
parser.add_argument("project")
parser.add_argument("lines", type=int)
parser.add_argument("--seed", type=int, default=7)
parser.add_argument("--picture")
options = parser.parse_args()
project, target = options.project, options.lines
rng = random.Random(options.seed)
app = "Counter"

files = ["Sources/App.swift", "Sources/ContentView.swift", "Sources/CounterStore.swift", "Sources/HistoryView.swift",
         "Sources/SettingsView.swift", "Sources/Theme.swift", "Sources/Models/Tally.swift", "Package.swift"]
requests = [
    "Make the count bigger and put a reset button under it",
    "Add a history of the last 20 counts with the time each happened",
    "Can it keep the count when I quit?",
    "Use a warmer colour for the background, something like sand",
    "Add a keyboard shortcut: space adds one, backspace takes one away",
    "Show a little graph of counts per day",
    "The reset button is too easy to hit by mistake, ask first",
    "Let me have more than one counter, each with its own name",
    "Export the history as a CSV file",
    "Make it work in dark mode properly, the text is hard to read",
    "Add a menu bar item that shows the current count",
    "Sound when it reaches a goal I can set",
]
intros = [
    "I'll look at how the count is drawn first, then make the change.",
    "Let me read the store and the main view before changing anything.",
    "I'll add this in the store first so the view only reads it.",
    "First I'll check how the history is saved now.",
]
mids = [
    "The view reads `store.count` directly, so the new button can call `store.reset()`.",
    "Build failed on a missing `import Charts`; adding it.",
    "That built. Opening the app to look at it.",
    "The layout is cramped at the window's smallest size, so I'm giving the stack a minimum width.",
]
code_blocks = [
    """```swift
struct ResetButton: View {
    @Environment(CounterStore.self) private var store
    @State private var confirming = false

    var body: some View {
        Button("Reset", role: .destructive) { confirming = true }
            .confirmationDialog("Reset the count?", isPresented: $confirming) {
                Button("Reset", role: .destructive) { store.reset() }
            }
    }
}
```""",
    """```swift
func exportCSV(_ tallies: [Tally]) -> String {
    let header = "date,count\\n"
    let rows = tallies.map { "\\($0.date.ISO8601Format()),\\($0.count)" }
    return header + rows.joined(separator: "\\n")
}
```""",
    """```swift
Chart(store.days) { day in
    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Count", day.total))
        .foregroundStyle(Theme.accent.gradient)
}
.frame(height: 160)
```""",
]
finals = [
    "Done. The count is now **72 pt** and there's a *Reset* button under it, which asks first.",
    "The history keeps the last 20 counts, newest at the top, each with its time. It's saved with the count, so it survives a quit.",
    "Space adds one and backspace takes one away. They work whenever the window is in front; the `+` and `−` buttons still work too.",
    "I added a **Goal** field in Settings. When the count reaches it you'll hear a short chime, once per goal:\n\n- set it to 0 to turn it off\n- the chime follows the system volume",
    "Each counter has its own name and colour now. Use the **+** in the toolbar to add one; right-click a counter to rename or delete it.",
]
build_output = """Building for debugging...
[1/6] Compiling Counter CounterStore.swift
[2/6] Compiling Counter ContentView.swift
/Sources/ContentView.swift:42:17: error: cannot find 'Chart' in scope
            Chart(store.days) { day in
            ^~~~~
/Sources/ContentView.swift:43:17: error: cannot find 'BarMark' in scope
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Count", day.total))
                ^~~~~~~
error: fatalError"""


def line(kind, text, **extra):
    d = {"id": str(uuid.uuid4()).upper(), "kind": kind, "text": text}
    d.update(extra)
    return d


def tool():
    f = rng.choice(files)
    return rng.choice([f"Read {f}", f"Read {f}", f"Edit {f}", f"Write {f}", f"Bash: cd \"/Users/admin/Library/Application Support/Lamp Dev/Apps/counter\" && ./build.sh",
                       "grep -n \"count\" Sources", "look_at_app", "use_app click Reset", "ls Sources"])


def hexv():
    return "%040x" % rng.getrandbits(160)


attach_dir = os.path.join(project, "Attachments")
os.makedirs(attach_dir, exist_ok=True)
picture = options.picture or ""

lines, turn = [], 0
while len(lines) < target:
    turn += 1
    before, version = hexv(), hexv()
    user = line("user", rng.choice(requests), before=before, version=version)
    if turn % 5 == 0 and os.path.exists(picture):
        name = f"Screenshot {turn}.png"
        shutil.copy(picture, os.path.join(attach_dir, name))
        user["attachments"] = [name]
    lines.append(user)
    if turn % 9 == 4:
        # The agent asks; the click is the next request, shown by the folded card.
        lines.append(line("agent", rng.choice(intros)))
        ask = {"layout": "steps", "questions": [{"question": "Where should the reset button go?", "options": [
            {"title": "Under the count", "symbol": "arrow.down"}, {"title": "In the toolbar", "symbol": "menubar.rectangle"},
            {"title": "In the menu", "symbol": "filemenu.and.selection"}]}], "answers": ["Under the count"]}
        text = "Where should the reset button go?\n- Under the count\n- In the toolbar\n- In the menu"
        lines.append(line("tool", "ask"))
        lines.append(line("ask", text, ask=ask))
        lines.append(line("summary", "Worked for %ds · $%.2f" % (rng.randint(5, 40), rng.random() * 0.1)))
        lines.append(line("user", "Where should the reset button go? Under the count", before=version, version=hexv(), fromCard=True))
    lines.append(line("agent", rng.choice(intros)))
    for _ in range(rng.randint(3, 10)):
        lines.append(line("tool", tool()))
        if rng.random() < 0.15:
            lines.append(line("detail", build_output))
        if rng.random() < 0.25:
            lines.append(line("agent", rng.choice(mids)))
    lines.append(line("status", "Building…"))
    lines.append(line("status", f"{app} is updated" if turn > 1 else f"{app} is ready"))
    final = rng.choice(finals)
    if rng.random() < 0.4:
        final += "\n\nThe new part is:\n\n" + rng.choice(code_blocks)
    lines.append(line("agent", final))
    lines.append(line("summary", "Worked for %dm %ds · $%.2f" % (rng.randint(0, 4), rng.randint(0, 59), rng.random() * 0.6)))
    if turn % 3 == 0:
        lines.append(line("result", f"{app} is updated: " + final.split(".")[0] + ".",
                          result={"summary": final.split(".")[0] + ".", "guesses": [], "status": f"{app} is updated", "version": version}))

os.makedirs(os.path.join(project, ".lamp"), exist_ok=True)
with open(os.path.join(project, ".lamp", "chat.json"), "w") as f:
    json.dump(lines, f)
kinds = {}
for l in lines:
    kinds[l["kind"]] = kinds.get(l["kind"], 0) + 1
print(json.dumps({"lines": len(lines), "turns": turn, "kinds": kinds, "bytes": os.path.getsize(os.path.join(project, ".lamp", "chat.json"))}))
