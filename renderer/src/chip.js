import { blockAt } from './marks.js';

/**
 * The prototype's change chip: "3 changes since 1:02 PM", Next with its N key, and Mark read. It sits under the
 * status line, or at the top when there is none. A count of 0 removes it.
 */
export function showChip(doc, { count, since }, { onNext, onMarkRead }) {
  doc.querySelector('.chip')?.remove();
  if (!count) return null;
  const d = doc.ownerDocument;
  const chip = d.createElement('div');
  chip.className = 'chip';
  chip.setAttribute('data-dotmd-ui', '');
  chip.setAttribute('role', 'group');
  chip.setAttribute('aria-label', 'Changes since you last read this file');
  const label = d.createElement('b');
  label.textContent = count === 1 ? '1 change' : `${count} changes`;
  const when = d.createElement('span');
  when.className = 'since';
  when.textContent = since;
  const next = d.createElement('button');
  next.type = 'button';
  next.append('Next');
  const key = d.createElement('kbd');
  key.textContent = 'N';
  next.append(key);
  next.setAttribute('aria-label', 'Next change');
  next.addEventListener('click', onNext);
  const read = d.createElement('button');
  read.type = 'button';
  read.textContent = 'Mark read';
  read.addEventListener('click', onMarkRead);
  chip.append(label, when, next, read);
  const meta = doc.firstElementChild?.classList.contains('meta') ? doc.firstElementChild : null;
  if (meta) meta.after(chip);
  else doc.prepend(chip);
  return chip;
}

/** The first change below the top of the view, or the first change when the view is past the last one. */
export function nextChangeLine(lines, viewTop, topOf) {
  const sorted = [...lines].sort((a, b) => a - b);
  return sorted.find((line) => topOf(line) > viewTop + 4) ?? sorted[0];
}

/** The change above the one at the top of the view, wrapping to the last: Shift-N. */
export function previousChangeLine(lines, viewTop, topOf) {
  const sorted = [...lines].sort((a, b) => a - b);
  return sorted.findLast((line) => topOf(line) < viewTop - 4) ?? sorted.at(-1);
}

/**
 * Scrolls a block to just under the top with an ease-out over 300 ms, then outlines it briefly.
 * With Reduce Motion it jumps and only outlines.
 */
export function revealBlock(doc, line, { reduceMotion = false } = {}) {
  const block = blockAt(doc, line);
  if (!block) return;
  const win = doc.ownerDocument.defaultView;
  const target = Math.max(0, block.getBoundingClientRect().top + win.scrollY - 24);
  if (reduceMotion) {
    win.scrollTo(0, target);
  } else {
    const start = win.scrollY;
    const began = win.performance.now();
    const step = (now) => {
      const t = Math.min(1, (now - began) / 300);
      win.scrollTo(0, start + (target - start) * (1 - (1 - t) ** 3));
      if (t < 1) win.requestAnimationFrame(step);
    };
    win.requestAnimationFrame(step);
  }
  block.classList.remove('target-flash');
  void block.offsetWidth;
  block.classList.add('target-flash');
  setTimeout(() => block.classList.remove('target-flash'), 1200);
}
