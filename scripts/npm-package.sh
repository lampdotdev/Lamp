#!/bin/zsh
# Packs lamp for npm, for a computer without Lamp's app (on a Mac with Lamp, the copy in the app is the one to use:
# cli/README.md). The package is laid out as the repository is, so lamp finds what it reads where it always does:
# cli/ (its modules, page.js, the skill, and lamps/, whose generated files scripts/cli-files.sh writes first), the
# site's limits for a link (site/lib), and the Lamp resources lamp reads (its game kit, libraries, the Xbox's host,
# the device integrations and the skills, `RESOURCES`), with the licenses that go with them.
#   scripts/npm-package.sh 0.4.0              writes build/npm/lampdotdev-lamp-0.4.0.tgz
#   scripts/npm-package.sh 0.4.0 --publish    and publishes it (npm signed in to the lampdotdev organization, or the
#                                             release workflow, its trusted publisher)
set -euo pipefail
cd "${0:A:h}/.."
version="${1:?the version to give the package, e.g. 0.4.0}"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' ]] || { echo "\"$version\" isn't a version" >&2; exit 1; }

# The files only Lamp's code makes, from this checkout's code.
scripts/cli-files.sh >/dev/null 2>&1

stage="$(mktemp -d)/package"
trap 'rm -rf "${stage:h}"' EXIT
mkdir -p "$stage/cli" "$stage/site/lib" "$stage/Resources"
cp cli/*.mjs cli/page.js "$stage/cli/"
cp -R cli/skill cli/lamps "$stage/cli/"
# lamps/ keeps its generated files out of git; in the package they're the point, so npm is told to take everything.
rm -f "$stage/cli/lamps/.gitignore" && : > "$stage/cli/lamps/.npmignore"
# npm leaves every file called .gitignore out of a package, the Mac starter's own among them: it goes as gitignore,
# which lamp writes as .gitignore into a new app (writeMacStarter).
mv "$stage/cli/lamps/mac-starter/.gitignore" "$stage/cli/lamps/mac-starter/gitignore"
cp site/lib/shared-wishes.js site/lib/quota.js "$stage/site/lib/"
for folder in GameKit WebLibraries WebHost Devices skills; do cp -R "Resources/$folder" "$stage/Resources/$folder"; done
cp Resources/share-rules.json "$stage/Resources/"
cp Resources/THIRD_PARTY_NOTICES.md "$stage/"
cp LICENSE "$stage/LICENSE"
cp cli/README.md "$stage/README.md"
# No Mac metadata, no build products a starter might have left.
find "$stage" \( -name .DS_Store -o -name .build -o -name build \) -prune -exec rm -rf {} +

node -e '
const [version, out] = process.argv.slice(1);
const own = JSON.parse(require("fs").readFileSync("cli/package.json", "utf8"));
const pkg = {
  name: "@lampdotdev/lamp", version, description: own.description, type: "module",
  bin: { lamp: "cli/lamp.mjs" }, engines: own.engines, license: own.license,
  repository: { type: "git", url: "https://github.com/lampdotdev/Lamp.git", directory: "cli" },
  homepage: "https://lamp.dev", publishConfig: { access: "public" },
};
require("fs").writeFileSync(out, JSON.stringify(pkg, null, 2) + "\n");
' "$version" "$stage/package.json"
chmod 755 "$stage/cli/lamp.mjs"

mkdir -p build/npm
npm pack "$stage" --silent --pack-destination "$PWD/build/npm" >/dev/null
echo "Packed build/npm/lampdotdev-lamp-$version.tgz ($(du -h "build/npm/lampdotdev-lamp-$version.tgz" | cut -f1))"
if [[ "${2:-}" == --publish ]]; then
  npm publish "build/npm/lampdotdev-lamp-$version.tgz" --access public
fi
