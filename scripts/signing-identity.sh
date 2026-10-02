#!/bin/zsh
# Prints the name of a code-signing identity for local Forge builds, creating a
# self-signed one in the login keychain the first time. It never leaves this Mac and
# isn't trusted for anything else: it only gives builds a stable signature.
set -euo pipefail
NAME="Forge Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

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
  PASS="forge-$RANDOM$RANDOM"
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -passout "pass:$PASS" -out "$TMP/identity.p12" >/dev/null 2>&1
  security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
  echo "Created the \"$NAME\" certificate in your login keychain." >&2
fi
echo "$NAME"
