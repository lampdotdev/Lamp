"""For the commands marked `confined` in corpus.py (their only fault is where on disk they reach): shows that
macOS refuses them when they run under the app's sandbox profile. They delete, overwrite and read things in a
home folder, so this is for a disposable test VM and a made-up home, never a real one: it refuses to start
unless told the home is disposable.

    python3 refusals.py --disposable-home commands.json "/path/to/the/app" "/path/to/its/profile.sb"

commands.json is corpus.CORPUS + HELD_OUT as `compare.py prepare` writes them, with the app's path filled in.
The profile is one Lamp wrote for that app (its support folder's Sandbox/, after any agent command).
Each command runs twice in the app's folder: not confined, to show it does reach the made-up files, then
confined. Reached: a made-up file was read out, changed, removed or had its permissions changed, or a new
file appeared beside one; when that happens confined, the line says which.
"""
import json, os, stat, subprocess, sys

if len(sys.argv) != 5 or sys.argv[1] != "--disposable-home": sys.exit(__doc__)
commands, app, profile = json.load(open(sys.argv[2])), sys.argv[3], sys.argv[4]
home = os.path.expanduser("~")
MARK = "MADE-UP-HOME-CONTENT"
FILES = ["Documents/old-projects/keep.txt", "Documents/note.txt", ".ssh/id_ed25519", ".aws/credentials", ".zshrc", ".zsh_history",
         "Pictures/p.txt", "Desktop/a.csv", "Music/m.txt", "Movies/m.txt", "Downloads/d.txt", "Library/Application Support/Notes/state.json",
         "Library/Application Support/AddressBook/AddressBook-v22.abcddb", "cert.pem"]
OUTSIDE = [os.path.join(home, f) for f in FILES] + [os.path.join(app, "../notes/.lamp/token")]
FOLDERS = sorted({os.path.dirname(f) for f in OUTSIDE})

def lay_out():
    for path in OUTSIDE:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        os.chmod(os.path.dirname(path), 0o700)
        with open(path, "w") as f: f.write(MARK + "\n")
        os.chmod(path, 0o600)
        os.utime(path, (1_600_000_000, 1_600_000_000))   # old enough for a "not touched in a month" sweep
    for folder in ["Sources", "build/cache", ".lamp"]: os.makedirs(os.path.join(app, folder), exist_ok=True)
    for name in ["build/export-sample.csv", "build/dev.tally.plist", "Sources/PowerMonitor.swift"]:
        path = os.path.join(app, name)
        if not os.path.exists(path): open(path, "w").write("x\n")
    for extra in ["keys"]:   # what a command may have left inside the app
        path = os.path.join(app, extra)
        if os.path.islink(path): os.remove(path)

def state():
    seen = {}
    for path in OUTSIDE:
        try: seen[path] = (open(path).read(), stat.S_IMODE(os.stat(path).st_mode))
        except OSError: seen[path] = None
    for folder in FOLDERS:
        try: seen[folder + "/"] = (tuple(sorted(os.listdir(folder))), stat.S_IMODE(os.stat(folder).st_mode))
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
    what = ["its content was printed"] if MARK in out.stdout else []
    what += [f"{os.path.relpath(path, home)} changed" for path in after if after[path] != before[path]]
    return what

# First, that a confined shell runs at all and can still work inside the app.
lay_out()
check = subprocess.run(["/usr/bin/sandbox-exec", "-f", profile, "/bin/bash", "-c", "cd Sources && echo ok > ../build/refusals-check && cat ../build/refusals-check && rm ../build/refusals-check"], cwd=app, capture_output=True, text=True)
if check.stdout.strip() != "ok": sys.exit(f"Confined, the shell couldn't read and write inside the app, so nothing below would mean anything: {check.stderr.strip()[:200]}")

print("| Command | Not confined: reaches the made-up files | Confined: reaches them |\n| --- | --- | --- |")
through = 0
for item in commands:
    if not item.get("confined"): continue
    loose, held = reached(item, False), reached(item, True)
    through += bool(held)
    line = item["command"].split("\n")[0][:80].replace("|", "\\|") + (" …" if "\n" in item["command"] or len(item["command"].split("\n")[0]) > 80 else "")
    print(f"| `{line}` | {'yes' if loose else 'no'} | {('**yes: ' + '; '.join(held) + '**') if held else 'no'} |")
lay_out()
print(f"\nConfined, {through} command(s) reached a made-up file outside the app.")
sys.exit(1 if through else 0)
