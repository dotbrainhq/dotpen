const BUBBLE = '<svg class="i" viewBox="0 0 16 16" aria-hidden="true"><path d="M2.75 4.25a1.5 1.5 0 0 1 1.5-1.5h7.5a1.5 1.5 0 0 1 1.5 1.5v5a1.5 1.5 0 0 1-1.5 1.5H7l-3 2.5v-2.5h.25a1.5 1.5 0 0 1-1.5-1.5z"/></svg>';

/**
 * The passage a selection covers, whitespace collapsed, and the source line of the block it starts in.
 * Null for an empty selection, one outside the text, or one in dotPen's own controls.
 */
export function selectionInfo(doc, selection) {
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
  const range = selection.getRangeAt(0);
  const start = range.startContainer.nodeType === 1 ? range.startContainer : range.startContainer.parentElement;
  if (!start || !doc.contains(start) || start.closest('[data-dotpen-ui]')) return null;
  const block = start.closest('[data-line]');
  if (!block || !doc.contains(block)) return null;
  const text = selection.toString().replace(/\s+/g, ' ').trim();
  if (!text) return null;
  return { text, line: Number(block.dataset.line) };
}

/**
 * The prototype's selection bar above a selection: Comment (C), Copy, and Copy as prompt. Comment only shows
 * for a file in a watched folder, where comments are kept. The arrow points at the middle of the first line.
 */
export function showSelectionBar(doc, rect, { canComment, onComment, onCopy, onPrompt }) {
  hideSelectionBar(doc);
  const d = doc.ownerDocument;
  const win = d.defaultView;
  const bar = d.createElement('div');
  bar.className = 'selpop';
  bar.setAttribute('data-dotpen-ui', '');
  bar.setAttribute('role', 'toolbar');
  bar.setAttribute('aria-label', 'Selection');
  const button = (html, action) => {
    const b = d.createElement('button');
    b.type = 'button';
    b.innerHTML = html;
    b.addEventListener('click', action);
    bar.appendChild(b);
    return b;
  };
  if (canComment) {
    button(`${BUBBLE}Comment<kbd>C</kbd>`, onComment).classList.add('primary');
    bar.appendChild(d.createElement('i'));
  }
  button('Copy', onCopy);
  button('Copy as prompt', onPrompt);
  // Pressing a button must not clear the selection it acts on.
  bar.addEventListener('mousedown', (event) => event.preventDefault());
  d.body.appendChild(bar);
  bar.style.left = `${Math.max(8, rect.left + win.scrollX + rect.width / 2 - 45)}px`;
  bar.style.top = `${rect.top + win.scrollY - 44}px`;
  return bar;
}

export function hideSelectionBar(doc) {
  doc.ownerDocument.querySelector('.selpop')?.remove();
}
