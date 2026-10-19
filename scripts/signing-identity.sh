#!/bin/zsh
# Prints the name of a code-signing identity for local Lamp builds, creating it the first time.
#
# It lives in Lamp's own keychain (~/Library/Application Support/Lamp/Signing), not the login keychain:
# the login keychain asks the person every time codesign uses a private key, and "Always Allow" doesn't
# reliably stick. Lamp's keychain has a password Lamp generated and keeps beside it, so Lamp can unlock
# it and let codesign use the key without asking anyone. The certificate is self-signed, never leaves this
# Mac and isn't trusted for anything else: it only gives builds a stable signature, so macOS keeps an app's
# permissions across rebuilds. Sign with `codesign --keychain "$KEYCHAIN" -s "<printed name>"`.
set -euo pipefail
# Lamp runs this as itself, with its keychain password: every program by its full path, never one found on
# the PATH, where a folder a command could write to might hold a look-alike.
NAME="Lamp App Signing"
FOLDER="$HOME/Library/Application Support/Lamp/Signing"
KEYCHAIN="$FOLDER/lamp-signing.keychain-db"
PASSFILE="$FOLDER/keychain-password"

/bin/mkdir -p "$FOLDER"
/bin/chmod 700 "$FOLDER"
if [[ ! -f "$KEYCHAIN" || ! -f "$PASSFILE" ]]; then
  /bin/rm -f "$KEYCHAIN"
  (umask 077; /usr/bin/openssl rand -hex 24 > "$PASSFILE")
  /usr/bin/security create-keychain -p "$(/bin/cat "$PASSFILE")" "$KEYCHAIN"
  /usr/bin/security set-keychain-settings "$KEYCHAIN"   # no auto-lock
fi
/usr/bin/security unlock-keychain -p "$(/bin/cat "$PASSFILE")" "$KEYCHAIN"

if ! /usr/bin/security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | /usr/bin/grep -q "\"$NAME\""; then
  TMP="$(/usr/bin/mktemp -d)"
  trap '/bin/rm -rf "$TMP"' EXIT
  /bin/cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
  P12PASS="$(/usr/bin/openssl rand -hex 12)"
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -passout "pass:$P12PASS" -out "$TMP/identity.p12" >/dev/null 2>&1
  /usr/bin/security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
  # Lets codesign use the key without a prompt (needs the keychain's password, which Lamp has).
  /usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(/bin/cat "$PASSFILE")" "$KEYCHAIN" >/dev/null
  echo "Created the \"$NAME\" certificate in Lamp's keychain." >&2
fi

# Before macOS 27, codesign takes --keychain but still looks for the identity only in the person's keychain
# search list (it hands the keychain to the lookup as the place to add to, which a search ignores), so for
# Lamp's keychain it answers "no identity found". Try it on a scrap file: where it can't sign, Lamp's
# keychain goes on the list, after the ones already there, which stay as they are. Where it can, the list
# is left alone. Not being able to change the list is no reason to stop.
SCRAP="$(/usr/bin/mktemp)"
/bin/cp /usr/bin/true "$SCRAP"
if ! /usr/bin/codesign --force --keychain "$KEYCHAIN" -s "$NAME" "$SCRAP" >/dev/null 2>&1; then
  LISTED=(${(f)"$(/usr/bin/security list-keychains -d user | /usr/bin/sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"})
  if (( ! ${LISTED[(Ie)$KEYCHAIN]} )); then
    /usr/bin/security list-keychains -d user -s "${LISTED[@]}" "$KEYCHAIN" \
      || echo "Couldn't add Lamp's keychain to the keychain search list." >&2
  fi
fi
/bin/rm -f "$SCRAP"
echo "$NAME"
