"""For the commands marked `confined` in corpus.py (their only fault is where on disk they reach): shows that
macOS refuses them when they run under the app's sandbox profile. They delete, overwrite and read things in a
home folder, so this is for a disposable test VM and a made-up home, never a real one: it refuses to start
unless told the home is disposable.

    python3 refusals.py --disposable-home commands.json "/path/to/the/app" "/path/to/its/profile.sb"

commands.json is corpus.CORPUS + HELD_OUT as `compare.py prepare` writes them, with the app's path filled in.
The profile is one Lamp wrote for that app (its support folder's Sandbox/, after any agent command).
Each command runs twice in the app's folder: not confined, then confined. Reached: a made-up file's content
or name was printed, or it was changed, removed or had its permissions changed, or a new file appeared
beside one; when that happens confined, the line says which. A command only counts as shown refused when
the run that isn't confined does reach: one that reaches nothing either way (it doesn't work as written, or
macOS's own privacy rules stop it first) shows nothing about the sandbox, and is listed as not shown.
"""
import json, os, stat, subprocess, sys

if len(sys.argv) != 5 or sys.argv[1] != "--disposable-home": sys.exit(__doc__)
commands, app, profile = json.load(open(sys.argv[2])), sys.argv[3], sys.argv[4]
home = os.path.expanduser("~")
MARK = "MADE-UP-HOME-CONTENT"
FILES = ["Documents/old-projects/keep.txt", "Documents/note.txt", ".ssh/id_ed25519", ".aws/credentials", ".zshrc", ".zsh_history",
         "Pictures/p.txt", "Desktop/made-up-home-a.csv", "Music/m.txt", "Movies/m.txt", "Downloads/d.txt", "Library/Application Support/Notes/state.json",
         "made-up-home-cert.pem", ".gitconfig"]
# Two that a command opens as databases: real ones, with the mark as a table's name and in a row.
DATABASES = ["Library/Application Support/AddressBook/AddressBook-v22.abcddb", "Library/Safari/History.db"]
OUTSIDE = [os.path.join(home, f) for f in FILES] + [os.path.join(app, "../notes/.lamp/token")]
# What a listing or a search would print: names no file of the system's shares (it has its own cert.pem).
NAMES = ["old-projects", "made-up-home-cert.pem", "made-up-home-a.csv"]
STRAYS = ["Downloads/export-sample.csv"]   # what a command that got through leaves behind
FOLDERS = sorted({os.path.dirname(f) for f in OUTSIDE})
OURS = {f.split("/")[0] for f in FILES + DATABASES + STRAYS}   # what this check put in the home folder

def lay_out():
    for path in OUTSIDE:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        os.chmod(os.path.dirname(path), 0o700)
        with open(path, "w") as f: f.write(MARK + "\n" + ("export PATH=/made/up:$PATH\n" if path.endswith(".zshrc") else ""))
        os.chmod(path, 0o600)
        os.utime(path, (1_600_000_000, 1_600_000_000))   # old enough for a "not touched in a month" sweep
    import sqlite3
    for name in DATABASES:
        path = os.path.join(home, name)
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            if os.path.exists(path): os.remove(path)
            db = sqlite3.connect(path)
            db.execute("create table history_items (url text)"); db.execute(f"insert into history_items values ('{MARK}')")
            db.execute("create table MADE_UP_HOME_TABLE (x)"); db.commit(); db.close()
        except (OSError, sqlite3.Error): pass   # macOS keeps some folders to itself: then nothing reaches there, confined or not
    for folder in ["Sources", "build/cache", ".lamp"]: os.makedirs(os.path.join(app, folder), exist_ok=True)
    for name in ["build/export-sample.csv", "build/dev.tally.plist", "Sources/PowerMonitor.swift"]:
        path = os.path.join(app, name)
        if not os.path.exists(path): open(path, "w").write("x\n")
    for stray in STRAYS:
        if os.path.exists(os.path.join(home, stray)): os.remove(os.path.join(home, stray))
    for extra in ["keys"]:   # what a command may have left inside the app
        path = os.path.join(app, extra)
        if os.path.islink(path): os.remove(path)

def state():
    seen = {}
    for path in OUTSIDE:
        try: seen[path] = (open(path).read(), stat.S_IMODE(os.stat(path).st_mode))
        except OSError: seen[path] = None
    for folder in FOLDERS:
        try:
            names = sorted(os.listdir(folder))
            # The home folder itself is other programs' too: Lamp adds ~/Applications and ~/.swiftpm when it
            # builds, and an earlier version of this check, which compared the whole listing, took one of
            # those appearing mid-run for a command reaching out. Only the made-up names count there.
            if folder == home: names = [n for n in names if n in OURS]
            seen[folder + "/"] = (tuple(names), stat.S_IMODE(os.stat(folder).st_mode))
        except OSError: seen[folder + "/"] = None
    return seen

def reached(item, confined):
    lay_out()
    before = state()
    argv = (["/usr/bin/sandbox-exec", "-f", profile] if confined else []) + ["/bin/bash", "-c", item["command"]]
    try: out = subprocess.run(argv, cwd=app, capture_output=True, text=True, timeout=40)
    except subprocess.TimeoutExpired as e: out = subprocess.CompletedProcess(argv, 1, (e.stdout or b"").decode(errors="ignore") if isinstance(e.stdout, bytes) else (e.stdout or ""), "")
    if confined and "sandbox-exec:" in out.stderr: sys.exit(f"The sandbox didn't start for {item['id']}: {out.stderr.strip()[:200]}")
    after = state()
    what = ["its content was printed"] if MARK in out.stdout or "MADE_UP_HOME_TABLE" in out.stdout else []
    what += [f"{name} was listed" for name in NAMES if name in out.stdout]
    what += [f"{os.path.relpath(path, home)} changed" for path in after if after[path] != before[path]]
    return what

# First, that a confined shell runs at all and can still work inside the app.
lay_out()
check = subprocess.run(["/usr/bin/sandbox-exec", "-f", profile, "/bin/bash", "-c", "cd Sources && echo ok > ../build/refusals-check && cat ../build/refusals-check && rm ../build/refusals-check"], cwd=app, capture_output=True, text=True)
if check.stdout.strip() != "ok": sys.exit(f"Confined, the shell couldn't read and write inside the app, so nothing below would mean anything: {check.stderr.strip()[:200]}")

print("| Command | Not confined: reaches the made-up files | Confined: reaches them |\n| --- | --- | --- |")
through = shown = 0
not_shown = []
for item in commands:
    if not item.get("confined"): continue
    loose, held = reached(item, False), reached(item, True)
    through += bool(held)
    if loose and not held: shown += 1
    if not loose and not held: not_shown.append(item["id"])
    line = item["command"].split("\n")[0][:80].replace("|", "\\|") + (" …" if "\n" in item["command"] or len(item["command"].split("\n")[0]) > 80 else "")
    print(f"| `{line}` | {'yes' if loose else 'no'} | {('**yes: ' + '; '.join(held) + '**') if held else 'no' if loose else 'not shown: nothing to refuse'} |")
lay_out()
print(f"\nConfined, {through} command(s) reached a made-up file outside the app. Shown refused: {shown}. Not shown, because they reach nothing even when not confined: {len(not_shown)} ({', '.join(not_shown)}).")
sys.exit(1 if through else 0)
