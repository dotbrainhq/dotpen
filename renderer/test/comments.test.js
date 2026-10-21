import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';
import { anchorPassage, renderComments, clearComments, openComposer } from '../src/comments.js';
import { selectionInfo, showSelectionBar, hideSelectionBar } from '../src/selection.js';
import { blockAt } from '../src/marks.js';

function page(markdown) {
  const dom = new JSDOM('<main id="doc"></main><aside id="margin"></aside>');
  const d = dom.window.document;
  const doc = d.getElementById('doc');
  doc.innerHTML = renderDocument(markdown, createSanitizer(dom.window));
  return { dom, doc, margin: d.getElementById('margin') };
}

const plan = '# Plan\n\n## Steps\n\n- [ ] Shadow mode: log every decision, block nothing\n- [ ] Roll out to **internal keys** for one day\n';
const author = { initial: 'S', name: 'You' };
const noop = () => {};

test('a passage gets the dotted underline and its number, across formatting', () => {
  const { doc } = page(plan);
  assert.ok(anchorPassage(blockAt(doc, 6), 'internal keys for one day', 1));
  const block = blockAt(doc, 6);
  assert.equal([...block.querySelectorAll('.anch')].map((s) => s.textContent).join(''), 'internal keys for one day');
  assert.equal(block.querySelector('.num').textContent, '1');
  assert.equal(block.querySelector('.num').previousElementSibling.className, 'anch');
});

test('a passage that isn\'t in the block is left alone', () => {
  const { doc } = page(plan);
  assert.equal(anchorPassage(blockAt(doc, 6), 'everyone', 1), false);
  assert.equal(doc.querySelector('.anch'), null);
});

test('saved comments get the prototype\'s card in the margin', () => {
  const { doc, margin } = page(plan);
  renderComments(doc, margin, [
    { id: 7, line: 6, quote: 'internal keys for one day', body: 'One day is enough.', when: 'now', inPrompt: true, number: 1 },
  ], author, { onEdit: noop, onResolve: noop });
  const card = margin.querySelector('.cmt.saved');
  assert.equal(card.querySelector('.h').textContent, 'SYounow');
  assert.equal(card.querySelector('p').textContent, 'One day is enough.');
  assert.equal(card.querySelector('.f').textContent, 'In promptEditResolve');
  assert.ok(margin.classList.contains('has-comments'));
});

test('a sent comment says so, and its buttons call back', () => {
  const { doc, margin } = page(plan);
  const calls = [];
  renderComments(doc, margin, [
    { id: 7, line: 5, quote: 'log every decision', body: 'Log for a week.', when: '2:20 PM', inPrompt: false, number: 1 },
  ], author, { onEdit: (c) => calls.push(['edit', c.id]), onResolve: (c) => calls.push(['resolve', c.id]) });
  const [edit, resolve] = margin.querySelectorAll('.cmt .f button');
  assert.equal(margin.querySelector('.cmt .f span').textContent, 'Sent');
  edit.click();
  resolve.click();
  assert.deepEqual(calls, [['edit', 7], ['resolve', 7]]);
});

test('clearing the comments gives back the page as rendered', () => {
  const { doc, margin } = page(plan);
  const before = doc.innerHTML;
  renderComments(doc, margin, [
    { id: 7, line: 6, quote: 'internal keys for one day', body: 'x', when: 'now', inPrompt: true, number: 1 },
  ], author, { onEdit: noop, onResolve: noop });
  clearComments(doc, margin);
  assert.equal(doc.innerHTML, before);
  assert.equal(margin.children.length, 0);
});

test('the composer submits with ⌘↩ and cancels with Escape', () => {
  const { dom, doc, margin } = page(plan);
  const submitted = [];
  let cancelled = 0;
  openComposer(doc, margin, { line: 5, quote: 'log every decision, block nothing' }, author, {
    onSubmit: (c) => submitted.push(c), onCancel: () => { cancelled += 1; },
  });
  const card = margin.querySelector('.cmt.compose');
  assert.equal(card.querySelector('.h span:last-child').textContent, 'on "log every decision…"');
  const field = card.querySelector('textarea');
  field.value = '  Log for a week before we block anything. ';
  field.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key: 'Enter', metaKey: true }));
  assert.deepEqual(submitted, [{ line: 5, quote: 'log every decision, block nothing', body: 'Log for a week before we block anything.', id: null }]);
  assert.equal(margin.querySelector('.cmt.compose'), null);
  openComposer(doc, margin, { line: 5, quote: 'x' }, author, { onSubmit: noop, onCancel: () => { cancelled += 1; } });
  margin.querySelector('textarea').dispatchEvent(new dom.window.KeyboardEvent('keydown', { key: 'Escape' }));
  assert.equal(cancelled, 1);
});

test('an empty comment isn\'t saved', () => {
  const { dom, doc, margin } = page(plan);
  const submitted = [];
  openComposer(doc, margin, { line: 5, quote: 'x' }, author, { onSubmit: (c) => submitted.push(c), onCancel: noop });
  margin.querySelector('.btn.pri').click();
  assert.deepEqual(submitted, []);
  assert.ok(margin.querySelector('.cmt.compose'));
});

test('a selection inside a block gives its text and line', () => {
  const { dom, doc } = page(plan);
  const d = dom.window.document;
  const text = blockAt(doc, 5).lastChild;
  const range = d.createRange();
  const at = text.data.indexOf('log every');
  range.setStart(text, at);
  range.setEnd(text, at + 'log every decision'.length);
  const selection = dom.window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  assert.deepEqual(selectionInfo(doc, selection), { text: 'log every decision', line: 5 });
  selection.removeAllRanges();
  assert.equal(selectionInfo(doc, selection), null);
});

test('the selection bar offers Comment only where comments are kept', () => {
  const { doc } = page(plan);
  const rect = { left: 100, top: 300, width: 80, height: 20 };
  const bar = showSelectionBar(doc, rect, { canComment: true, onComment: noop, onCopy: noop, onPrompt: noop });
  assert.equal(bar.textContent, 'CommentCCopyCopy as prompt');
  showSelectionBar(doc, rect, { canComment: false, onComment: noop, onCopy: noop, onPrompt: noop });
  assert.equal(doc.ownerDocument.querySelectorAll('.selpop').length, 1);
  assert.equal(doc.ownerDocument.querySelector('.selpop').textContent, 'CopyCopy as prompt');
  hideSelectionBar(doc);
  assert.equal(doc.ownerDocument.querySelector('.selpop'), null);
});
