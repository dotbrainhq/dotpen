import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';
import { copyHTML } from '../src/copy.js';

const window = new JSDOM('').window;
const sanitize = createSanitizer(window);

function page(src) {
  const doc = window.document.createElement('main');
  doc.innerHTML = renderDocument(src, sanitize);
  return doc;
}

const body = (html) => html.replace(/^[\s\S]*<body>|<\/body>[\s\S]*$/g, '');

test('Slack gets bold lines for headings and plain boxes for tasks', () => {
  const html = body(copyHTML(page('# Rollout\n\n- [x] Ship the flag\n- [ ] Ramp to 5%'), 'slack'));
  assert.match(html, /<p><b>Rollout<\/b><\/p>/);
  assert.match(html, /☑ Ship the flag/);
  assert.match(html, /☐ Ramp to 5%/);
  assert.doesNotMatch(html, /<input|<h1/);
});

test('Slack gets tables as aligned text', () => {
  const html = body(copyHTML(page('| Plan | Capacity |\n|---|---|\n| Free | 20 |\n| Scale | 500 |'), 'slack'));
  assert.doesNotMatch(html, /<table/);
  assert.match(html, /<pre>Plan  \| Capacity\nFree  \| 20\nScale \| 500<\/pre>/);
});

test('Google Docs keeps headings and tables, styled inline so the paste keeps its look', () => {
  const html = body(copyHTML(page('## Refill\n\n| Plan | Cap |\n|---|---|\n| Free | 20 |\n\n```js\nlet a = 1\n```'), 'docs'));
  assert.match(html, /<h2[^>]*>Refill<\/h2>/);
  assert.match(html, /<table style="[^"]*border-collapse: collapse[^"]*">/);
  assert.match(html, /<td style="[^"]*border: 1px solid[^"]*">Free<\/td>/);
  assert.match(html, /<pre style="[^"]*monospace[^"]*"><code>let a = 1\n?<\/code><\/pre>/);
  assert.doesNotMatch(html, /hljs|code-lang|class="copy"/);
});

test('math pastes as its TeX source, and the status line as one line of text', () => {
  const html = body(copyHTML(page('---\nstatus: in-review\nagent: claude-code\n---\nBurst is $b = r t$ tokens.'), 'docs'));
  assert.match(html, /<code[^>]*>\$b = r t\$<\/code>/);
  assert.doesNotMatch(html, /katex/);
  assert.match(html, /<p[^>]*>In review · Claude Code<\/p>/);
});

test('diagrams paste as their source in Slack, and as the image Docs is handed', () => {
  const doc = page('```mermaid\nflowchart LR\n  A --> B\n```');
  const figure = doc.querySelector('figure.mermaid-block');
  figure.dataset.source = 'flowchart LR\n  A --> B\n';
  figure.innerHTML = '<div class="diagram-light"><svg></svg></div>';
  assert.match(body(copyHTML(doc, 'slack')), /<pre>flowchart LR\n  A --&gt; B\n?<\/pre>/);
  const docs = body(copyHTML(doc, 'docs', { diagramImages: new Map([[figure, 'data:image/png;base64,AAAA']]) }));
  assert.match(docs, /<img src="data:image\/png;base64,AAAA" alt="Diagram"/);
});
