#!/usr/bin/env bash
# Gate local antes de push (compose + YAML legivel).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[validate] docker compose config"
compose_files=(-f docker-compose.yaml)
if [[ -f docker-compose.override.yml ]]; then
  compose_files+=(-f docker-compose.override.yml)
fi
docker compose "${compose_files[@]}" config -q

if [ -f docker-compose.dev.yaml ]; then
  echo "[validate] docker-compose.dev.yaml"
  docker compose -f docker-compose.yaml -f docker-compose.dev.yaml config -q
fi

echo "[validate] scripts shellcheck (janela, watchdog)" 
command -v shellcheck >/dev/null && shellcheck scripts/janela.sh scripts/orchestrator-watchdog.sh || true

echo "[validate] ok"
