#!/bin/sh
# Menu de organizações (canto superior direito) ficava por baixo do cabeçalho
# do calendário (sticky z-[20]): com 4 ou mais organizações o último item
# sumia. O menu é absolute sem z-index; aqui ele ganha z-[100], acima do
# calendário e abaixo do fundo dos modais (z-[490]). A classe z-[100] já
# existe no CSS compilado. Idempotente.
set -eu

NEXT_DIR="/app/apps/frontend/.next"
OLD='group-hover:flex absolute top-[100%] end-0 w-max max-w-[400px]'
NEW='group-hover:flex absolute z-[100] top-[100%] end-0 w-max max-w-[400px]'

files=$(grep -rlF "$OLD" "$NEXT_DIR/static" "$NEXT_DIR/server" 2>/dev/null | grep -v '\.map$' || true)
if [ -z "$files" ]; then
  if grep -rqF "$NEW" "$NEXT_DIR/static" 2>/dev/null; then
    echo "[patch-org-selector] já aplicado"
  else
    echo "[patch-org-selector] AVISO: seletor não encontrado (versão do Postiz mudou?)" >&2
  fi
  exit 0
fi
for f in $files; do
  sed -i "s/group-hover:flex absolute top-\[100%\] end-0 w-max max-w-\[400px\]/group-hover:flex absolute z-[100] top-[100%] end-0 w-max max-w-[400px]/g" "$f"
  echo "[patch-org-selector] $f"
done
