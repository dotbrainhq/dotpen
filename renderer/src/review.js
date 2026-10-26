/** The start line of every change in reading order. A removal at the top counts as line 1. */
export function changeLines(changes) {
  const lines = [
    ...(changes.added ?? []).map((c) => c.start),
    ...(changes.changed ?? []).map((c) => c.start),
    ...(changes.removed ?? []).map((r) => Math.max(r.afterLine, 1)),
  ];
  return [...new Set(lines)].sort((a, b) => a - b);
}

/**
 * The change at a line, as Swift names it to accept it: its kind and line (a removal's afterLine), with its place
 * among all changes. A rewritten block comes first, then an added one, then lines removed after it.
 */
export function changeAt(changes, line) {
  const all = [
    ...(changes.changed ?? []).map((c) => ({ kind: 'changed', line: c.start, at: c.start })),
    ...(changes.added ?? []).map((c) => ({ kind: 'added', line: c.start, at: c.start })),
    ...(changes.removed ?? []).map((r) => ({ kind: 'removed', line: Math.max(r.afterLine, 1), at: r.afterLine })),
  ];
  const order = { changed: 0, added: 1, removed: 2 };
  all.sort((a, b) => a.line - b.line || order[a.kind] - order[b.kind]);
  const index = all.findIndex((change) => change.line === line);
  if (index < 0) return null;
  const { kind, at } = all[index];
  return { kind, at, index: index + 1, total: all.length };
}

/**
 * The review bar at the bottom of the page, for the change Next landed on: Accept (A), Send back, and Next (N).
 * Send back turns the change into a comment for the agent, so it shows only where comments are kept, and not for
 * removed lines, which have no text left on the page to comment on.
 */
export function showChangeBar(d, change, { canSendBack, onAccept, onSendBack, onNext }) {
  hideChangeBar(d);
  const bar = d.createElement('div');
  bar.className = 'chgbar';
  bar.setAttribute('data-dotmd-ui', '');
  bar.setAttribute('role', 'toolbar');
  bar.setAttribute('aria-label', `Change ${change.index} of ${change.total}`);
  const count = d.createElement('span');
  count.className = 'n';
  count.textContent = `Change ${change.index} of ${change.total}`;
  bar.appendChild(count);
  const button = (act, label, key, quiet, action) => {
    const el = d.createElement('button');
    el.type = 'button';
    el.className = quiet ? 'nb q' : 'nb';
    el.dataset.act = act;
    el.textContent = label;
    if (key) {
      const kbd = d.createElement('kbd');
      kbd.textContent = key;
      el.append(' ', kbd);
    }
    el.addEventListener('click', action);
    bar.appendChild(el);
  };
  button('accept', 'Accept', 'A', false, onAccept);
  if (canSendBack && change.kind !== 'removed') button('back', 'Send back', null, true, onSendBack);
  button('next', 'Next', 'N', true, onNext);
  d.body.appendChild(bar);
}

export function hideChangeBar(d) {
  d.querySelector('.chgbar')?.remove();
}
