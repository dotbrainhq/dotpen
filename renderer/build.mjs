import { build } from 'esbuild';
import { copyFile, readFile, writeFile, readdir, rm, mkdir } from 'node:fs/promises';
import { join } from 'node:path';

const out = '../Packages/DotMDRender/Sources/DotMDRender/Resources/renderer';
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });

await build({
  entryPoints: { main: 'src/main.js', mermaid: 'src/mermaid-entry.js', styles: 'src/styles.css' },
  bundle: true,
  minify: true,
  format: 'iife',
  target: 'safari17',
  outdir: out,
  loader: { '.woff2': 'file', '.woff': 'file', '.ttf': 'file' },
  assetNames: 'fonts/[name]',
  logLevel: 'warning',
});

// Keep only woff2 fonts: WebKit loads them, and exported HTML inlines them.
const cssPath = join(out, 'styles.css');
const css = await readFile(cssPath, 'utf8');
await writeFile(cssPath, css.replace(/,\s*url\(["']?[^)"']*\.(?:woff|ttf)["']?\)\s*format\("(?:woff|truetype)"\)/g, ''));
for (const name of await readdir(join(out, 'fonts'))) {
  if (!name.endsWith('.woff2')) await rm(join(out, 'fonts', name));
}

await copyFile('src/index.html', join(out, 'index.html'));
console.log('renderer built');
