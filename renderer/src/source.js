import { escapeHtml } from './escape.js';

/** The file as written, for Show Source: one numbered row per line. The numbers stay out of a copy. */
export function sourceHTML(markdown) {
  const lines = markdown.split('\n');
  if (lines.length > 1 && lines.at(-1) === '') lines.pop();
  const rows = lines.map((line, index) => `<span class="sl" data-line="${index + 1}">`
    + `<span class="ln" aria-hidden="true">${index + 1}</span>`
    + `<span class="st">${escapeHtml(line.replace(/\r$/, ''))}</span></span>`);
  return `<pre class="source">${rows.join('')}</pre>`;
}

/** The first source row still in view. */
export function sourceTopLine(doc, viewTop = 0) {
  for (const row of doc.querySelectorAll('.source .sl')) {
    if (row.getBoundingClientRect().bottom > viewTop) return Number(row.dataset.line);
  }
  return null;
}

/** The page block a source line belongs to: the last one starting at or before it. */
export function blockForLine(doc, line) {
  let found = null;
  for (const block of doc.querySelectorAll(':scope > [data-line]')) {
    if (Number(block.dataset.line) > line) break;
    found = block;
  }
  return found;
}
