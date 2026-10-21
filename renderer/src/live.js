import { blockAt } from './marks.js';

/**
 * Blocks an agent just wrote glow soft green and cool to normal over 1.5 s (the animation lives in the
 * stylesheet). Restarting the class replays the glow for a block written again.
 */
export function markLive(doc, lines) {
  for (const line of lines) {
    const block = blockAt(doc, line);
    if (!block) continue;
    block.classList.remove('live');
    void block.offsetWidth;
    block.classList.add('live');
    block.addEventListener('animationend', () => block.classList.remove('live'), { once: true });
  }
}

/** The prototype's caret at the end of the last written block while a file is being written. */
export function setWriting(doc, writing, lastLine) {
  doc.querySelector('.caret')?.remove();
  if (!writing) return;
  const block = (lastLine && blockAt(doc, lastLine)) || doc.lastElementChild;
  if (!block) return;
  const caret = doc.ownerDocument.createElement('span');
  caret.className = 'caret';
  caret.setAttribute('data-dotmd-ui', '');
  caret.setAttribute('aria-hidden', 'true');
  (block.querySelector('li:last-child') ?? block).appendChild(caret);
}
