#!/bin/sh
# BigWorks branding: assets estáticos, manifest, meta tags e logos Postiz.
set -eu

BRANDING_SRC="/branding-src"
PUBLIC="/app/apps/frontend/public"
FRONTEND_SRC="/app/apps/frontend/src"

cp -f "$BRANDING_SRC"/favicon.ico "$PUBLIC"/favicon.ico
cp -f "$BRANDING_SRC"/favicon.png "$PUBLIC"/favicon.png
cp -f "$BRANDING_SRC"/bigworks-icon.png "$PUBLIC"/bigworks-icon.png
cp -f "$BRANDING_SRC"/bigworks-icon-1024.png "$PUBLIC"/bigworks-icon-1024.png
cp -f "$BRANDING_SRC"/apple-touch-icon.png "$PUBLIC"/apple-touch-icon.png
cp -f "$BRANDING_SRC"/og-image.png "$PUBLIC"/og-image.png
cp -f "$BRANDING_SRC"/site.webmanifest "$PUBLIC"/site.webmanifest
cp -f "$BRANDING_SRC"/logo.svg "$PUBLIC"/logo.svg
cp -f "$BRANDING_SRC"/logo.svg "$PUBLIC"/postiz.svg
cp -f "$BRANDING_SRC"/bigworks-icon.png "$PUBLIC"/postiz-fav.png

cp -f "$BRANDING_SRC"/logo-text.component.tsx \
  "$FRONTEND_SRC"/components/ui/logo-text.component.tsx
cp -f "$BRANDING_SRC"/logo.tsx \
  "$FRONTEND_SRC"/components/new-layout/logo.tsx

node /patch-logo.js
node /patch-meta.js

NGINX_CONF="/etc/nginx/nginx.conf"
if ! grep -q "bigworks-branding-subfilter" "$NGINX_CONF"; then
  sed -i '/location \/ {/a\
            # bigworks-branding-subfilter\
            proxy_set_header Accept-Encoding "";\
            sub_filter_types text/html;\
            sub_filter_once off;\
            sub_filter \x27<link rel="icon" href="/favicon.ico" sizes="any"/>\x27 \x27<link rel="icon" href="/favicon.ico" sizes="any"/><link rel="manifest" href="/site.webmanifest"/><link rel="apple-touch-icon" href="/apple-touch-icon.png"/><meta name="theme-color" content="#0a0a0a"/><meta property="og:title" content="BigWorks Social"/><meta property="og:image" content="https://social.staging.bigworks.com.br/og-image.png"/><meta property="og:type" content="website"/><meta name="twitter:card" content="summary"/><meta name="twitter:image" content="https://social.staging.bigworks.com.br/og-image.png"/>\x27;\
            sub_filter "Postiz Register" "BigWorks Social";\
            sub_filter ">Postiz<" ">BigWorks Social<";\
' "$NGINX_CONF"
fi

echo "Postiz BigWorks branding patch applied."
