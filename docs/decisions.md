# Decisões

## 2026-10-30 - Trivy no CI e patches de imagens (issue #18)

- O job `trivy` do `ci.yml` constrói `Dockerfile.postiz` e reprova com CVE CRITICAL que tenha correção (`--ignore-unfixed`).
- Roda só em `push` para `main`, nunca em PR: o runner é self-hosted (`stage-vps`) e PR de terceiros executaria código no host da Stage. A imagem é exportada com `docker save` e lida pelo Trivy via `--input`, sem montar `/var/run/docker.sock`.
- `Dockerfile.postiz` roda `apt-get upgrade` para pegar os patches do Debian 12 (libgnutls30, perl-base).
- Temporal (auto-setup/admin-tools 1.28.4) e Elasticsearch (7.17.28) sobem de patch na mesma linha. `postgres:17-alpine` e `postgres:16-alpine` são tags flutuantes da linha: o patch novo vem de `docker compose pull`.
- Pendente (precisa da Stage): rebuild, Trivy antes/depois, deploy e verificação (site, login, rascunho). CVEs em dependências npm (ex.: `handlebars` 4.7.8) vêm da imagem oficial e só saem com nova versão upstream; se o gate reprovar por elas, é esperado.
