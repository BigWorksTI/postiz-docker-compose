#!/usr/bin/env node
/**
 * White-label: remove a marca Postiz do frontend.
 *
 * 1. Tira o painel de marketing da tela de login ("Over 20,000+ Entrepreneurs
 *    use Postiz..." + depoimentos) e centraliza o formulario.
 * 2. Troca toda ocorrencia da palavra "Postiz" nos bundles do Next.js
 *    (JS, HTML, RSC e traducoes) por "BigWorks Social".
 *
 * Roda depois de patch-branding.sh, que ja usa "BigWorks Social" nos
 * titulos, entao nada vira "BigWorks Social - BigWorks".
 */
const fs = require('fs');
const path = require('path');

const ROOT = '/app/apps/frontend/.next';
const BRAND = 'BigWorks Social';
const EXTENSIONS = new Set(['.js', '.html', '.rsc', '.json', '.body', '.txt']);

const RIGHT_PANEL_CLASS =
  'text-[36px] flex-1 pt-[88px] hidden lg:flex flex-col items-center';
const FORM_PANEL_FROM = 'flex-1 lg:w-[600px] lg:flex-none';
const FORM_PANEL_TO = 'flex-1 lg:max-w-[600px] lg:mx-auto';

// Do indice de "(0,x.jsx)(...)" ate o fechamento do segundo grupo de
// parenteses, que e a chamada jsx inteira.
function callEnd(s, start) {
  let i = start;
  for (let group = 0; group < 2; group++) {
    let depth = 0;
    let closed = false;
    for (; i < s.length; i++) {
      const ch = s[i];
      if (ch === '(') depth++;
      if (ch === ')') {
        depth--;
        if (depth === 0) {
          i++;
          closed = true;
          break;
        }
      }
    }
    if (!closed) return -1;
  }
  return i;
}

function patchAuthLayout(content) {
  let s = content;
  let total = 0;
  let searchFrom = 0;

  while (true) {
    const idx = s.indexOf(`{className:"${RIGHT_PANEL_CLASS}"`, searchFrom);
    if (idx === -1) break;

    const head = s.slice(Math.max(0, idx - 24), idx);
    const m = head.match(/\(0,([a-z])\.jsxs?\)\("div",$/);
    if (!m) {
      searchFrom = idx + 1;
      continue;
    }

    const start = idx - m[0].length;
    const end = callEnd(s, start);
    if (end === -1) break;

    const replacement = `(0,${m[1]}.jsx)("div",{className:"hidden"})`;
    s = s.slice(0, start) + replacement + s.slice(end);
    total++;
    searchFrom = start + replacement.length;
  }

  if (s.includes(FORM_PANEL_FROM)) {
    s = s.split(FORM_PANEL_FROM).join(FORM_PANEL_TO);
  }

  return { content: s, total };
}

function patchBrandWord(content) {
  let s = content.split('MyPostizAgent').join('MyAgent');
  const re = /\bPostiz\b/g;
  const total = (s.match(re) || []).length;
  if (total) s = s.replace(re, BRAND);
  return { content: s, total };
}

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'cache' || entry.name === 'node_modules') continue;
      walk(full, out);
    } else if (EXTENSIONS.has(path.extname(entry.name))) {
      out.push(full);
    }
  }
  return out;
}

if (!fs.existsSync(ROOT)) {
  console.error('patch-whitelabel: .next nao encontrado em', ROOT);
  process.exit(1);
}

let layoutPatches = 0;
let wordPatches = 0;
let files = 0;

for (const file of walk(ROOT, [])) {
  const original = fs.readFileSync(file, 'utf8');
  if (!original.includes('Postiz') && !original.includes(RIGHT_PANEL_CLASS)) continue;

  const layout = patchAuthLayout(original);
  const word = patchBrandWord(layout.content);
  if (layout.total === 0 && word.total === 0) continue;

  fs.writeFileSync(file, word.content);
  layoutPatches += layout.total;
  wordPatches += word.total;
  files++;
  if (layout.total) console.log(`patch-whitelabel: auth layout em ${file}`);
}

console.log(
  `patch-whitelabel: layout=${layoutPatches}, "Postiz"=${wordPatches} em ${files} arquivo(s)`
);

if (layoutPatches === 0) {
  console.error('patch-whitelabel: painel de marketing do login nao encontrado (bundle mudou?)');
  process.exit(1);
}
