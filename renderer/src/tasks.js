/**
 * Task boxes tick in the app and stay read-only in Quick Look. Ticking boxes are tab stops, so Tab reaches a task
 * and Space ticks it. Each box is named by its item's own text, for VoiceOver.
 */
export function prepareTasks(doc, editable) {
  for (const box of doc.querySelectorAll('.task-list-item-checkbox')) {
    box.disabled = !editable;
    if (editable) box.setAttribute('tabindex', '0');
    else box.removeAttribute('tabindex');
    const item = box.closest('li');
    if (!item) continue;
    const own = item.cloneNode(true);
    own.querySelectorAll('ul, ol').forEach((list) => list.remove());
    const name = own.textContent.replace(/\s+/g, ' ').trim();
    if (name) box.setAttribute('aria-label', name);
  }
}

/** The source line of a Markdown task's box, or null for any other input. */
export function taskLine(box) {
  if (!box?.matches?.('.task-list-item-checkbox')) return null;
  const line = Number(box.closest('li.task-list-item[data-line]')?.dataset.line);
  return line > 0 ? line : null;
}
