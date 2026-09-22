import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { createCanvas } = require('C:/Users/kjkhkh/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@napi-rs/canvas');
const { getDocument } = await import('file:///C:/Users/kjkhkh/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pdfjs-dist/legacy/build/pdf.mjs');

const pdfPath = process.argv[2];
const outDir = process.argv[3];
const pages = process.argv.slice(4).map(Number);
fs.mkdirSync(outDir, { recursive: true });
const data = new Uint8Array(fs.readFileSync(pdfPath));
const pdf = await getDocument({ data, useSystemFonts: true }).promise;
for (const num of pages) {
  if (num < 1 || num > pdf.numPages) continue;
  const page = await pdf.getPage(num);
  const viewport = page.getViewport({ scale: 1.35 });
  const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
  const ctx = canvas.getContext('2d');
  await page.render({ canvasContext: ctx, viewport }).promise;
  const out = path.join(outDir, `page-${String(num).padStart(3, '0')}.png`);
  fs.writeFileSync(out, canvas.toBuffer('image/png'));
  console.log(out);
}


