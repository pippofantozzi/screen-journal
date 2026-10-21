#!/usr/bin/env bash
# One-time: creates the self-signed "Screen Journal Signing" code-signing identity in the login keychain.
# Every release must be signed with this same identity, or macOS forgets her Screen Recording grant.
# Back up the exported .p12 somewhere safe (password manager); losing it means re-granting once.
set -euo pipefail

NAME="Screen Journal Signing"
OUT="${1:-$HOME/.screen-journal-signing}"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "'$NAME' already exists in the keychain."
  exit 0
fi

mkdir -p "$OUT" && chmod 700 "$OUT"
cd "$OUT"
cat > cert.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config cert.cnf -keyout key.pem -out cert.pem
PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "$NAME" -out signing.p12 -passout "pass:$PASS" 2>/dev/null \
  || openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" -out signing.p12 -passout "pass:$PASS"
security import signing.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
printf '%s' "$PASS" > signing.p12.password
rm key.pem cert.cnf
chmod 600 signing.p12 signing.p12.password
echo "Created '$NAME'. Backup: $OUT/signing.p12 (+ .password)"
