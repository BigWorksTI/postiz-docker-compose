#!/usr/bin/env node
/**
 * Injeta manifest, apple-touch-icon e meta tags sociais no layout raiz do Next.js.
 */
const fs = require('fs');
const { execSync } = require('child_process');

const ROOT = '/app/apps/frontend/.next';
const SITE_URL = 'https://social.bigworks.com.br';
const ICON_MARKER = '{rel:"icon",href:"/favicon.ico",sizes:"any"}';

const EXTRA_HEAD = [
  '{rel:"manifest",href:"/site.webmanifest"}',
  '{rel:"apple-touch-icon",href:"/apple-touch-icon.png"}',
  '{name:"theme-color",content:"#0a0a0a"}',
  '{property:"og:title",content:"BigWorks Social"}',
  `{property:"og:image",content:"${SITE_URL}/og-image.png"}`,
  '{property:"og:type",content:"website"}',
  `{property:"og:url",content:"${SITE_URL}"}`,
  '{name:"twitter:card",content:"summary"}',
  `{name:"twitter:image",content:"${SITE_URL}/og-image.png"}`,
].map((props) => {
  const isMeta = props.startsWith('{name:') || props.startsWith('{property:');
  const tag = isMeta ? 'meta' : 'link';
  return `(0,ALIAS.jsx)("${tag}",${props})`;
});

function patchHeadBlock(content) {
  let s = content;
  let total = 0;
  let searchFrom = 0;

  while (true) {
    const iconIdx = s.indexOf(ICON_MARKER, searchFrom);
    if (iconIdx === -1) break;

    const headIdx = s.lastIndexOf('("head",{children:', iconIdx);
    if (headIdx === -1 || iconIdx - headIdx > 80) {
      searchFrom = iconIdx + 1;
      continue;
    }

    const aliasMatch = s.slice(headIdx - 12, headIdx).match(/\(0,([a-z])\.jsx\)$/);
    if (!aliasMatch) {
      searchFrom = iconIdx + 1;
      continue;
    }
    const alias = aliasMatch[1];

    const oldBlock = `(0,${alias}.jsx)("head",{children:(0,${alias}.jsx)("link",${ICON_MARKER})})`;
    const blockIdx = s.lastIndexOf(oldBlock, iconIdx);
    if (blockIdx === -1 || blockIdx < searchFrom) {
      searchFrom = iconIdx + 1;
      continue;
    }

    const children = [
      `(0,${alias}.jsx)("link",${ICON_MARKER})`,
      `(0,${alias}.jsx)("link",{rel:"icon",href:"/favicon.png",type:"image/png",sizes:"48x48"})`,
      ...EXTRA_HEAD.map((item) => item.replace(/ALIAS/g, alias)),
    ].join(',');

    const newBlock = `(0,${alias}.jsxs)("head",{children:[${children}]})`;
    s = s.slice(0, blockIdx) + newBlock + s.slice(blockIdx + oldBlock.length);
    total++;
    searchFrom = blockIdx + newBlock.length;
  }

  return { content: s, total };
}

function patchTitles(content) {
  let s = content;
  const replacements = [
    ['Postiz Register', 'BigWorks Social'],
    ['Postiz Calendar', 'BigWorks Social'],
    ['Postiz Integrations', 'BigWorks Social'],
    ['Postiz Analytics', 'BigWorks Social'],
    ['Postiz Media', 'BigWorks Social'],
    ['Postiz Settings', 'BigWorks Social'],
    ['Postiz - Agent', 'BigWorks Social'],
    ['title:"Postiz', 'title:"BigWorks Social'],
    ['children:"Postiz Register"', 'children:"BigWorks Social"'],
    ['children:"Postiz Calendar"', 'children:"BigWorks Social"'],
  ];
  let total = 0;
  for (const [from, to] of replacements) {
    if (s.includes(from)) {
      s = s.split(from).join(to);
      total++;
    }
  }
  return { content: s, total };
}

if (!fs.existsSync(ROOT)) {
  console.error('patch-meta: .next nao encontrado');
  process.exit(1);
}

let files = [];
try {
  const out = execSync(
    `grep -rlF '${ICON_MARKER}' '${ROOT}' --include='*.js' 2>/dev/null || true`,
    { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }
  );
  files = out.trim().split('\n').filter(Boolean);
} catch {
  files = [];
}

let headPatches = 0;
let titlePatches = 0;

for (const file of files) {
  const original = fs.readFileSync(file, 'utf8');
  const head = patchHeadBlock(original);
  const titles = patchTitles(head.content);
  if (head.total === 0 && titles.total === 0) continue;
  fs.writeFileSync(file, titles.content);
  headPatches += head.total;
  titlePatches += titles.total;
  console.log(`patch-meta: ${file} (head=${head.total}, titles=${titles.total})`);
}

// Titulos/metadata em chunks que nao passam pelo layout <head> hardcoded.
let titleFiles = 0;
try {
  const out = execSync(
    `grep -rl 'Postiz Register\\|Postiz Calendar\\|Postiz - Agent\\|children:"Postiz' '${ROOT}' --include='*.js' 2>/dev/null || true`,
    { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }
  );
  for (const file of out.trim().split('\n').filter(Boolean)) {
    const original = fs.readFileSync(file, 'utf8');
    const titles = patchTitles(original);
    if (titles.total === 0) continue;
    fs.writeFileSync(file, titles.content);
    titleFiles++;
    titlePatches += titles.total;
    console.log(`patch-meta: ${file} (titles=${titles.total})`);
  }
} catch {
  // ignore
}

console.log(`patch-meta: head=${headPatches}, titles=${titlePatches}, titleFiles=${titleFiles}`);
