# Operacao na Stage

## Layout

- Codigo: `/opt/infra/postiz-docker-compose` no host do deploy (symlink `/opt/projects` → `/opt/infra`).
- Secrets: `.env` ao lado do `docker-compose.yaml` (gitignored). Host/IP e demais segredos de infra ficam no Vault ou no override local — nao neste repo.
- Override local: `docker-compose.override.yml` (branding, patches, Traefik, imagem Node). Exemplo: [override.example.yml](override.example.yml).

## Janela (`scripts/janela.sh`)

| Comando | Efeito |
|---------|--------|
| `subir` | `compose up -d`, espera health + API `is-connected`, depois poller Temporal na fila `main` |
| `derrubar` | no-op na Stage atual (stack permanece no ar; PO 2026-10-10) |
| `status` | `no ar` / `desligado de proposito` / `fora do ar` |

Variaveis uteis: `POSTIZ_URL` (default `http://127.0.0.1:4007`), `JANELA_ESPERA` (health, default 300s),
`JANELA_ESPERA_WORKER` (pollers, default 900s).

Integracao de postagem (agente prompt-do-dia): `daily.sh` ainda chama `subir` antes das fotos;
`confirmar_publicacao.py` chama `derrubar` apos publicar, mas na Stage atual isso nao para o stack.

## Watchdog do orchestrator

Ver secao no [README.md](../README.md). Na Stage o Jarbas (Zelador) agenda
`postiz-orchestrator-watchdog` via `jarbas/config/schedules/agent3.yaml`.
Units em `systemd/` sao fallback sem Telegram.

## Deploy manual

```bash
cd /opt/projects/postiz-docker-compose
docker compose -p postiz-docker-compose up -d
```

Apos mudar apenas `docker-compose.yaml` / override, `up -d` basta. Mudancas nos
patches de branding ou no `Dockerfile.postiz` exigem recriar o container `postiz`
(`docker compose -p postiz-docker-compose up -d --build postiz`).

## Validacao

```bash
./scripts/validate.sh
```

Tambem roda no workflow CI (`.github/workflows/ci.yml`) no runner self-hosted da Stage.

## Saude rapida

```bash
./scripts/janela.sh status
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4007/api/public/v1/is-connected
./scripts/orchestrator-watchdog.sh --dry-run
```

Com stack no ar, `status` = `no ar`. O estado `desligado de proposito` so aparece se
alguem criar o marcador manualmente; `derrubar` na Stage atual nao o cria.
