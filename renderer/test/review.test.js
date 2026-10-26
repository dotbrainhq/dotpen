import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { changeAt, changeLines, showChangeBar, hideChangeBar } from '../src/review.js';

const changes = {
  changed: [{ start: 3, end: 3, words: [] }],
  added: [{ start: 5, end: 5 }],
  removed: [{ afterLine: 5, lineCount: 1, text: 'Log every decision.' }, { afterLine: 0, lineCount: 1, text: 'Intro' }],
};

test('every change has one line, in reading order', () => {
  assert.deepEqual(changeLines(changes), [1, 3, 5]);
});

test('a line names its change: rewritten first, then added, then removed', () => {
  assert.deepEqual(changeAt(changes, 3), { kind: 'changed', at: 3, index: 2, total: 4 });
  assert.deepEqual(changeAt(changes, 5), { kind: 'added', at: 5, index: 3, total: 4 });
  assert.deepEqual(changeAt(changes, 1), { kind: 'removed', at: 0, index: 1, total: 4 });
  assert.equal(changeAt(changes, 9), null);
});

test('the bar offers Accept, Send back and Next, and hides again', () => {
  const { document } = new JSDOM('<body><main id="doc"></main></body>').window;
  const calls = [];
  showChangeBar(document, { kind: 'changed', at: 3, index: 2, total: 4 }, {
    canSendBack: true, onAccept: () => calls.push('accept'), onSendBack: () => calls.push('back'), onNext: () => calls.push('next'),
  });
  const bar = document.querySelector('.chgbar');
  assert.equal(bar.getAttribute('role'), 'toolbar');
  assert.equal(bar.querySelector('.n').textContent, 'Change 2 of 4');
  [...bar.querySelectorAll('button')].forEach((button) => button.click());
  assert.deepEqual(calls, ['accept', 'back', 'next']);
  hideChangeBar(document);
  assert.equal(document.querySelector('.chgbar'), null);
});

test('a removal and a page without comments get no Send back', () => {
  const { document } = new JSDOM('<body></body>').window;
  showChangeBar(document, { kind: 'removed', at: 5, index: 4, total: 4 }, { canSendBack: true, onAccept() {}, onSendBack() {}, onNext() {} });
  assert.equal(document.querySelector('[data-act="back"]'), null);
  showChangeBar(document, { kind: 'added', at: 5, index: 3, total: 4 }, { canSendBack: false, onAccept() {}, onSendBack() {}, onNext() {} });
  assert.equal(document.querySelector('[data-act="back"]'), null);
  assert.equal(document.querySelectorAll('.chgbar').length, 1);
});
