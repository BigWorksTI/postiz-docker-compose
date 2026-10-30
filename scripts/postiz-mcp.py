#!/usr/bin/env python3
"""Chama o MCP do Postiz em nome de uma organizacao.

A apiKey da organizacao vem do Vault na hora do uso (id em postiz-orgs.json);
nada de chave em arquivo. Exige a janela TOTP do Vault aberta.

Uso:
  scripts/postiz-mcp.py ORG                       # lista as tools
  scripts/postiz-mcp.py ORG TOOL ['{"arg": 1}']   # chama uma tool
  scripts/postiz-mcp.py --orgs                    # lista as organizacoes
"""
import json
import sys
import urllib.request
from pathlib import Path

CONFIG = json.loads((Path(__file__).with_name("postiz-orgs.json")).read_text(encoding="utf-8"))
VAULT_URL = "https://vault.vps.bigworks.com.br/mcp"
VAULT_ENV = Path("/root/.config/vault-mcp.env")


def _sse_ou_json(raw: str) -> dict:
    if "data:" in raw[:30]:
        raw = [linha[5:] for linha in raw.splitlines() if linha.startswith("data:")][-1]
    return json.loads(raw) if raw.strip() else {}


def chave_do_vault(cred_id: int) -> str:
    token = ""
    for linha in VAULT_ENV.read_text(encoding="utf-8").splitlines():
        if linha.startswith("VAULT_MCP_TOKEN="):
            token = linha.split("=", 1)[1].strip().strip('"').strip("'")
    corpo = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
             "params": {"name": "get_credential", "arguments": {"id": cred_id}}}
    req = urllib.request.Request(
        VAULT_URL, data=json.dumps(corpo).encode(), method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json",
                 "Accept": "application/json, text/event-stream"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        resultado = _sse_ou_json(resp.read().decode())["result"]
    texto = resultado["content"][0]["text"]
    if resultado.get("isError"):
        raise SystemExit(f"Vault recusou a credencial {cred_id}: {texto[:200]}")
    return json.loads(texto)["data"]["api_key"]


class Mcp:
    def __init__(self, chave: str) -> None:
        self.chave = chave
        self.sessao = None
        self.chamar("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                   "clientInfo": {"name": "jarbas", "version": "1"}})

    def chamar(self, metodo: str, params: dict) -> dict:
        cab = {"Authorization": f"Bearer {self.chave}", "Content-Type": "application/json",
               "Accept": "application/json, text/event-stream"}
        if self.sessao:
            cab["mcp-session-id"] = self.sessao
        corpo = {"jsonrpc": "2.0", "id": 1, "method": metodo, "params": params}
        req = urllib.request.Request(CONFIG["mcp_url"], data=json.dumps(corpo).encode(),
                                     headers=cab, method="POST")
        with urllib.request.urlopen(req, timeout=120) as resp:
            self.sessao = resp.headers.get("mcp-session-id") or self.sessao
            return _sse_ou_json(resp.read().decode())


def main() -> None:
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        raise SystemExit(__doc__)
    if args[0] == "--orgs":
        for apelido, org in CONFIG["orgs"].items():
            print(f"{apelido}: {org['nome']}")
        return
    org = CONFIG["orgs"].get(args[0])
    if not org:
        raise SystemExit(f"organizacao desconhecida: {args[0]} (veja --orgs)")
    mcp = Mcp(chave_do_vault(org["vault_id"]))
    if len(args) == 1:
        for tool in mcp.chamar("tools/list", {}).get("result", {}).get("tools", []):
            print(f"{tool['name']}: {tool.get('description', '')[:100]}")
        return
    argumentos = json.loads(args[2]) if len(args) > 2 else {}
    resposta = mcp.chamar("tools/call", {"name": args[1], "arguments": argumentos})
    print(json.dumps(resposta.get("result", resposta), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
