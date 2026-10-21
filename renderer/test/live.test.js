import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';
import { markLive, setWriting } from '../src/live.js';

function page(markdown) {
  const dom = new JSDOM('<main id="doc"></main>');
  const doc = dom.window.document.getElementById('doc');
  doc.innerHTML = renderDocument(markdown, createSanitizer(dom.window));
  return doc;
}

test('written blocks get the glow', () => {
  const doc = page('# Plan\n\nOne.\n\nTwo.\n');
  markLive(doc, [5]);
  assert.ok(doc.querySelector('[data-line="5"]').classList.contains('live'));
  assert.ok(!doc.querySelector('[data-line="3"]').classList.contains('live'));
});

test('the caret follows the last written block and leaves when writing stops', () => {
  const doc = page('# Plan\n\n- [ ] A\n- [ ] B\n');
  setWriting(doc, true, 4);
  assert.equal(doc.querySelector('[data-line="4"] .caret') !== null, true);
  setWriting(doc, false);
  assert.equal(doc.querySelector('.caret'), null);
});
