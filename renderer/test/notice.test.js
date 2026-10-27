import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { showNotice, diagramErrorHTML, diagramErrorMessage } from '../src/notice.js';

function page() {
  const dom = new JSDOM('<body><div class="paper"><main id="doc"></main></div></body>');
  return dom.window.document;
}

test('a notice sits above the page with its buttons', () => {
  const d = page();
  const calls = [];
  showNotice(d, {
    icon: 'trash',
    title: 'rate-limiter.md has gone missing.',
    text: "You're reading the copy from 2:14 PM.",
    buttons: [{ id: 'find', label: 'Find It' }, { id: 'close', label: 'Close', quiet: true }],
  }, (id) => calls.push(id));
  const notice = d.querySelector('.notice');
  assert.equal(notice.nextElementSibling.className, 'paper');
  assert.equal(notice.getAttribute('role'), 'status');
  assert.equal(notice.querySelector('span').textContent, "rate-limiter.md has gone missing. You're reading the copy from 2:14 PM.");
  const [find, close] = notice.querySelectorAll('button');
  assert.equal(close.className, 'nb q');
  find.click();
  close.click();
  assert.deepEqual(calls, ['find', 'close']);
});

test('a new notice replaces the old one, and none removes it', () => {
  const d = page();
  showNotice(d, { icon: 'gauge', title: "This one's big, 2.4 MB.", text: 'dotPen shows the first 2,000 lines so it stays quick.', buttons: [] }, () => {});
  showNotice(d, { icon: 'trash', title: 'Gone.', text: '', buttons: [] }, () => {});
  assert.equal(d.querySelectorAll('.notice').length, 1);
  assert.match(d.querySelector('.notice b').textContent, /Gone/);
  showNotice(d, null, () => {});
  assert.equal(d.querySelector('.notice'), null);
});

test('the diagram card escapes the error and keeps the source hidden', () => {
  const html = diagramErrorHTML('unknown arrow "-->>"', 'flowchart LR\n  A -->> <B>');
  assert.match(html, /This diagram didn't render/);
  assert.match(html, /unknown arrow &quot;--&gt;&gt;&quot;/);
  assert.match(html, /<pre class="dg-src" hidden>flowchart LR\n  A --&gt;&gt; &lt;B&gt;<\/pre>/);
  assert.match(html, /<button class="nb" type="button">Show Source<\/button>/);
});

test('the diagram message names the line Mermaid stopped at', () => {
  const source = 'flowchart LR\n  A -->> B';
  const parse = new Error("Parse error on line 2:\nflowchart LR A -->> B\n----------------^\nExpecting 'AMP', got 'TAGEND'");
  assert.equal(diagramErrorMessage(parse, source), 'Mermaid stopped at line 2: A -->> B');
  assert.equal(diagramErrorMessage(new Error('No diagram type detected\nfor text: hello'), 'hello'), "Mermaid couldn't make sense of this diagram.");
  assert.equal(diagramErrorMessage(new Error('Parse error on line 9:'), source), "Mermaid couldn't make sense of this diagram.");
});
