import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';
import { showMemory, blockForLine } from '../src/memory.js';

function page(markdown) {
  const dom = new JSDOM('<main id="doc"></main>');
  const doc = dom.window.document.getElementById('doc');
  doc.innerHTML = renderDocument(markdown, createSanitizer(dom.window));
  return doc;
}

const text = '# Plan\n\nOne.\n\n## Steps\n\n- [ ] A\n- [ ] B\n\nLast.\n';

test('the line goes after the block where reading stopped', () => {
  const doc = page(text);
  showMemory(doc, { line: 8, label: 'You stopped reading here at 1:02 PM' });
  const memory = doc.querySelector('.memory');
  assert.equal(memory.previousElementSibling.tagName, 'UL');
  assert.equal(memory.textContent, 'You stopped reading here at 1:02 PM');
});

test('a line inside a block counts as that block', () => {
  const doc = page(text);
  assert.equal(blockForLine(doc, 4).tagName, 'P');
});

test('no line when reading stopped at the end', () => {
  const doc = page(text);
  assert.equal(showMemory(doc, { line: 10, label: 'x' }), null);
  assert.equal(doc.querySelector('.memory'), null);
});
