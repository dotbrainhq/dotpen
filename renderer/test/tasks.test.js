import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';
import { prepareTasks, taskLine } from '../src/tasks.js';

const window = new JSDOM('').window;
const sanitize = createSanitizer(window);

function page(src) {
  const doc = window.document.createElement('main');
  doc.innerHTML = renderDocument(src, sanitize);
  return doc;
}

test('task boxes become tab stops that tick in the app', () => {
  const doc = page('- [ ] Load limits\n- [x] Log decisions');
  prepareTasks(doc, true);
  const [first, second] = doc.querySelectorAll('.task-list-item-checkbox');
  assert.equal(first.disabled, false);
  assert.equal(first.getAttribute('tabindex'), '0');
  assert.equal(second.checked, true);
  prepareTasks(doc, false);
  assert.equal(first.disabled, true);
  assert.equal(first.getAttribute('tabindex'), null);
});

test('each box is named by its own item, without nested items', () => {
  const doc = page('- [ ] Roll out\n  - [ ] Internal keys first\n');
  prepareTasks(doc, false);
  const [outer, inner] = doc.querySelectorAll('.task-list-item-checkbox');
  assert.equal(outer.getAttribute('aria-label'), 'Roll out');
  assert.equal(inner.getAttribute('aria-label'), 'Internal keys first');
});

test('a box knows its source line, and other inputs have none', () => {
  const doc = page('# Plan\n\n- [ ] One\n- [ ] Two\n\n<input type="checkbox">');
  const boxes = doc.querySelectorAll('.task-list-item-checkbox');
  assert.equal(taskLine(boxes[1]), 4);
  assert.equal(taskLine(doc.querySelector('input:not(.task-list-item-checkbox)')), null);
});
