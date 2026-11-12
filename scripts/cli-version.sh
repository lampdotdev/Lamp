#!/bin/zsh
# lamp's version on npm for a build of Lamp's version: a release's own ("0.36.1"), and for a build N commits after it
# (Lamp Nightly's "0.36.1+9") the next patch's pre-release, "0.36.2-nightly.9", which npm orders after the release
# before it and before the release that follows. Lamp's app stamps its copy of lamp with it (build.sh), and the
# nightly lamp on npm is published at it (mac-release.yml's cli-nightly job), so the same commit has the same number in both.
#   scripts/cli-version.sh 0.36.1+9    prints 0.36.2-nightly.9
set -euo pipefail
version="${1:?Lamp's version, e.g. 0.36.1 or 0.36.1+9}"
if [[ "$version" =~ '^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$' ]]; then
  echo "${match[1]}.${match[2]}.$(( match[3] + 1 ))-nightly.${match[4]}"
elif [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "$version"
else
  echo "0.0.0-local"   # a build with no release tag to count from
fi
