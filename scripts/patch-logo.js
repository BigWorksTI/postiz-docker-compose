#!/usr/bin/env node
/**
 * Substitui logos Postiz (auth + sidebar) por <img> BigWorks nos bundles Next.js.
 */
const fs = require('fs');
const { execSync } = require('child_process');

const ROOT = '/app/apps/frontend/.next';

const AUTH_SVG_OPEN =
  '("svg",{width:"101",height:"33",viewBox:"0 0 101 33",fill:"none",xmlns:"http://www.w3.org/2000/svg",children:[(0,';
const AUTH_RECT_MARKER = 'fill:"black"';

const SIDEBAR_SVG_OPEN =
  '("svg",{xmlns:"http://www.w3.org/2000/svg",width:"60",height:"60",viewBox:"0 0 60 60",fill:"none",className:"mt-[8px] min-w-[60px] min-h-[60px]"';
const SIDEBAR_MARKER = '#612BD3';

function matchCallPair(s, start) {
  let i = start;
  let depth = 0;

  for (; i < s.length; i++) {
    const ch = s[i];
    if (ch === '(') depth++;
    if (ch === ')') {
      depth--;
      if (depth === 0) {
        i++;
        break;
      }
    }
  }

  for (depth = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === '(') depth++;
    if (ch === ')') {
      depth--;
      if (depth === 0) {
        i++;
        break;
      }
    }
  }

  return i;
}

function patchAuthLogo(content) {
  let s = content;
  let total = 0;
  let searchFrom = 0;

  while (true) {
    const svgIdx = s.indexOf(AUTH_SVG_OPEN, searchFrom);
    if (svgIdx === -1) break;

    const rectIdx = s.indexOf(AUTH_RECT_MARKER, svgIdx);
    if (rectIdx === -1 || rectIdx > svgIdx + 220) {
      searchFrom = svgIdx + 1;
      continue;
    }

    const prefix = s.slice(Math.max(0, svgIdx - 16), svgIdx);
    const prefixMatch = prefix.match(/\(0,[a-z]\.jsxs\)$/);
    if (!prefixMatch) {
      searchFrom = svgIdx + 1;
      continue;
    }

    const exprStart = svgIdx - prefixMatch[0].length;
    const end = matchCallPair(s, exprStart);
    const alias = prefixMatch[0].match(/\(0,([a-z])\.jsxs\)/)[1];
    const imgBlock = `(0,${alias}.jsx)("img",{src:"/bigworks-icon.png",alt:"BigWorks",width:64,height:64,className:"block"})`;

    s = s.slice(0, exprStart) + imgBlock + s.slice(end);
    total++;
    searchFrom = exprStart + imgBlock.length;
  }

  return { content: s, total };
}

function patchSidebarLogo(content) {
  let s = content;
  let total = 0;
  let searchFrom = 0;

  while (true) {
    const svgIdx = s.indexOf(SIDEBAR_SVG_OPEN, searchFrom);
    if (svgIdx === -1) break;

    const colorIdx = s.indexOf(SIDEBAR_MARKER, svgIdx);
    if (colorIdx === -1 || colorIdx > svgIdx + 2500) {
      searchFrom = svgIdx + 1;
      continue;
    }

    const prefix = s.slice(Math.max(0, svgIdx - 16), svgIdx);
    const prefixMatch = prefix.match(/\(0,[a-z]\.jsxs\)$/);
    if (!prefixMatch) {
      searchFrom = svgIdx + 1;
      continue;
    }

    const exprStart = svgIdx - prefixMatch[0].length;
    const end = matchCallPair(s, exprStart);
    const alias = prefixMatch[0].match(/\(0,([a-z])\.jsxs\)/)[1];
    const imgBlock = `(0,${alias}.jsx)("img",{src:"/bigworks-icon.png",alt:"BigWorks",width:60,height:60,className:"mt-[8px] min-w-[60px] min-h-[60px] block"})`;

    s = s.slice(0, exprStart) + imgBlock + s.slice(end);
    total++;
    searchFrom = exprStart + imgBlock.length;
  }

  return { content: s, total };
}

function patchFile(file) {
  const original = fs.readFileSync(file, 'utf8');
  const auth = patchAuthLogo(original);
  const sidebar = patchSidebarLogo(auth.content);
  const total = auth.total + sidebar.total;
  if (total === 0) return 0;

  fs.writeFileSync(file, sidebar.content);
  console.log(`patch-logo: ${file} (auth=${auth.total}, sidebar=${sidebar.total})`);
  return total;
}

if (!fs.existsSync(ROOT)) {
  console.error('patch-logo: .next nao encontrado em', ROOT);
  process.exit(1);
}

let files = new Set();
for (const marker of [AUTH_SVG_OPEN, SIDEBAR_SVG_OPEN]) {
  try {
    const out = execSync(
      `grep -rlF '${marker}' '${ROOT}' --include='*.js' 2>/dev/null || true`,
      { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }
    );
    out.trim().split('\n').filter(Boolean).forEach((f) => files.add(f));
  } catch {
    // ignore
  }
}

let patchedBlocks = 0;
for (const file of files) {
  patchedBlocks += patchFile(file);
}

console.log(`patch-logo: ${patchedBlocks} bloco(s) em ${files.size} arquivo(s)`);
