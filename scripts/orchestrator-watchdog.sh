#!/bin/sh
# Vigia o processo orchestrator do Postiz e o reinicia quando ele para de
# pollar a task queue do Temporal.
#
# Motivo: no reboot da VPS o Docker sobe os containers em paralelo, e o
# depends_on/condition: service_healthy do compose so vale em "docker compose
# up" - nao no restart automatico do daemon. Quando o postiz sobe antes do
# temporal, o orchestrator leva connection refused em temporal:7233, desiste
# calado e fica "online" no pm2 sem nenhum worker. O backend continua criando
# os posts, mas ninguem executa o workflow: o post agendado fica em QUEUE para
# sempre (incidente de 2026-09-24, carrossel do @prompt.do.dia parado 4h).
#
# O health check HTTP do orchestrator (porta 3002) nao detecta isso: o processo
# responde normalmente mesmo sem worker conectado. Por isso o sinal aqui e o
# poller registrado no Temporal.
#
# Uso: scripts/orchestrator-watchdog.sh [--dry-run]
# Roda no host, chamado pelo timer postiz-orchestrator-watchdog.timer.

set -eu

CONTAINER="${POSTIZ_CONTAINER:-postiz}"
ADMIN="${TEMPORAL_ADMIN_CONTAINER:-temporal-admin-tools}"
ENDERECO="${TEMPORAL_ADDRESS:-temporal:7233}"
FILA="${TEMPORAL_TASK_QUEUE:-main}"
# Um poller renova o lease a cada minuto; o Temporal ainda lista poller morto
# por alguns minutos, entao a idade do ultimo acesso e o que vale.
IDADE_MAXIMA="${WATCHDOG_IDADE_MAXIMA:-180}"
# Espaco minimo entre dois restarts, para nao entrar em loop se a causa for
# outra (Temporal fora do ar, por exemplo).
INTERVALO_MINIMO="${WATCHDOG_INTERVALO_MINIMO:-900}"
ESTADO="${WATCHDOG_ESTADO:-/var/lib/postiz-watchdog}"
MARCADOR="$ESTADO/ultimo-restart"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log() {
    echo "$(date -Is) orchestrator-watchdog: $*"
}

rodando() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" = "true" ]
}

# Idade em segundos do poller mais recente da fila, ou vazio se nao ha poller.
idade_do_poller() {
    docker exec "$ADMIN" temporal task-queue describe \
        --address "$ENDERECO" --task-queue "$FILA" -o json 2>/dev/null |
        python3 -c '
import json, sys
from datetime import datetime, timezone

try:
    dados = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

agora = datetime.now(timezone.utc)
idades = []
for poller in dados.get("pollers") or []:
    acesso = poller.get("lastAccessTime")
    if not acesso:
        continue
    # O Temporal manda nanosegundos; datetime le no maximo microssegundos.
    acesso = acesso.replace("Z", "+00:00")
    if "." in acesso:
        cabeca, resto = acesso.split(".", 1)
        fracao, fuso = resto[:-6], resto[-6:]
        acesso = f"{cabeca}.{fracao[:6]}{fuso}"
    idades.append((agora - datetime.fromisoformat(acesso)).total_seconds())

if idades:
    print(int(min(idades)))
'
}

# O pm2 mata so o wrapper pnpm; o node filho sobrevive e segura a porta 3002,
# o que joga o processo novo em crash loop com EADDRINUSE.
matar_orfaos() {
    pids=$(docker top "$CONTAINER" -eo pid,cmd 2>/dev/null |
        awk '/orchestrator\/src\/main.js/ {print $1}' || true)
    [ -n "$pids" ] || return 0
    log "encerrando processo(s) orfao(s) do orchestrator: $(echo "$pids" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    sleep 3
    pids=$(docker top "$CONTAINER" -eo pid,cmd 2>/dev/null |
        awk '/orchestrator\/src\/main.js/ {print $1}' || true)
    if [ -n "$pids" ]; then
        # shellcheck disable=SC2086
        kill -9 $pids 2>/dev/null || true
    fi
}

reiniciar() {
    docker exec "$CONTAINER" pm2 stop orchestrator >/dev/null 2>&1 || true
    matar_orfaos
    docker exec "$CONTAINER" pm2 start orchestrator >/dev/null 2>&1
    mkdir -p "$ESTADO"
    date +%s >"$MARCADOR"
    log "orchestrator reiniciado; workers levam cerca de 60s para compilar os bundles"
}

if ! rodando "$CONTAINER"; then
    log "container $CONTAINER fora do ar; nada a fazer (restart: always cuida)"
    exit 0
fi

if ! rodando "$ADMIN"; then
    log "container $ADMIN fora do ar; sem como consultar a fila $FILA"
    exit 0
fi

idade=$(idade_do_poller || true)

if [ -n "$idade" ] && [ "$idade" -le "$IDADE_MAXIMA" ]; then
    exit 0
fi

if [ -z "$idade" ]; then
    log "fila $FILA sem nenhum poller"
else
    log "poller mais recente da fila $FILA tem ${idade}s (limite ${IDADE_MAXIMA}s)"
fi

if [ -f "$MARCADOR" ]; then
    desde=$(($(date +%s) - $(cat "$MARCADOR")))
    if [ "$desde" -lt "$INTERVALO_MINIMO" ]; then
        log "ultimo restart foi ha ${desde}s; aguardando ${INTERVALO_MINIMO}s entre tentativas"
        exit 0
    fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
    log "--dry-run: reiniciaria o orchestrator agora"
    exit 0
fi

reiniciar
