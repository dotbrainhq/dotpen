import { textNodes } from './words.js';
import { blockAt } from './marks.js';

/**
 * Wraps a comment's passage in its block with the prototype's dotted underline and puts the comment's number
 * after it. The passage is matched with whitespace collapsed, and can span formatting. False when it isn't there.
 */
export function anchorPassage(block, quote, number) {
  const nodes = textNodes(block);
  let joined = '';
  const starts = [];
  for (const node of nodes) {
    starts.push(joined.length);
    joined += node.data;
  }
  // The collapsed text, and for each of its characters the index it came from.
  let collapsed = '';
  const origin = [];
  for (let i = 0; i < joined.length; i++) {
    const space = /\s/.test(joined[i]);
    if (space && (collapsed.endsWith(' ') || collapsed === '')) continue;
    collapsed += space ? ' ' : joined[i];
    origin.push(i);
  }
  const at = collapsed.indexOf(quote);
  if (!quote || at < 0) return false;
  const from = origin[at];
  const to = origin[at + quote.length - 1] + 1;
  const d = block.ownerDocument;
  const pieces = [];
  nodes.forEach((node, i) => {
    const start = Math.max(from, starts[i]);
    const end = Math.min(to, starts[i] + node.data.length);
    if (start < end) pieces.push({ node, start: start - starts[i], end: end - starts[i] });
  });
  let last = null;
  for (const piece of pieces.reverse()) {
    const range = d.createRange();
    range.setStart(piece.node, piece.start);
    range.setEnd(piece.node, piece.end);
    const span = d.createElement('span');
    span.className = 'anch';
    range.surroundContents(span);
    last ??= span;
  }
  const badge = d.createElement('span');
  badge.className = 'num';
  badge.setAttribute('data-dotmd-ui', '');
  badge.textContent = String(number);
  last.after(badge);
  return true;
}

/** Takes every comment, passage mark and composer off the page. */
export function clearComments(doc, margin) {
  doc.querySelectorAll('.num').forEach((el) => el.remove());
  doc.querySelectorAll('.anch').forEach((el) => el.replaceWith(...el.childNodes));
  doc.normalize();
  margin.querySelectorAll('.cmt').forEach((el) => el.remove());
  margin.classList.remove('has-comments');
}

/**
 * The prototype's comments beside their passage in the margin. Each comment is
 * { id, line, quote, body, when, inPrompt, number }, and author is { initial, name }.
 */
export function renderComments(doc, margin, comments, author, { onEdit, onResolve }) {
  const composer = margin.querySelector('.cmt.compose');
  clearComments(doc, margin);
  const d = doc.ownerDocument;
  for (const comment of comments) {
    const block = blockAt(doc, comment.line);
    if (!block) continue;
    anchorPassage(block, comment.quote, comment.number);
    const card = d.createElement('div');
    card.className = 'cmt saved';
    card.setAttribute('data-dotmd-ui', '');
    card.dataset.for = String(comment.line);
    card.dataset.comment = String(comment.id);
    card.appendChild(header(d, author, comment.when));
    const body = d.createElement('p');
    body.textContent = comment.body;
    card.appendChild(body);
    const footer = d.createElement('div');
    footer.className = 'f';
    const state = d.createElement(comment.inPrompt ? 'b' : 'span');
    state.textContent = comment.inPrompt ? 'In prompt' : 'Sent';
    footer.appendChild(state);
    footer.appendChild(textButton(d, 'Edit', () => onEdit(comment)));
    footer.appendChild(textButton(d, 'Resolve', () => onResolve(comment)));
    card.appendChild(footer);
    margin.appendChild(card);
  }
  if (composer) margin.appendChild(composer);
  margin.classList.toggle('has-comments', comments.length > 0);
  layoutCards(doc, margin);
}

/**
 * The prototype's composer, in the margin beside the passage: Cancel, and Comment with ⌘↩. Editing an existing
 * comment passes its id and body. onSubmit gets { line, quote, body, id }.
 */
export function openComposer(doc, margin, { line, quote, body = '', id = null }, author, { onSubmit, onCancel }) {
  closeComposer(margin);
  const d = doc.ownerDocument;
  const card = d.createElement('div');
  card.className = 'cmt compose';
  card.setAttribute('data-dotmd-ui', '');
  card.dataset.for = String(line);
  card.appendChild(header(d, author, `on "${shortQuote(quote)}"`));
  const field = d.createElement('textarea');
  field.className = 'ta';
  field.value = body;
  field.setAttribute('aria-label', 'Comment');
  card.appendChild(field);
  const row = d.createElement('div');
  row.className = 'row2';
  const cancel = d.createElement('button');
  cancel.type = 'button';
  cancel.className = 'btn sm';
  cancel.textContent = 'Cancel';
  const save = d.createElement('button');
  save.type = 'button';
  save.className = 'btn sm pri';
  save.innerHTML = 'Comment<kbd>⌘↩</kbd>';
  row.append(cancel, save);
  card.appendChild(row);
  const submit = () => {
    const text = field.value.trim();
    if (!text) return;
    closeComposer(margin);
    onSubmit({ line, quote, body: text, id });
  };
  const dismiss = () => {
    closeComposer(margin);
    onCancel?.();
  };
  cancel.addEventListener('click', dismiss);
  save.addEventListener('click', submit);
  field.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && event.metaKey) {
      event.preventDefault();
      submit();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      dismiss();
    }
  });
  margin.appendChild(card);
  layoutCards(doc, margin);
  field.focus();
  return card;
}

export function closeComposer(margin) {
  margin.querySelector('.cmt.compose')?.remove();
}

/**
 * Puts each card level with its passage's block, then moves cards down so none overlap: the composer first,
 * as the prototype does when it pushes the saved comment below it.
 */
export function layoutCards(doc, margin, gap = 8) {
  const top = margin.getBoundingClientRect().top;
  const cards = [...margin.querySelectorAll('.cmt')].map((card) => {
    const block = blockAt(doc, Number(card.dataset.for));
    return { card, want: block ? block.getBoundingClientRect().top - top : 0 };
  });
  cards.sort((a, b) => a.want - b.want || (a.card.classList.contains('compose') ? -1 : 1));
  let floor = -Infinity;
  for (const { card, want } of cards) {
    const y = Math.max(want, floor);
    card.style.top = `${y}px`;
    floor = y + card.offsetHeight + gap;
  }
}

/** Whole words up to 20 characters, without trailing punctuation, then an ellipsis: "log every decision…". */
export function shortQuote(quote, limit = 20) {
  if (quote.length <= limit) return quote;
  let out = '';
  for (const word of quote.split(' ')) {
    if ((out ? out.length + 1 : 0) + word.length > limit) break;
    out = out ? `${out} ${word}` : word;
  }
  return `${(out || quote.slice(0, limit)).replace(/[,;:.]+$/, '')}…`;
}

function header(d, author, note) {
  const row = d.createElement('div');
  row.className = 'h';
  const avatar = d.createElement('span');
  avatar.className = 'av';
  avatar.textContent = author.initial;
  const name = d.createElement('b');
  name.textContent = author.name;
  const meta = d.createElement('span');
  meta.textContent = note;
  row.append(avatar, name, meta);
  return row;
}

function textButton(d, label, action) {
  const b = d.createElement('button');
  b.type = 'button';
  b.textContent = label;
  b.addEventListener('click', action);
  return b;
}
