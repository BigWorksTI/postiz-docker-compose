
## Watch the Tutorial for docker-compose install:
[https://m.youtube.com/watch?v=A6CjAmJOWvA&t=5s](https://m.youtube.com/watch?v=A6CjAmJOWvA&t=5s)

## Warning
If you are upgrading from Postiz old version, please make sure you update your docker compose, you can read more here:
https://docs.postiz.com/installation/migration

### Configuration uses environment variables

The docker containers for Postiz are entirely configured with environment variables.

- **Option A** - environment variables in your `docker-compose.yml` file
- **Option B** - environment variables in a `postiz.env` file mounted in `/config` for the Postiz container only
- **Option C** - environment variables in a `.env` file next to your `docker-compose.yml` file (not recommended).

... or a mixture of the above options!

There is a [configuration reference](https://docs.postiz.com/configuration/reference) page with a list
of configuration settings.

Setup:
```
git clone https://github.com/gitroomhq/postiz-docker-compose
```

Then run:
```
docker compose up
```

Wait for it to load:

Open your website on https://localhost:4007

## BigWorks Social (white-label)

A instancia em `https://social.bigworks.com.br` roda como **BigWorks Social**:
a marca Postiz nao aparece na interface. Os patches rodam na subida do container,
encadeados no `command` do `docker-compose.override.yml` (arquivo fora do git):

```
/patch-facebook-oauth.sh && /patch-legal-pages.sh && /patch-branding.sh && node /patch-whitelabel.js && exec docker-entrypoint.sh sh -c 'nginx && pnpm run pm2'
```

- `scripts/patch-branding.sh`: icones, manifest, meta tags e logos (`patch-logo.js`, `patch-meta.js`).
- `scripts/patch-whitelabel.js`: remove o painel de marketing da tela de login e troca
  toda ocorrencia de "Postiz" nos bundles do Next.js por "BigWorks Social". Falha na
  subida se o painel de login nao for encontrado (sinal de que o bundle upstream mudou).
- `scripts/patch-legal-pages.sh`: publica `legal/terms-of-service.html` e `legal/privacy-policy.html`.

Cada script precisa estar montado no container (`./scripts/<nome>:/<nome>:ro`) e o
`NEXT_PUBLIC_POSTIZ_OAUTH_DISPLAY_NAME` deve ser `BigWorks Social`.
