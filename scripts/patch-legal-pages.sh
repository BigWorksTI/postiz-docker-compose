#!/bin/sh
# Serve Terms/Privacy localmente e aponta links do register para a instancia.
set -eu

LEGAL_SRC="/legal-src"
LEGAL_DST="/var/www/legal"
NGINX_CONF="/etc/nginx/nginx.conf"

mkdir -p "$LEGAL_DST"
cp -f "$LEGAL_SRC"/*.html "$LEGAL_DST/"

if ! grep -q "absolute_redirect off" "$NGINX_CONF"; then
  sed -i '/http {/a\
    absolute_redirect off;\
' "$NGINX_CONF"
fi

if ! grep -q "location = /terms-of-service" "$NGINX_CONF"; then
  sed -i '/location \/uploads\//i\
        location = /terms { return 301 /terms-of-service; }\
        location = /privacy { return 301 /privacy-policy; }\
        location = /terms-of-service {\
            alias /var/www/legal/terms-of-service.html;\
            default_type text/html;\
            add_header Cache-Control "no-cache, no-store, must-revalidate" always;\
        }\
        location = /privacy-policy {\
            alias /var/www/legal/privacy-policy.html;\
            default_type text/html;\
            add_header Cache-Control "no-cache, no-store, must-revalidate" always;\
        }\
' "$NGINX_CONF"
fi

# Atualiza cache headers mesmo se locations ja existirem (ex.: troca max-age -> no-cache)
sed -i 's|add_header Cache-Control "public, max-age=3600" always;|add_header Cache-Control "no-cache, no-store, must-revalidate" always;|g' "$NGINX_CONF"

for pattern in \
  's|https://postiz.com/terms|/terms-of-service|g' \
  's|https://postiz.com/privacy|/privacy-policy|g'
do
  find /app/apps/frontend -type f \( -name '*.js' -o -name '*.tsx' \) \
    -exec grep -l 'postiz.com/terms\|postiz.com/privacy' {} + 2>/dev/null \
    | while read -r f; do
      sed -i "$pattern" "$f"
    done
done

echo "Postiz legal pages patch applied."
