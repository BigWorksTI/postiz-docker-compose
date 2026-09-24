
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

## Watchdog do orchestrator

O container `postiz` roda tres processos no pm2: `backend`, `frontend` e
`orchestrator`. Quem executa os workflows de publicacao e o `orchestrator`,
pelos workers que ele registra nas task queues do Temporal.

No reboot da VPS o Docker sobe todos os containers em paralelo: o
`depends_on: condition: service_healthy` do compose so vale em
`docker compose up`, nao no restart automatico do daemon. Quando o `postiz`
ganha a corrida do `temporal`, o orchestrator leva connection refused em
`temporal:7233`, desiste e continua "online" no pm2 sem nenhum worker. O
backend segue criando os posts normalmente, mas ninguem executa o workflow:
o post agendado fica em `QUEUE` indefinidamente. Foi o que parou o carrossel
do @prompt.do.dia por quatro horas em 2026-09-24.

O health check HTTP do orchestrator (porta 3002) nao enxerga esse estado, porque
o processo responde mesmo sem worker. O sinal confiavel e o poller registrado
na task queue: `scripts/orchestrator-watchdog.sh` consulta a fila `main` pelo
`temporal-admin-tools` e, se o poller mais recente estiver com mais de 180s de
idade (ou nao existir nenhum), reinicia o processo.

O restart tambem mata a arvore de processos orfa: `pm2 stop` e `pm2 restart`
encerram so o wrapper `pnpm`, e o `node` filho sobrevive. Ele continua pollando
o Temporal (o pm2 mostra `stopped` e o worker segue de pe) e segura a porta
3002, o que joga o processo novo em crash loop com `EADDRINUSE`.

Instalacao no host:

```
install -m 644 systemd/postiz-orchestrator-watchdog.service \
               systemd/postiz-orchestrator-watchdog.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now postiz-orchestrator-watchdog.timer
```

O timer roda 90s depois do boot e a cada 2 minutos. Entre dois restarts ele
respeita 15 minutos, para nao entrar em loop quando a causa for outra (Temporal
fora do ar, por exemplo). Para inspecionar sem mexer em nada:

```
scripts/orchestrator-watchdog.sh --dry-run
journalctl -u postiz-orchestrator-watchdog.service --since today
```
