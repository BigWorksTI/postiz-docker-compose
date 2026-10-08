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
        docker compose --project-directory "$DIR" -p postiz-docker-compose up -d >/dev/null 2>&1
        t=0
        while [ "$t" -lt "$ESPERA" ]; do
            if saudavel && curl -s -o /dev/null -m 5 "$URL/api/public/v1/is-connected"; then
                echo "postiz no ar (${t}s)"
                exit 0
            fi
            sleep 5
            t=$((t + 5))
        done
        echo "postiz não ficou saudável em ${ESPERA}s" >&2
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
