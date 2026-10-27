/** The top-level block a source line falls in: the last block that starts on or before it. */
export function blockForLine(doc, line) {
  let found = null;
  for (const block of doc.querySelectorAll(':scope > [data-line]')) {
    if (Number(block.dataset.line) <= line) found = block;
    else break;
  }
  return found;
}

/** The prototype's dotted "You stopped reading here" line, after the block where reading stopped. */
export function showMemory(doc, { line, label }) {
  doc.querySelector('.memory')?.remove();
  if (!line || !label) return null;
  const block = blockForLine(doc, line);
  if (!block || block === doc.lastElementChild) return null;
  const memory = doc.ownerDocument.createElement('div');
  memory.className = 'memory';
  memory.setAttribute('data-dotpen-ui', '');
  memory.setAttribute('role', 'separator');
  memory.textContent = label;
  block.after(memory);
  return memory;
}

/** The source line of the first block at or below the top of the view. */
export function topLine(doc, viewTop = 0) {
  for (const block of doc.querySelectorAll(':scope > [data-line]')) {
    if (block.getBoundingClientRect().bottom > viewTop) return Number(block.dataset.line);
  }
  return null;
}
