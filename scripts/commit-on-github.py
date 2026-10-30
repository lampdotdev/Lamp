#!/usr/bin/python3
"""Puts what's staged in the current git repository on top of a branch on GitHub as one commit, made by GitHub.

    commit-on-github.py <owner/repo> <branch> <message>

The commit is made through GitHub's API (`createCommitOnBranch`), so GitHub signs it and it shows as Verified,
authored by whoever gh is signed in as under the address their account commits with. A commit made here and pushed
would be signed with the local key, which GitHub verifies only when the commit's address is one of that key's own:
publishing under the account's noreply address keeps personal addresses off the repositories, and no key names it.

It goes on top of HEAD, which must be the branch's head on GitHub: if the branch moved since, GitHub turns it down.
The commit's id is printed, or HEAD's when nothing but modes changed, with no commit made. The API can't set a file's
mode (a file keeps the mode it has on the branch and a new one is plain), so staged modes are matched to that first:
a staged executable `build.sh` is no change, which is why a repository's README runs it with `zsh build.sh`. If the
tree GitHub made still differs from what's staged, it stops with an error rather than call that published.
"""
import base64
import json
import subprocess
import sys

repo, branch, message = sys.argv[1:4]


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


head = git("rev-parse", "HEAD").decode().strip()

# Each staged file takes the mode GitHub will give it: the branch's for a file that's there, plain for a new one.
fields = git("diff", "--cached", "--raw", "--no-renames", "-z", "HEAD").split(b"\0")
for meta, path in zip(fields[0::2], fields[1::2]):
    old_mode, new_mode = meta.split()[0].lstrip(b":"), meta.split()[1]
    if new_mode not in (b"100644", b"100755", b"000000"):
        sys.exit(f"{repo}: {path.decode()} isn't a plain file, which GitHub's API can't commit; nothing published")
    want = old_mode if old_mode in (b"100644", b"100755") else b"100644"
    if new_mode != b"000000" and new_mode != want:
        git("update-index", "--chmod=" + ("+x" if want == b"100755" else "-x"), "--", path.decode())

additions, deletions = [], []
entries = git("diff", "--cached", "--name-status", "--no-renames", "-z", "HEAD").split(b"\0")
for status, path in zip(entries[0::2], entries[1::2]):
    path = path.decode()
    if status == b"D":
        deletions.append({"path": path})
    else:
        contents = git("show", f":{path}")
        additions.append({"path": path, "contents": base64.b64encode(contents).decode()})
if not additions and not deletions:
    print(head)
    sys.exit(0)

query = "mutation($i: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $i) { commit { oid tree { oid } } } }"
headline, _, body = message.partition("\n")
request = {"query": query, "variables": {"i": {
    "branch": {"repositoryNameWithOwner": repo, "branchName": branch},
    "expectedHeadOid": head,
    "message": {"headline": headline, **({"body": body.strip()} if body.strip() else {})},
    "fileChanges": {"additions": additions, "deletions": deletions},
}}}
answer = subprocess.run(["gh", "api", "graphql", "--input", "-"], input=json.dumps(request).encode(), capture_output=True)
try:
    commit = json.loads(answer.stdout)["data"]["createCommitOnBranch"]["commit"]
except (ValueError, KeyError, TypeError):
    sys.stderr.write(answer.stdout.decode() + answer.stderr.decode())
    sys.exit(1)
if commit["tree"]["oid"] != git("write-tree").decode().strip():
    sys.stderr.write(f"{repo}: {commit['oid']} on {branch} differs from what was staged; look at it on GitHub\n")
    sys.exit(1)
print(commit["oid"])
