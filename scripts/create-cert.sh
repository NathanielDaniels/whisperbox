#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="WhisperBox Dev"

# Check if certificate already exists
if security find-identity -v -p codesigning login.keychain-db 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists."
    exit 0
fi

echo "Creating self-signed certificate '$CERT_NAME'..."

cat > /tmp/whisperbox-cert.cfg <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
[ req_dn ]
CN = $CERT_NAME
[ extensions ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout /tmp/whisperbox-key.pem \
    -out /tmp/whisperbox-cert.pem -days 3650 -nodes \
    -config /tmp/whisperbox-cert.cfg -extensions extensions 2>/dev/null

security import /tmp/whisperbox-cert.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import /tmp/whisperbox-key.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign

# Trust the certificate for code signing (requires password prompt)
security add-trusted-cert -d -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/whisperbox-cert.pem 2>/dev/null || true

rm -f /tmp/whisperbox-cert.cfg /tmp/whisperbox-key.pem /tmp/whisperbox-cert.pem

echo "Certificate '$CERT_NAME' created successfully."
