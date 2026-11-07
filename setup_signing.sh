#!/bin/bash
# One time setup: creates a self signed code signing certificate called
# "Soundweaver Local Signing" in your login keychain.
#
# Why: macOS remembers privacy permissions (Accessibility) by the app's code signature.
# An ad hoc signature changes on every build, so the permission is lost after each update.
# Signing every build with the same certificate keeps the signature identity stable,
# and the Accessibility permission survives updates.
#
# build.sh runs this automatically the first time; you can also run it by hand.
set -euo pipefail

NAME="Soundweaver Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # the system LibreSSL, so the .p12 stays readable by `security`

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate \"$NAME\" already exists."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "Creating certificate \"$NAME\"…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/cert.conf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" >/dev/null 2>&1
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout pass:soundweaver >/dev/null 2>&1

# -T lets codesign use the key without asking every time.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P soundweaver -T /usr/bin/codesign >/dev/null

# Mark it trusted for code signing. macOS shows a password dialog for this once.
echo "macOS may now ask for your login password to trust the certificate for code signing."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" \
  || echo "Trust step skipped; signing usually still works."

echo "Done. Future builds will be signed with \"$NAME\"."
