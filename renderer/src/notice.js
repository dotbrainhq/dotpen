import { escapeHtml } from './document.js';

const ICONS = {
  trash: '<path d="M3 4.5h10M6.25 4.5V3h3.5v1.5M4.5 4.5l.6 8.5a1 1 0 0 0 1 .95h3.8a1 1 0 0 0 1-.95l.6-8.5"/>',
  gauge: '<path d="M2.5 11a5.5 5.5 0 1 1 11 0"/><path d="m8 11 2.5-3.5"/>',
  warn: '<path d="M8 2.5 14.25 13.5H1.75z"/><path d="M8 6.5v3.25M8 11.75v.01"/>',
};

const icon = (name) => `<svg class="i" viewBox="0 0 16 16" aria-hidden="true">${ICONS[name] ?? ''}</svg>`;

/**
 * The prototype's `.notice`, above the page: a file that went away, or a large file shown in part. One at a time;
 * null takes it off. Each button calls onAction with its id.
 */
export function showNotice(d, notice, onAction) {
  d.querySelector('.notice')?.remove();
  if (!notice) return;
  const box = d.createElement('div');
  box.className = 'notice';
  box.setAttribute('role', 'status');
  box.setAttribute('data-dotmd-ui', '');
  box.innerHTML = `${icon(notice.icon)}<span><b>${escapeHtml(notice.title)}</b>${notice.text ? ` ${escapeHtml(notice.text)}` : ''}</span>`;
  for (const { id, label, quiet } of notice.buttons ?? []) {
    const button = d.createElement('button');
    button.type = 'button';
    button.className = quiet ? 'nb q' : 'nb';
    button.textContent = label;
    button.addEventListener('click', () => onAction(id));
    box.appendChild(button);
  }
  d.body.insertBefore(box, d.querySelector('.paper'));
}

/** The prototype's `.dg-err` in place of a diagram that didn't render, with its source a click away. */
export function diagramErrorHTML(message, source) {
  return `<div class="dg-err"><div class="dg-err-h">${icon('warn')}<b>This diagram didn't render</b>`
    + '<button class="nb" type="button">Show Source</button></div>'
    + `<code>${escapeHtml(message)}</code><pre class="dg-src" hidden>${escapeHtml(source)}</pre></div>`;
}

/** Mermaid's error, cut down to the line it stopped at, so the card says where to look. */
export function diagramErrorMessage(error, source) {
  const text = String(error?.message ?? error);
  const line = Number(/on line (\d+)/.exec(text)?.[1]);
  const code = line ? source.split('\n')[line - 1]?.trim() : '';
  // Mermaid's own text without a line is parser talk; the card says it plainly and Show Source has the rest.
  return code ? `Mermaid stopped at line ${line}: ${code}` : "Mermaid couldn't make sense of this diagram.";
}
