import { removeMarks } from './marks.js';

// Inline styles for Google Docs: it keeps the look of pasted HTML only when the style rides on each element.
const DOCS = {
  table: 'border-collapse: collapse; margin: 8px 0;',
  cell: 'border: 1px solid #c2c9c9; padding: 4px 8px; text-align: left; vertical-align: top;',
  pre: 'font-family: Menlo, Consolas, monospace; font-size: 10pt; background: #f1f5f5; padding: 8px 10px; white-space: pre-wrap;',
  code: 'font-family: Menlo, Consolas, monospace;',
  meta: 'color: #596363;',
};

/**
 * The page as HTML ready to paste: 'slack' for Slack's composer, which has no headings or tables, or 'docs' for
 * Google Docs, which keeps both. Math pastes as its TeX source. Diagrams paste as their Mermaid source in Slack, and
 * in Docs as the image in diagramImages (keyed by figure), else as source too.
 */
export function copyHTML(doc, target, { diagramImages = new Map() } = {}) {
  const d = doc.ownerDocument;
  const clone = doc.cloneNode(true);
  const originals = [...doc.querySelectorAll('figure.mermaid-block')];
  [...clone.querySelectorAll('figure.mermaid-block')].forEach((figure, index) => {
    const source = originals[index]?.dataset.source ?? figure.querySelector('pre.mermaid')?.textContent ?? '';
    const image = target === 'docs' ? diagramImages.get(originals[index]) : null;
    if (image) {
      const img = d.createElement('img');
      img.src = image;
      img.alt = 'Diagram';
      figure.replaceWith(img);
    } else {
      figure.replaceWith(pre(d, source.replace(/\n$/, ''), target));
    }
  });

  removeMarks(clone);
  clone.querySelectorAll('[data-dotpen-ui], button.copy, .code-lang').forEach((el) => el.remove());
  clone.querySelectorAll('.anch').forEach((el) => el.replaceWith(...el.childNodes));

  for (const math of clone.querySelectorAll('.katex-display, .katex')) {
    // Display math holds an inline .katex too; once the outer one is replaced, the inner one is gone.
    if (!clone.contains(math)) continue;
    const tex = math.querySelector('annotation[encoding="application/x-tex"]')?.textContent.trim() ?? math.textContent;
    const code = d.createElement('code');
    if (target === 'docs') code.setAttribute('style', DOCS.code);
    const display = math.classList.contains('katex-display');
    code.textContent = display ? `$$${tex}$$` : `$${tex}$`;
    (math.closest('eq, eqn') ?? math).replaceWith(code);
  }

  const meta = clone.querySelector('.meta');
  if (meta) {
    meta.querySelectorAll('.agent').forEach((el) => el.remove());
    const p = d.createElement('p');
    if (target === 'docs') p.setAttribute('style', DOCS.meta);
    p.textContent = [...meta.children].map((part) => part.textContent.trim()).filter(Boolean).join(' · ');
    meta.replaceWith(p);
  }

  for (const box of clone.querySelectorAll('input.task-list-item-checkbox')) {
    const mark = box.hasAttribute('checked') || box.checked ? '☑' : '☐';
    const spaced = /^\s/.test(box.nextSibling?.textContent ?? '');
    box.replaceWith(d.createTextNode(spaced ? mark : `${mark} `));
  }

  for (const figure of clone.querySelectorAll('figure.code-block')) {
    figure.replaceWith(pre(d, figure.querySelector('code')?.textContent.replace(/\n$/, '') ?? '', target));
  }

  if (target === 'slack') toSlack(clone, d);
  else toDocs(clone);

  // Line attributes are dotPen's own; nothing on the other side needs them.
  clone.querySelectorAll('[data-line], [data-line-end]').forEach((el) => {
    el.removeAttribute('data-line');
    el.removeAttribute('data-line-end');
  });
  return `<html><head><meta charset="utf-8"></head><body>${clone.innerHTML}</body></html>`;
}

function pre(d, text, target) {
  const block = d.createElement('pre');
  if (target === 'docs') {
    block.setAttribute('style', DOCS.pre);
    const code = d.createElement('code');
    code.textContent = text;
    block.appendChild(code);
  } else {
    block.textContent = text;
  }
  return block;
}

// Slack's composer has no headings, tables or images: headings become bold lines, tables aligned text, images links.
function toSlack(root, d) {
  for (const heading of root.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
    const p = d.createElement('p');
    const b = d.createElement('b');
    b.textContent = heading.textContent.trim();
    p.appendChild(b);
    heading.replaceWith(p);
  }
  for (const table of root.querySelectorAll('table')) {
    const rows = [...table.querySelectorAll('tr')].map((tr) => [...tr.children].map((cell) => cell.textContent.trim()));
    const widths = rows.reduce((w, row) => row.map((cell, i) => Math.max(w[i] ?? 0, cell.length)), []);
    const lines = rows.map((row) => row.map((cell, i) => (i < row.length - 1 ? cell.padEnd(widths[i]) : cell)).join(' | '));
    const block = d.createElement('pre');
    block.textContent = lines.join('\n');
    table.replaceWith(block);
  }
  for (const img of root.querySelectorAll('img')) {
    const label = img.getAttribute('alt') || 'Image';
    const src = img.getAttribute('src') ?? '';
    if (src.startsWith('https:')) {
      const a = d.createElement('a');
      a.href = src;
      a.textContent = label;
      img.replaceWith(a);
    } else {
      img.replaceWith(d.createTextNode(label));
    }
  }
}

// Google Docs keeps headings, lists and tables; it needs the borders and fonts inline, and can't fetch local images.
function toDocs(root) {
  for (const table of root.querySelectorAll('table')) table.setAttribute('style', DOCS.table);
  for (const cell of root.querySelectorAll('th, td')) cell.setAttribute('style', DOCS.cell);
  for (const code of root.querySelectorAll('code')) {
    if (!code.closest('pre')) code.setAttribute('style', DOCS.code);
  }
  for (const img of root.querySelectorAll('img')) {
    const src = img.getAttribute('src') ?? '';
    if (!src.startsWith('https:') && !src.startsWith('data:')) {
      img.replaceWith(root.ownerDocument.createTextNode(img.getAttribute('alt') || 'Image'));
    }
  }
}
