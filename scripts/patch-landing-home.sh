#!/bin/sh
# Home publica (Prompt do dia) na raiz; login em /auth.
set -eu

LANDING_SRC="/landing-src"
LANDING_DST="/var/www/landing"
NGINX_CONF="/etc/nginx/nginx.conf"

mkdir -p "$LANDING_DST"
cp -f "$LANDING_SRC/index.html" "$LANDING_DST/index.html"
if [ -f "$LANDING_SRC/bigworks-logo.png" ]; then
  cp -f "$LANDING_SRC/bigworks-logo.png" "$LANDING_DST/bigworks-logo.png"
fi

if grep -q "alias /var/www/landing/index.html" "$NGINX_CONF"; then
  sed -i 's|alias /var/www/landing/index.html;|root /var/www/landing;\
            try_files /index.html =404;|' "$NGINX_CONF"
fi

if ! grep -q "bw-tiktok-home" "$NGINX_CONF"; then
  sed -i '/location \/uploads\//i\
        # bw-tiktok-home\
        location = /bigworks-logo.png {\
            alias /var/www/landing/bigworks-logo.png;\
            default_type image/png;\
            add_header Cache-Control "public, max-age=86400" always;\
        }\
        location = / {\
            root /var/www/landing;\
            try_files /index.html =404;\
            default_type text/html;\
            add_header Cache-Control "no-cache, no-store, must-revalidate" always;\
        }\
' "$NGINX_CONF"
fi

echo "Postiz TikTok home patch applied."
