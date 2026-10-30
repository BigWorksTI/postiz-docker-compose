# Decisões

## 2026-10-30 - Trivy no CI e patches de imagens (issue #18)

- O job `trivy` do `ci.yml` constrói `Dockerfile.postiz` e reprova com CVE CRITICAL de pacote do SO que tenha correção (`--ignore-unfixed --pkg-types os`).
- Roda em `ubuntu-latest` (runner descartável), em PR e push. Não usa o runner self-hosted `stage-vps` nem `docker.sock`: a imagem é exportada com `docker save` e lida pelo Trivy via `--input`.
- O gate cobre só o SO porque é o que o `Dockerfile.postiz` consegue corrigir (`apt-get upgrade`). CVEs em npm/go/cargo (`next`, `handlebars`, ...) vêm da imagem oficial e só saem com nova versão upstream; entram na contagem abaixo, mas não reprovam o CI.
- Temporal (auto-setup/admin-tools 1.28.4) e Elasticsearch (7.17.28) sobem de patch na mesma linha. `postgres:17-alpine` e `postgres:16-alpine` são tags flutuantes da linha: o patch novo vem de `docker compose pull`.
- Trivy 0.58.1, `postiz-app`, CRITICAL/HIGH (build e scan locais em 2026-10-30): antes (base v2.25.0) 35/644, depois 30/548. CRITICAL de SO com correção: 5 -> 0 (libgnutls30, perl-base). Restam 27 CRITICAL com correção em npm/go/cargo, todos da base upstream.
- Pendente (precisa da Stage): scan das demais imagens, deploy e verificação (site, login, rascunho).
