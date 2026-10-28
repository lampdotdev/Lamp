#!/usr/bin/python3
# Writes where a starter lives and the commit Lamp's copy is at into its starter.md's front matter, in place of any
# there: starter-commit.py <starter.md> <repository url> <commit>. Used by pull-starters.sh and publish-starters.sh.
import sys

path, url, sha = sys.argv[1:]
lines = [l for l in open(path).read().split("\n") if not l.startswith(("repository:", "commit:"))]
end = lines.index("---", 1)
at = next((i for i in range(1, end) if lines[i].startswith("tweaks:")), end)
lines[at:at] = [f"repository: {url}", f"commit: {sha}"]
open(path, "w").write("\n".join(lines))
