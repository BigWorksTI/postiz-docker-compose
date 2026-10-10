# Operacao na VPS Stage

## Layout

- Codigo: `/opt/infra/postiz-docker-compose` na Contabo (symlink `/opt/projects` -> `/opt/infra`).
- Secrets: `.env` ao lado do `docker-compose.yaml` (gitignored).
- Override local: `docker-compose.override.yml` (branding, patches, portas).

## Janela (`scripts/janela.sh`)

| Comando | Efeito |
|---------|--------|
| `subir` | `compose up -d`, espera health + API `is-connected`, depois poller Temporal na fila `main` |
| `derrubar` | Marcador `desligado` + `compose stop` (watchdog nao alerta container parado) |
| `status` | `no ar` / `desligado de proposito` / `fora do ar` |

Variaveis uteis: `POSTIZ_URL` (default `http://127.0.0.1:4007`), `JANELA_ESPERA` (health, default 300s),
`JANELA_ESPERA_WORKER` (pollers, default 900s).

Integracao **prompt-do-dia**: `daily.sh` chama `subir` antes das fotos; `confirmar_publicacao.py` chama `derrubar` apos publicar.

## Watchdog do orchestrator

Ver secao no [README.md](../README.md). Nesta VPS o Jarbas (Zelador) agenda
`postiz-orchestrator-watchdog` via `jarbas/config/schedules/agent3.yaml`.
Units em `systemd/` sao fallback sem Telegram.

## Deploy manual (fora da janela)

```bash
cd /opt/projects/postiz-docker-compose
docker compose -p postiz-docker-compose up -d
```

Apos mudar apenas `docker-compose.yaml` / override, `up -d` basta. Mudancas nos
patches de branding exigem recriar o container `postiz`.

## Saude rapida

```bash
./scripts/janela.sh status
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4007/api/public/v1/is-connected
./scripts/orchestrator-watchdog.sh --dry-run
```

Com stack parado de proposito, `status` = `desligado de proposito` e containers `Exited` e esperado.
