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
NAME="Lamp App Signing"
FOLDER="$HOME/Library/Application Support/Lamp/Signing"
KEYCHAIN="$FOLDER/lamp-signing.keychain-db"
PASSFILE="$FOLDER/keychain-password"

mkdir -p "$FOLDER"
chmod 700 "$FOLDER"
if [[ ! -f "$KEYCHAIN" || ! -f "$PASSFILE" ]]; then
  rm -f "$KEYCHAIN"
  (umask 077; /usr/bin/openssl rand -hex 24 > "$PASSFILE")
  security create-keychain -p "$(cat "$PASSFILE")" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"   # no auto-lock
fi
security unlock-keychain -p "$(cat "$PASSFILE")" "$KEYCHAIN"

if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/cert.cnf" <<CNF
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
  security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
  # Lets codesign use the key without a prompt (needs the keychain's password, which Lamp has).
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat "$PASSFILE")" "$KEYCHAIN" >/dev/null
  echo "Created the \"$NAME\" certificate in Lamp's keychain." >&2
fi
echo "$NAME"
