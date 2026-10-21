import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { buildOutline } from '../src/outline.js';

function page(html) {
  const dom = new JSDOM(`<main id="doc">${html}</main><aside id="margin"></aside>`);
  const d = dom.window.document;
  return { doc: d.getElementById('doc'), margin: d.getElementById('margin') };
}

test('the title and each section are listed in order', () => {
  const { doc, margin } = page('<h1>Rate limiter rollout</h1><p>x</p><h2>Steps</h2><h3>Detail</h3><h2>Open question</h2>');
  buildOutline(doc, margin);
  assert.deepEqual([...margin.querySelectorAll('.toc button')].map((b) => b.textContent), ['Rate limiter rollout', 'Steps', 'Open question']);
});

test('a page with fewer than two headings gets no outline', () => {
  const { doc, margin } = page('<h1>Only</h1><p>x</p>');
  buildOutline(doc, margin);
  assert.equal(margin.children.length, 0);
});

test('headings inside raw HTML are left out', () => {
  const { doc, margin } = page('<h1>A</h1><details><h2>Hidden</h2></details><h2>B</h2>');
  buildOutline(doc, margin);
  assert.deepEqual([...margin.querySelectorAll('.toc button')].map((b) => b.textContent), ['A', 'B']);
});

test('rebuilding the outline keeps comment cards in the margin', () => {
  const { doc, margin } = page('<h1>A</h1><p>x</p><h2>B</h2>');
  margin.innerHTML = '<div class="cmt saved"></div>';
  buildOutline(doc, margin);
  buildOutline(doc, margin);
  assert.deepEqual([...margin.children].map((el) => el.className), ['toc', 'cmt saved']);
});
