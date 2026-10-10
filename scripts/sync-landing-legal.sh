#!/bin/sh
# Copia Terms/Privacy para a landing publica (social.bigworks.com.br).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cp -f "$ROOT/legal/privacy-policy.html" "$ROOT/landing/privacy-policy.html"
cp -f "$ROOT/legal/terms-of-service.html" "$ROOT/landing/terms-of-service.html"
