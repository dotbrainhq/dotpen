import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { buildOutline, currentIndex, markCurrent, statsLabel } from '../src/outline.js';

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

test('the outline ends with the word count and reading time, counting prose only', () => {
  const { doc, margin } = page('<div class="meta"><span>Status in review</span></div><h1>Title here</h1><p>One two three.</p>'
    + '<figure class="code-block"><pre>let x = 1</pre></figure><figure class="mermaid-block"><pre>graph LR</pre></figure>'
    + '<h2>Next part</h2><p>Four <span class="del" data-dotpen-ui="">old</span> five</p>');
  buildOutline(doc, margin);
  assert.equal(margin.querySelector('.toc .toc-stats').textContent, '9 words · 1 min read');
  assert.deepEqual([...margin.querySelectorAll('.toc button')].map((b) => b.textContent), ['Title here', 'Next part']);
});

test('reading time rounds up at 230 words a minute', () => {
  assert.equal(statsLabel(1), '1 word · 1 min read');
  assert.equal(statsLabel(230), '230 words · 1 min read');
  assert.equal(statsLabel(231), '231 words · 2 min read');
  assert.equal(statsLabel(1240), '1,240 words · 6 min read');
});

test('the current section is the last heading at or above the top of the view', () => {
  assert.equal(currentIndex([-300, -20, 150], 96), 1);
  assert.equal(currentIndex([20, 400], 96), 0);
  assert.equal(currentIndex([200, 400], 96), 0);
  assert.equal(currentIndex([-900, -400, 300], 96, { atBottom: true }), 2);
});

test('the outline marks the section being read and clears the rest', () => {
  const { doc, margin } = page('<h1>A</h1><p>x</p><h2>B</h2><p>y</p><h2>C</h2>');
  buildOutline(doc, margin);
  const tops = new Map([...doc.querySelectorAll('h1, h2')].map((h, i) => [h, [-500, 40, 600][i]]));
  markCurrent(margin, doc, { topOf: (h) => tops.get(h) });
  const buttons = [...margin.querySelectorAll('.toc button')];
  assert.deepEqual(buttons.map((b) => b.classList.contains('current')), [false, true, false]);
  assert.deepEqual(buttons.map((b) => b.getAttribute('aria-current')), [null, 'location', null]);
  tops.set(doc.querySelector('h2:last-of-type'), 10);
  markCurrent(margin, doc, { topOf: (h) => tops.get(h) });
  assert.deepEqual(buttons.map((b) => b.classList.contains('current')), [false, false, true]);
});
