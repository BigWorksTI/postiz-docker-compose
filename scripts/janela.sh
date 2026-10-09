#!/bin/sh
# Liga e desliga o stack do Postiz fora da hora de postar (PO 2026-10-08).
#
# A Stage divide 6 cores com uns oito projetos e o Postiz são 8 containers
# (Temporal e Elasticsearch inclusos) parados quase o dia todo. Ele só precisa
# estar de pé para agendar o carrossel do @prompt.do.dia e até o post das
# 12:00 publicar. Quem chama:
#   - o agente, quando o PO devolve as fotos: `subir` antes do daily.sh --fotos;
#   - confirmar_publicacao.py (prompt-do-dia), depois que tudo publicou: `derrubar`.
#
# `derrubar` deixa um marcador que o orchestrator-watchdog lê para não gritar
# "container fora do ar" enquanto o stack estiver parado de propósito.
# `subir` apaga o marcador.
#
# Uso: scripts/janela.sh subir|derrubar|status

set -eu

DIR=$(cd "$(dirname "$0")/.." && pwd)
ESTADO="${WATCHDOG_ESTADO:-/var/lib/postiz-watchdog}"
DESLIGADO="$ESTADO/desligado"
URL="${POSTIZ_URL:-http://127.0.0.1:4007}"
ESPERA="${JANELA_ESPERA:-300}"

saudavel() {
    [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' postiz 2>/dev/null || echo none)" = "healthy" ]
}

case "${1:-}" in
    subir)
        rm -f "$DESLIGADO"
        # Sem a saída do compose, uma subida que falha não deixa motivo nenhum
        # no log de quem chamou (2026-10-09: dependência parada no meio do up).
        if ! saida=$(docker compose --project-directory "$DIR" -p postiz-docker-compose up -d 2>&1); then
            echo "$saida" | tail -n 5 >&2
            exit 1
        fi
        # Subida a frio conta como restart para o watchdog: sem isso, a primeira
        # checagem abaixo vê a fila sem poller e reinicia o orchestrator no meio
        # da compilação dos bundles. Em 2026-10-09 isso jogou o worker para além
        # de 10 min e o post das 12:00 saiu 12:09.
        mkdir -p "$ESTADO"
        date +%s >"$ESTADO/ultimo-restart"
        t=0
        while [ "$t" -lt "$ESPERA" ] && ! { saudavel && curl -s -o /dev/null -m 5 "$URL/api/public/v1/is-connected"; }; do
            sleep 5
            t=$((t + 5))
        done
        if [ "$t" -ge "$ESPERA" ]; then
            echo "postiz não ficou saudável em ${ESPERA}s" >&2
            exit 1
        fi
        # Container healthy não basta: em 2026-09-24 e 2026-10-08 o orchestrator
        # subiu sem worker e o post ficou em QUEUE. Só conta como no ar com o
        # poller da fila registrado; o watchdog reinicia o processo se faltar
        # (sem a trava de 15 min entre tentativas, que aqui atrasou o post).
        w=0
        while [ "$w" -lt "${JANELA_ESPERA_WORKER:-900}" ]; do
            if WATCHDOG_INTERVALO_MINIMO=0 "$DIR/scripts/orchestrator-watchdog.sh" --json | grep -q pollando; then
                echo "postiz no ar, worker pollando ($((t + w))s)"
                exit 0
            fi
            sleep 30
            w=$((w + 30))
        done
        echo "postiz no ar, mas o worker não registrou na fila em ${w}s" >&2
        exit 1
        ;;
    derrubar)
        mkdir -p "$ESTADO"
        date +%s >"$DESLIGADO"
        docker compose --project-directory "$DIR" -p postiz-docker-compose stop >/dev/null 2>&1
        echo "postiz parado"
        ;;
    status)
        if saudavel; then echo "no ar"; elif [ -f "$DESLIGADO" ]; then echo "desligado de propósito"; else echo "fora do ar"; fi
        ;;
    *)
        echo "uso: $0 subir|derrubar|status" >&2
        exit 2
        ;;
esac
