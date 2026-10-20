import { escapeHtml } from './escape.js';

// Replaces front matter with the same number of blank lines, so line numbers below it stay true.
export function splitFrontMatter(src) {
  const match = src.match(/^---\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/);
  if (!match) return { body: src, fields: [] };
  const lineCount = match[0].split('\n').length - (match[0].endsWith('\n') ? 1 : 0);
  const fields = match[1]
    .split(/\r?\n/)
    .map((line) => line.match(/^([A-Za-z0-9_-]+):[ \t]*(.*)$/))
    .filter(Boolean)
    .map(([, key, value]) => [key, value.replace(/^["']|["']$/g, '')]);
  return { body: '\n'.repeat(lineCount) + src.slice(match[0].length), fields };
}

export function frontMatterHTML(fields) {
  if (!fields.length) return '';
  const rows = fields.map(([k, v]) => `<div><dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd></div>`).join('');
  return `<dl class="frontmatter">${rows}</dl>\n`;
}
