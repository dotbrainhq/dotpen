import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';

const sanitize = createSanitizer(new JSDOM('').window);
const mdx = (src) => renderDocument(src, sanitize, { format: 'mdx' });
const markdown = (src) => renderDocument(src, sanitize);

test('import and export lines show as one labeled code block', () => {
  const html = mdx("import Tabs from '@theme/Tabs';\nimport TabItem from '@theme/TabItem';\n\n# Install\n");
  assert.match(html, /<figure class="mdx-block mdx-code" data-line="1" data-line-end="2"><figcaption class="mdx-label">Imports<\/figcaption><pre><code>import Tabs from '@theme\/Tabs';\nimport TabItem from '@theme\/TabItem';<\/code><\/pre><\/figure>/);
  assert.match(html, /<h1 data-line="4" data-line-end="4">Install<\/h1>/);
});

test('a block mixing imports and exports says so', () => {
  const html = mdx("import X from 'x';\nexport const meta = { title: 'Intro' };\n");
  assert.match(html, /<figcaption class="mdx-label">Imports and exports<\/figcaption>/);
});

test('a component wraps its Markdown children under a label', () => {
  const html = mdx('<Callout type="warning">\n\n**Careful** with this one.\n\n</Callout>\n\nAfter');
  assert.match(html, /<div class="mdx-block mdx-component" data-line="1" data-line-end="5"><div class="mdx-label">&lt;Callout type="warning"&gt;<\/div><div class="mdx-children"><p><strong>Careful<\/strong> with this one.<\/p>\n<\/div><\/div>/);
  assert.match(html, /<p data-line="7" data-line-end="7">After<\/p>/);
});

test('nested and indented components stay components, not code', () => {
  const html = mdx('<Tabs>\n    <TabItem value="mac">\n\n    Run `brew install dotpen`.\n\n    </TabItem>\n</Tabs>\n');
  assert.match(html, /<div class="mdx-label">&lt;Tabs&gt;<\/div><div class="mdx-children"><div class="mdx-block mdx-component"><div class="mdx-label">&lt;TabItem value="mac"&gt;<\/div>/);
  assert.match(html, /<p>Run <code>brew install dotpen<\/code>\.<\/p>/);
  assert.doesNotMatch(html, /code-block/);
});

test('a self-closing component shows its source under its name', () => {
  const html = mdx('<Image\n  src="/img/hero.png"\n  alt="Hero"\n/>\n');
  assert.match(html, /<figure class="mdx-block mdx-code" data-line="1" data-line-end="4"><figcaption class="mdx-label">&lt;Image \/&gt;<\/figcaption><pre><code>&lt;Image\n  src="\/img\/hero.png"\n  alt="Hero"\n\/&gt;<\/code><\/pre><\/figure>/);
});

test('a component closed on its own line keeps its text inline', () => {
  const html = mdx('<Badge>New</Badge>\n');
  assert.match(html, /<div class="mdx-label">&lt;Badge&gt;<\/div><div class="mdx-children">New<\/div>/);
});

test('comments disappear and other expressions show as code', () => {
  const html = mdx('{/* Hidden note for writers */}\n\nHello {props.name}, welcome.\n\n{items.map((i) => i.title)}\n');
  assert.doesNotMatch(html, /Hidden note/);
  assert.match(html, /Hello <code class="mdx-expression">\{props\.name\}<\/code>, welcome\./);
  assert.match(html, /<figcaption class="mdx-label">Expression<\/figcaption><pre><code>\{items\.map\(\(i\) =&gt; i\.title\)\}<\/code><\/pre>/);
});

test('components inside a paragraph are labeled inline', () => {
  const html = mdx('Status: <Badge text="Beta" /> and <Highlight>this part</Highlight>.');
  assert.match(html, /<code class="mdx-inline">&lt;Badge text="Beta" \/&gt;<\/code>/);
  assert.match(html, /<span class="mdx-inline-component" data-component="Highlight">this part<\/span>/);
});

test('nothing in MDX ever runs', () => {
  const html = mdx('export const x = alert(1);\n\n<Button onClick={() => alert(2)}>Go</Button>\n\n<Script>alert(3)</Script>\n\nInline {alert(4)}');
  const page = new JSDOM(html).window.document;
  assert.equal(page.querySelectorAll('script').length, 0);
  assert.equal([...page.querySelectorAll('*')].filter((el) => [...el.attributes].some((a) => a.name.startsWith('on'))).length, 0);
  assert.match(html, /&lt;Button onClick=\{\(\) =&gt; alert\(2\)\}&gt;/);
});

test('code fences, HTML and math work the same in MDX', () => {
  const html = mdx('```jsx\n<Tabs>\n```\n\n<details><summary>More</summary>\n\nBody\n\n</details>\n\nRate $\\frac{a}{b}$');
  assert.match(html, /<figure class="code-block" data-line="1" data-line-end="3"><span class="code-lang">jsx<\/span>/);
  assert.match(html, /<details><summary>More<\/summary>/);
  assert.match(html, /katex/);
  assert.doesNotMatch(html, /mdx-expression/);
});

test('plain Markdown files keep reading imports, components and braces as text', () => {
  const html = markdown("import X from 'x';\n\nHello {name}\n\n    indented code");
  assert.match(html, /<p data-line="1" data-line-end="1">import X from 'x';<\/p>/);
  assert.match(html, /Hello \{name\}/);
  assert.match(html, /<pre[^>]*><code>indented code/);
  assert.doesNotMatch(html, /mdx-/);
});
