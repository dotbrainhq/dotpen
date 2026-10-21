import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';
import { applyMarks, removeMarks, fadeMarks, blockAt } from '../src/marks.js';
import { blockWords } from '../src/words.js';

function page(markdown) {
  const dom = new JSDOM('<main id="doc"></main>');
  const doc = dom.window.document.getElementById('doc');
  doc.innerHTML = renderDocument(markdown, createSanitizer(dom.window));
  return doc;
}

const after = `# Rate limiter rollout

Move the API from a fixed per-IP limit to a token bucket per API key. Ship it behind a flag and roll it out to internal keys first, then 5% of traffic.

## Steps

- [x] Add \`TokenBucket\` with Redis backing
- [x] Put it behind the \`rate_limit_v2\` flag
- [ ] Shadow mode: log every decision, block nothing
- [ ] Roll out to internal keys for one day
`;

// What ChangeDiff produces for the prototype's scenario (see ChangeDiffTests).
const changes = {
  added: [{ start: 9, end: 9 }],
  changed: [{ start: 3, end: 3, words: [
    { kind: 'keep', count: 25 }, { kind: 'delete', count: 0, text: '10%' }, { kind: 'insert', count: 5 }, { kind: 'keep', count: 2 },
  ] }],
  removed: [{ afterLine: 7, lineCount: 1, text: '- [x] Load the limits from config' }],
};

test('a block\'s words match what Swift counts', () => {
  const doc = page(after);
  assert.deepEqual(blockWords(blockAt(doc, 7)), ['Add', 'TokenBucket', 'with', 'Redis', 'backing']);
  assert.equal(blockWords(blockAt(doc, 3)).length, 32);
});

test('rewritten words are struck and the new ones marked', () => {
  const doc = page(after);
  applyMarks(doc, changes);
  const p = blockAt(doc, 3);
  assert.equal(p.querySelector('.del').textContent, '10%');
  assert.deepEqual([...p.querySelectorAll('.ins')].map((s) => s.textContent).join(' '), 'internal keys first, then 5%');
  assert.match(p.textContent, /roll it out to 10% internal keys first, then 5% of traffic\./);
});

test('an added block gets the bar and a removal gets its tag', () => {
  const doc = page(after);
  applyMarks(doc, changes);
  assert.ok(blockAt(doc, 9).classList.contains('added'));
  const tag = blockAt(doc, 7).querySelector('.gut.rm');
  assert.equal(tag.textContent, '−1');
  assert.equal(tag.title, '1 line removed. Click to show it.');
});

test('clicking the tag shows the removed text below the block', () => {
  const doc = page(after);
  applyMarks(doc, changes);
  const tag = blockAt(doc, 7).querySelector('.gut.rm');
  tag.click();
  assert.equal(blockAt(doc, 7).nextElementSibling.textContent, '- [x] Load the limits from config');
  assert.equal(tag.getAttribute('aria-expanded'), 'true');
  tag.click();
  assert.ok(!blockAt(doc, 7).nextElementSibling?.classList.contains('removed'));
});

test('a block whose words don\'t line up gets the bar instead', () => {
  const doc = page(after);
  applyMarks(doc, { changed: [{ start: 3, end: 3, words: [{ kind: 'keep', count: 3 }, { kind: 'insert', count: 1 }] }] });
  const p = blockAt(doc, 3);
  assert.ok(p.classList.contains('added'));
  assert.equal(p.querySelector('.ins'), null);
});

test('a removal at the top tags the first block', () => {
  const doc = page('# Title\n\nText.\n');
  applyMarks(doc, { removed: [{ afterLine: 0, lineCount: 2, text: 'Intro\nlines' }] });
  const tag = doc.querySelector('h1 .gut.rm.top');
  assert.equal(tag.textContent, '−2');
  assert.equal(tag.title, '2 lines removed. Click to show them.');
});

test('words split across formatting are marked piece by piece', () => {
  const doc = page('Make **bo**ld happen.\n');
  applyMarks(doc, { changed: [{ start: 1, end: 1, words: [{ kind: 'keep', count: 1 }, { kind: 'insert', count: 1 }, { kind: 'keep', count: 1 }] }] });
  assert.deepEqual([...doc.querySelectorAll('.ins')].map((s) => s.textContent), ['bo', 'ld']);
});

test('removing the marks gives back the page as rendered', () => {
  const doc = page(after);
  const before = doc.innerHTML;
  applyMarks(doc, changes);
  removeMarks(doc);
  assert.equal(doc.innerHTML, before);
});

test('fading takes the marks off when it ends', async () => {
  const doc = page(after);
  const before = doc.innerHTML;
  applyMarks(doc, changes);
  await new Promise((resolve) => fadeMarks(doc, { reduceMotion: true, done: resolve }));
  assert.equal(doc.innerHTML, before);
});
