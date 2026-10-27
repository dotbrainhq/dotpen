import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sourceHTML } from '../src/source.js';

test('the source shows each line numbered and escaped', () => {
  const html = sourceHTML('# Plan\n\n<b>bold</b>\r\n');
  assert.equal((html.match(/class="sl"/g) ?? []).length, 3);
  assert.match(html, /<span class="sl" data-line="1"><span class="ln" aria-hidden="true">1<\/span><span class="st"># Plan<\/span><\/span>/);
  assert.match(html, /data-line="3"><span class="ln" aria-hidden="true">3<\/span><span class="st">&lt;b&gt;bold&lt;\/b&gt;<\/span>/);
  assert.match(html, /^<pre class="source">/);
});

test('switching views keeps the line at the top', async () => {
  const { JSDOM } = await import('jsdom');
  const { sourceTopLine, blockForLine } = await import('../src/source.js');
  const { document } = new JSDOM('<main id="doc"></main>').window;
  const doc = document.getElementById('doc');
  doc.innerHTML = sourceHTML('a\nb\nc\n');
  const rows = [...doc.querySelectorAll('.sl')];
  rows.forEach((row, i) => { row.getBoundingClientRect = () => ({ top: i * 20 - 30, bottom: i * 20 - 10 }); });
  assert.equal(sourceTopLine(doc), 2);
  doc.innerHTML = '<h1 data-line="1">T</h1><p data-line="3" data-line-end="7">P</p><p data-line="9">Q</p>';
  assert.equal(blockForLine(doc, 5).textContent, 'P');
  assert.equal(blockForLine(doc, 9).textContent, 'Q');
  assert.equal(blockForLine(doc, 2).textContent, 'T');
});
