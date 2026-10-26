// Writes App/Acknowledgments.md: every open-source package dotPen ships, with its license. The npm list comes from
// the renderer's real bundle (same entry points as build.mjs), so it never lists a package the app doesn't carry.
// Run after changing dependencies: npm run acknowledgments (the Swift packages need one Xcode build first).
import { build } from 'esbuild';
import { readFile, readdir, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const out = await mkdtemp(join(tmpdir(), 'dotmd-ack-'));
const { metafile } = await build({
  entryPoints: { main: 'src/main.js', mermaid: 'src/mermaid-entry.js', styles: 'src/styles.css' },
  bundle: true,
  format: 'iife',
  target: 'safari17',
  outdir: out,
  loader: { '.woff2': 'file', '.woff': 'file', '.ttf': 'file' },
  metafile: true,
  logLevel: 'error',
});
await rm(out, { recursive: true, force: true });

const names = new Set();
for (const input of Object.keys(metafile.inputs)) {
  const match = input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/g);
  if (match) names.add(match.at(-1).replace('node_modules/', ''));
}

async function licenseText(dir) {
  const file = (await readdir(dir)).find((name) => /^(licen[cs]e|copying)/i.test(name));
  // Some license files use Windows line endings, which would draw as blank lines between every line.
  return file ? (await readFile(join(dir, file), 'utf8')).replace(/\r\n?/g, '\n').trim() : null;
}

function repositoryURL(pkg) {
  const repo = typeof pkg.repository === 'string' ? pkg.repository : pkg.repository?.url;
  if (!repo) return pkg.homepage ?? null;
  return repo.replace(/^git\+/, '').replace(/^git:\/\//, 'https://').replace(/\.git$/, '').replace(/^github:/, 'https://github.com/');
}

const entries = [];
for (const name of [...names].sort()) {
  const dir = join('node_modules', name);
  const pkg = JSON.parse(await readFile(join(dir, 'package.json'), 'utf8'));
  entries.push({ name, version: pkg.version, license: pkg.license, url: repositoryURL(pkg), text: await licenseText(dir) });
}

// Swift packages, from the checkouts of the last Xcode build. Apache-licensed ones carry their NOTICE too.
const swift = [
  { name: 'GRDB.swift', dir: 'GRDB.swift', license: 'MIT', url: 'https://github.com/groue/GRDB.swift' },
  { name: 'swift-markdown', dir: 'swift-markdown', license: 'Apache-2.0', url: 'https://github.com/swiftlang/swift-markdown' },
  { name: 'swift-cmark', dir: 'swift-cmark', license: 'BSD-2-Clause', url: 'https://github.com/swiftlang/swift-cmark' },
];
const checkouts = '../build/SourcePackages/checkouts';
if (!existsSync(checkouts)) throw new Error('Build the app in Xcode once, so the Swift package checkouts exist.');
for (const item of swift) {
  const dir = join(checkouts, item.dir);
  let text = await licenseText(dir);
  if (existsSync(join(dir, 'NOTICE.txt'))) text += '\n\n' + (await readFile(join(dir, 'NOTICE.txt'), 'utf8')).replace(/\r\n?/g, '\n').trim();
  entries.push({ ...item, text });
}

// License text as plain paragraphs, so its hard line breaks reflow to the column. Lines that Markdown would read as
// headings, rules or code fences are neutralized, so a license can't add entries to the outline.
const plain = (text) => text.split('\n').map((line) => {
  if (/^\s*[=\-_*]{3,}\s*$/.test(line)) return '';
  // Indented lines would become code blocks; the text reflows anyway.
  return line.trimStart().replace(/^(#|```|~~~)/, '\\$1');
}).join('\n');
const sections = entries.map((entry) => [
  `## ${entry.name}${entry.version ? ` ${entry.version}` : ''}`,
  `${entry.license}${entry.url ? `, ${entry.url}` : ''}`,
  // EPL-2.0 asks binary distributions to say where the source is.
  entry.license === 'EPL-2.0' ? 'The source code for this package is available at the address above.' : null,
  entry.text ? plain(entry.text) : null,
].filter(Boolean).join('\n\n'));

const page = `# Acknowledgments

dotPen stands on the work of the people who wrote and maintain these ${entries.length} open-source projects. Each one is listed with its license.

${sections.join('\n\n')}
`;
await writeFile('../App/Acknowledgments.md', page);
console.log(`wrote App/Acknowledgments.md with ${entries.length} packages`);
