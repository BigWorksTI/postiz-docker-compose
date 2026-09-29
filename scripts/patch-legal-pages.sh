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

# Com DISABLE_REGISTRATION=true, /auth so mostra "Registration is disabled".
# Quem chega pela raiz (307 -> /auth) tem que cair no formulario de login.
if ! grep -q "location = /auth" "$NGINX_CONF"; then
  sed -i '/location \/uploads\//i\
        location = /auth { return 302 /auth/login; }\
' "$NGINX_CONF"
fi

# Terms/Privacy visiveis na propria tela de login (/auth), exigencia da revisao
# de app do TikTok quando a home e login. Depende do bloco sub_filter que o
# patch-branding.sh cria em `location /` (Accept-Encoding vazio, sub_filter_types,
# sub_filter_once) - por isso aqui entra so a regra nova, sem redeclarar.
if ! grep -q "bw-legal-footer" "$NGINX_CONF"; then
  cat > /tmp/bw-legal-map.conf <<'MAP'
    map $uri $bw_legal_footer {
        default "";
        ~^/auth '<style>#bw-legal-footer{position:fixed;left:0;right:0;bottom:0;z-index:60;display:flex;justify-content:center;gap:8px;padding:4px 16px;background:rgba(10,10,10,0.94);border-top:1px solid #262626;font-family:system-ui,-apple-system,sans-serif;font-size:14px}#bw-legal-footer a{color:#e5e5e5;text-decoration:underline;display:inline-flex;align-items:center;min-height:44px;padding:0 16px}#bw-legal-footer a:hover,#bw-legal-footer a:focus-visible{color:#ffffff}</style><div id="bw-legal-footer"><a href="/terms-of-service">Terms of Service</a><a href="/privacy-policy">Privacy Policy</a></div>';
    }
MAP
  sed -i '/^http {/r /tmp/bw-legal-map.conf' "$NGINX_CONF"

  cat > /tmp/bw-legal-sub.conf <<'SUB'
            # bw-legal-footer
            sub_filter '</body>' '${bw_legal_footer}</body>';
SUB
  sed -i '/location \/ {/r /tmp/bw-legal-sub.conf' "$NGINX_CONF"
  rm -f /tmp/bw-legal-map.conf /tmp/bw-legal-sub.conf
fi

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
