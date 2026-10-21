import { wordPieces } from './words.js';

/** The block a change line points at. A list item wins over its list, which starts on the same line. */
export function blockAt(doc, line) {
  return doc.querySelector(`li[data-line="${line}"]`) ?? doc.querySelector(`[data-line="${line}"]`);
}

/**
 * Marks a ChangeSet on the page: changed words struck and rewritten, a bar beside added blocks, and a "−N" tag
 * where lines were removed. A changed block whose words don't line up with the diff gets the bar instead.
 */
export function applyMarks(doc, changes) {
  removeMarks(doc);
  for (const range of changes.added ?? []) blockAt(doc, range.start)?.classList.add('added');
  for (const change of changes.changed ?? []) {
    const block = blockAt(doc, change.start);
    if (block && !markWords(block, change.words)) block.classList.add('added');
  }
  for (const removal of changes.removed ?? []) addRemovalTag(doc, removal);
}

/** Takes every mark off at once. */
export function removeMarks(doc) {
  doc.querySelectorAll('.del, .del-gap, .removed, .gut').forEach((el) => el.remove());
  doc.querySelectorAll('.ins').forEach((el) => el.replaceWith(...el.childNodes));
  doc.querySelectorAll('.added, .has-gut').forEach((el) => el.classList.remove('added', 'has-gut'));
  doc.normalize();
}

/**
 * Fades the marks out top to bottom, 40 ms apart and 220 ms each, then takes them off. With Reduce Motion they
 * all fade together in 120 ms. The timing goes through CSS variables so the added bar, a pseudo-element, gets it
 * too. Calls done when finished.
 */
export function fadeMarks(doc, { reduceMotion = false, done = () => {} } = {}) {
  const marks = [...doc.querySelectorAll('.del, .ins, .added, .gut, .removed')];
  if (!marks.length) {
    done();
    return;
  }
  marks.forEach((el, i) => {
    el.style.setProperty('--mark-delay', reduceMotion ? '0ms' : `${i * 40}ms`);
    el.style.setProperty('--mark-duration', reduceMotion ? '120ms' : '220ms');
    el.classList.add('mark-out');
  });
  const total = reduceMotion ? 120 : (marks.length - 1) * 40 + 220;
  setTimeout(() => {
    marks.forEach((el) => {
      el.classList.remove('mark-out');
      el.style.removeProperty('--mark-delay');
      el.style.removeProperty('--mark-duration');
      if (!el.getAttribute('style')) el.removeAttribute('style');
    });
    removeMarks(doc);
    done();
  }, total + 20);
}

function markWords(block, ops) {
  const words = wordPieces(block);
  const expected = ops.reduce((n, op) => n + (op.kind === 'delete' ? 0 : op.count), 0);
  if (words.length !== expected) return false;
  // Collect the edits first, then apply them from the end so earlier offsets stay valid.
  const edits = [];
  let index = 0;
  for (const op of ops) {
    if (op.kind === 'keep') index += op.count;
    else if (op.kind === 'insert') {
      for (let i = index; i < index + op.count; i++) for (const piece of words[i]) edits.push({ ...piece, type: 'ins' });
      index += op.count;
    } else if (op.kind === 'delete' && op.text) {
      const at = words[index]?.[0];
      const last = words[words.length - 1]?.at(-1);
      edits.push(at ? { node: at.node, start: at.start, end: at.start, type: 'del', text: op.text, before: true }
        : { node: last.node, start: last.end, end: last.end, type: 'del', text: op.text, before: false });
    }
  }
  edits.sort((a, b) => compare(b, a));
  for (const edit of edits) apply(block.ownerDocument, edit);
  return true;
}

// Orders edits by document position, then offset. Deletes sit before the word they precede.
function compare(a, b) {
  if (a.node !== b.node) return a.node.compareDocumentPosition(b.node) & 4 ? -1 : 1;
  if (a.start !== b.start) return a.start - b.start;
  return (a.type === 'del' ? 0 : 1) - (b.type === 'del' ? 0 : 1);
}

function apply(document, edit) {
  const range = document.createRange();
  if (edit.type === 'ins') {
    range.setStart(edit.node, edit.start);
    range.setEnd(edit.node, edit.end);
    const span = document.createElement('span');
    span.className = 'ins';
    range.surroundContents(span);
    return;
  }
  const del = document.createElement('span');
  del.className = 'del';
  del.setAttribute('data-dotmd-ui', '');
  del.textContent = edit.text;
  range.setStart(edit.node, edit.start);
  range.collapse(true);
  // The space between the struck words and the next ones belongs to the mark, so it leaves with it.
  const space = document.createElement('span');
  space.className = 'del-gap';
  space.setAttribute('data-dotmd-ui', '');
  space.textContent = ' ';
  if (edit.before) {
    range.insertNode(space);
    range.insertNode(del);
  } else {
    range.insertNode(del);
    range.insertNode(space);
  }
}

function addRemovalTag(doc, removal) {
  const block = removal.afterLine > 0 ? blockAt(doc, removal.afterLine) : doc.querySelector('[data-line]');
  if (!block) return;
  const n = removal.lineCount;
  const tag = doc.ownerDocument.createElement('button');
  tag.type = 'button';
  tag.className = removal.afterLine > 0 ? 'gut rm' : 'gut rm top';
  tag.setAttribute('data-dotmd-ui', '');
  tag.textContent = `−${n}`;
  tag.title = n === 1 ? '1 line removed. Click to show it.' : `${n} lines removed. Click to show them.`;
  tag.setAttribute('aria-label', n === 1 ? '1 line removed' : `${n} lines removed`);
  tag.setAttribute('aria-expanded', 'false');
  tag.addEventListener('click', () => toggleRemoved(block, removal, tag));
  block.classList.add('has-gut');
  block.appendChild(tag);
}

function toggleRemoved(block, removal, tag) {
  const next = block.nextElementSibling;
  if (next?.classList.contains('removed')) {
    next.remove();
    tag.setAttribute('aria-expanded', 'false');
    return;
  }
  const shown = block.ownerDocument.createElement('div');
  shown.className = 'removed';
  shown.setAttribute('data-dotmd-ui', '');
  shown.textContent = removal.text;
  block.after(shown);
  tag.setAttribute('aria-expanded', 'true');
}
