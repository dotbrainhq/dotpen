import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderDocument } from '../src/document.js';

test('headings carry their source line', () => {
  const html = renderDocument('# Title\n\nBody text');
  assert.match(html, /<h1 data-line="1" data-line-end="1">Title<\/h1>/);
  assert.match(html, /<p data-line="3" data-line-end="3">Body text<\/p>/);
});

test('front matter becomes a card and keeps later line numbers', () => {
  const html = renderDocument('---\nstatus: in-review\nagent: "claude-code"\n---\n\n# Plan');
  assert.match(html, /<dl class="frontmatter"><div><dt>status<\/dt><dd>in-review<\/dd><\/div><div><dt>agent<\/dt><dd>claude-code<\/dd><\/div><\/dl>/);
  assert.match(html, /<h1 data-line="6" data-line-end="6">Plan<\/h1>/);
});

test('task list items render checkboxes with their line', () => {
  const html = renderDocument('- [x] Done\n- [ ] Next');
  assert.match(html, /<li class="task-list-item" data-line="1" data-line-end="1"><input class="task-list-item-checkbox" checked="" disabled="" type="checkbox">/);
  assert.match(html, /<li class="task-list-item" data-line="2" data-line-end="2"><input class="task-list-item-checkbox" disabled="" type="checkbox">/);
});

test('plain dollar amounts stay text', () => {
  const html = renderDocument('It costs $5 and $10 per month.');
  assert.doesNotMatch(html, /katex/);
  assert.match(html, /\$5 and \$10/);
});

test('dollar amounts before a formula stay text', () => {
  const html = renderDocument('It costs $5 and $10 per month, and the bucket follows $r = n / t$.');
  assert.match(html, /It costs \$5 and \$10 per month, and the bucket follows <eq><span class="katex">/);
  assert.doesNotMatch(html, /katex-error/);
});

test('inline math renders with KaTeX', () => {
  const html = renderDocument('The rate is $r = n / t$ here.');
  assert.match(html, /class="katex"/);
});

test('code fences render as a figure with highlighting', () => {
  const html = renderDocument('```swift\nlet x = 1\n```');
  assert.match(html, /<figure class="code-block" data-line="1" data-line-end="3"><span class="code-lang">swift<\/span><pre><code class="hljs">/);
  assert.match(html, /hljs-keyword/);
});

test('mermaid fences are left for the browser to draw', () => {
  const html = renderDocument('```mermaid\nflowchart LR\n  A --> B\n```');
  assert.match(html, /<figure class="mermaid-block" data-line="1" data-line-end="4"><pre class="mermaid">flowchart LR\n  A --&gt; B\n<\/pre><\/figure>/);
});

test('GitHub alerts become labeled blockquotes', () => {
  const html = renderDocument('> [!WARNING]\n> Careful here');
  assert.match(html, /<blockquote class="alert alert-warning" data-alert="Warning"/);
  assert.match(html, /Careful here/);
  assert.doesNotMatch(html, /\[!WARNING\]/);
});

test('raw HTML is escaped, not rendered', () => {
  const html = renderDocument('<script>alert(1)</script>');
  assert.doesNotMatch(html, /<script>/);
});

test('footnotes render', () => {
  const html = renderDocument('Text[^1]\n\n[^1]: Note');
  assert.match(html, /class="footnotes"/);
});
