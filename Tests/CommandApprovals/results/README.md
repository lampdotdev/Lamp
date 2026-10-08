# What the PR's numbers are counted from

Every run of every command, as the comparison wrote it, and the logs behind the claims that weren't
re-run. Nothing here is read by the app or the tests.

Measured on 2026-10-08 with Jev through OpenRouter and Sonnet as the text model, five runs a command:
main at 24c3851 (ported in `before.py`; `python3 compare.py baseline` checked it against that commit's
source, 13 of 13 pieces), this branch with the judging of e51de70.

| File | What it holds | Made by |
| --- | --- | --- |
| `picked.md` | The 66 picked commands, counted | `compare.py table 5` |
| `generated.md` | The 408 generated commands, counted | `compare.py generated 5` |

The comparison also writes every run it counted beside these (`picked.json`, `generated.json`: each run on
main as `[verdict, why]`, and here as the verdict, the model's answers, the rating when one was asked for
and the outcome). They are large, so git ignores them; the ones behind this measurement, and the held-out
list's, are linked from the PR.

`logs/`, each from an earlier run and not repeated on the head:

| File | What it shows | Build it ran on |
| --- | --- | --- |
| `swift-test.txt` | The test suite's own summary lines | the head this was committed on |
| `live-turns-x4.txt` | Four live turns, each an edit then `brew install ffmpeg`: the chat lines Lamp wrote, and the edited files checked. Ends with the first run of the refusal check, whose one "yes" was the check's own mistake (see the link log) | the tree committed as fed7198 |
| `refusals-in-vm.md` | The 26 commands whose only fault is where they reach, not confined and confined, one run of three | fed7198, check script of d1385e3 |
| `link-read-through-lamps-wrapping.txt` | A read through a link out of the app, 30 times through Lamp's wrapping, five more commands 10 times each, and the earlier check replayed | 6e9baf7 |
| `links-enforced.md` | The 22 link and CDPATH cases under the profile, bash and zsh | 15b556a |
| `live-turn-links.txt` | A live turn reading and writing through links out of the app | the tree committed as 0e6adcd |
| `no-judging-model.txt` | The same three commands with decisions by text, and with Jev's call failing; how long each answer took | 3d46adb |
| `swift-build-confined-and-not.txt` | `swift build` in the test VM, confined and not | 5ad8457 |
