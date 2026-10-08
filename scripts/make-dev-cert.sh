#!/bin/bash
# One-time: create a local code-signing certificate so macOS remembers Perch's privacy permissions across rebuilds.
# Without it, scripts/run.sh signs ad-hoc and macOS asks again after every build.
set -euo pipefail
NAME=${CERT_NAME:-Perch Dev}
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then echo "\"$NAME\" already exists."; exit 0; fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/c.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/c.cnf" -keyout "$TMP/k.pem" -out "$TMP/c.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/k.pem" -in "$TMP/c.pem" -out "$TMP/p.p12" -passout pass:perch -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null || openssl pkcs12 -export -inkey "$TMP/k.pem" -in "$TMP/c.pem" -out "$TMP/p.p12" -passout pass:perch 2>/dev/null
security import "$TMP/p.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P perch -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\". scripts/run.sh will use it."
