import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';
import { showChip, nextChangeLine, previousChangeLine } from '../src/chip.js';

function page(markdown) {
  const dom = new JSDOM('<main id="doc"></main>');
  const doc = dom.window.document.getElementById('doc');
  doc.innerHTML = renderDocument(markdown, createSanitizer(dom.window));
  return doc;
}

const noop = () => {};

test('the chip sits under the status line with the prototype\'s parts', () => {
  const doc = page('---\nstatus: in-review\n---\n# Plan\n');
  showChip(doc, { count: 3, since: 'since 1:02 PM' }, { onNext: noop, onMarkRead: noop });
  assert.equal(doc.children[1].className, 'chip');
  assert.equal(doc.querySelector('.chip').textContent, '3 changessince 1:02 PMNextNMark read');
});

test('without a status line the chip comes first', () => {
  const doc = page('# Plan\n');
  showChip(doc, { count: 1, since: 'since yesterday' }, { onNext: noop, onMarkRead: noop });
  assert.equal(doc.firstElementChild.className, 'chip');
  assert.equal(doc.querySelector('.chip b').textContent, '1 change');
});

test('a count of zero removes the chip', () => {
  const doc = page('# Plan\n');
  showChip(doc, { count: 2, since: 'since Oct 18' }, { onNext: noop, onMarkRead: noop });
  showChip(doc, { count: 0, since: '' }, { onNext: noop, onMarkRead: noop });
  assert.equal(doc.querySelector('.chip'), null);
});

test('the buttons call back', () => {
  const doc = page('# Plan\n');
  const calls = [];
  showChip(doc, { count: 2, since: 'since 1:02 PM' }, { onNext: () => calls.push('next'), onMarkRead: () => calls.push('read') });
  const [next, read] = doc.querySelectorAll('.chip button');
  next.click();
  read.click();
  assert.deepEqual(calls, ['next', 'read']);
});

test('Next goes to the first change below the view, then wraps', () => {
  const tops = { 3: 100, 9: 600, 20: 1500 };
  assert.equal(nextChangeLine([9, 3, 20], 0, (l) => tops[l]), 3);
  assert.equal(nextChangeLine([3, 9, 20], 100, (l) => tops[l]), 9);
  assert.equal(nextChangeLine([3, 9, 20], 2000, (l) => tops[l]), 3);
});

test('Shift-N goes to the last change above the view, then wraps', () => {
  const tops = { 3: 100, 9: 600, 20: 1500 };
  assert.equal(previousChangeLine([9, 3, 20], 604, (l) => tops[l]), 3);
  assert.equal(previousChangeLine([3, 9, 20], 1504, (l) => tops[l]), 9);
  assert.equal(previousChangeLine([3, 9, 20], 50, (l) => tops[l]), 20);
});
