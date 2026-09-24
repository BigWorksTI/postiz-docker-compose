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
# Uso: scripts/orchestrator-watchdog.sh [--dry-run|--json]
#
# Roda no host. Com --json escreve uma linha JSON {severity,message} no lugar
# do log, no formato que o scheduler do Jarbas manda para o Telegram; e assim
# que o agendamento em jarbas/config/schedules/agent3.yaml chama o watchdog.

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
MODO_JSON=0
case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    --json) MODO_JSON=1 ;;
esac

log() {
    [ "$MODO_JSON" -eq 1 ] && return 0
    echo "$(date -Is) orchestrator-watchdog: $*"
}

# Em modo JSON o stdout carrega uma linha so, que o scheduler do Jarbas le.
# Fora dele a funcao nao imprime nada: quem informa e o log.
fim() {
    severidade="$1"
    texto="$2"
    if [ "$MODO_JSON" -eq 1 ]; then
        JARBAS_SEV="$severidade" JARBAS_MSG="$texto" python3 -c '
import json, os

print(json.dumps({
    "severity": os.environ["JARBAS_SEV"],
    "message": os.environ["JARBAS_MSG"],
    "dedupe_key": "postiz-orchestrator",
}, ensure_ascii=False))
'
    fi
    exit 0
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
    fim critical "Postiz: container $CONTAINER fora do ar. Nenhum post agendado vai publicar."
fi

if ! rodando "$ADMIN"; then
    log "container $ADMIN fora do ar; sem como consultar a fila $FILA"
    fim warning "Postiz: container $ADMIN fora do ar, sem como conferir a fila $FILA do orchestrator."
fi

idade=$(idade_do_poller || true)

if [ -n "$idade" ] && [ "$idade" -le "$IDADE_MAXIMA" ]; then
    fim ok "Postiz: orchestrator pollando a fila $FILA (ultimo acesso ha ${idade}s)."
fi

if [ -z "$idade" ]; then
    log "fila $FILA sem nenhum poller"
    diagnostico="a fila $FILA esta sem nenhum poller"
else
    log "poller mais recente da fila $FILA tem ${idade}s (limite ${IDADE_MAXIMA}s)"
    diagnostico="o poller mais recente da fila $FILA tem ${idade}s (limite ${IDADE_MAXIMA}s)"
fi

if [ -f "$MARCADOR" ]; then
    desde=$(($(date +%s) - $(cat "$MARCADOR")))
    if [ "$desde" -lt "$INTERVALO_MINIMO" ]; then
        log "ultimo restart foi ha ${desde}s; aguardando ${INTERVALO_MINIMO}s entre tentativas"
        fim critical "Postiz: $diagnostico e o restart de ha ${desde}s nao resolveu. Post agendado nao publica ate alguem olhar."
    fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
    log "--dry-run: reiniciaria o orchestrator agora"
    exit 0
fi

reiniciar
fim warning "Postiz: $diagnostico, entao reiniciei o orchestrator. Os workers levam cerca de 60s para voltar."
