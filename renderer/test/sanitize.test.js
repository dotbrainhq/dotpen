import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { renderDocument } from '../src/document.js';
import { createSanitizer } from '../src/sanitize.js';

const sanitize = createSanitizer(new JSDOM('').window);
const render = (src) => renderDocument(src, sanitize);

test('picture elements keep their sources', () => {
  const html = render('<picture>\n<source media="(prefers-color-scheme: dark)" srcset="dark.png">\n<img src="light.png" alt="Cover">\n</picture>');
  assert.match(html, /<picture>\s*<source media="\(prefers-color-scheme: dark\)" srcset="dark.png">\s*<img src="light.png" alt="Cover">\s*<\/picture>/);
});

test('scripts, event handlers and iframes are removed', () => {
  const html = render('<script>alert(1)</script>\n\n<img src="a.png" onerror="alert(1)">\n\n<iframe src="https://example.com"></iframe>');
  assert.doesNotMatch(html, /<script|onerror|<iframe/);
  assert.match(html, /<img src="a.png">/);
});

test('forms and style elements are removed', () => {
  const html = render('<form action="https://example.com"><button>Go</button></form>\n\n<style>body { display: none }</style>');
  assert.doesNotMatch(html, /<form|<button|<style/);
});

test('style attributes are removed outside math', () => {
  const html = render('<div style="position: fixed" align="center">Hi</div>');
  assert.match(html, /<div align="center">Hi<\/div>/);
});

test('math keeps the inline styles KaTeX needs', () => {
  const html = render('$\\frac{a}{b}^2$');
  assert.match(html, /class="katex"/);
  assert.match(html, /style="/);
});

test('a katex class cannot carry a style attribute', () => {
  const html = render('<div class="katex" style="position:fixed;inset:0;background:red">cover</div>');
  assert.doesNotMatch(html, /style=/);
  assert.match(html, />cover</);
});

test('a forged math slot stays an empty span', () => {
  const html = render('<span data-math-slot="anything-0"></span>\n\n$x^2$');
  assert.match(html, /<span data-math-slot="anything-0"><\/span>/);
  assert.equal(html.match(/class="katex"/g).length, 1);
});

test('math renders with KaTeX inline styles and its TeX annotation', () => {
  const html = render('$x^2$');
  assert.match(html, /style="/);
  assert.match(html, /<annotation encoding="application\/x-tex">x\^2<\/annotation>/);
  assert.doesNotMatch(html, /data-math-slot/);
});

test('only checkbox inputs survive, and they stay disabled', () => {
  const html = render('<input type="text" value="x"> <input type="checkbox" checked>');
  assert.doesNotMatch(html, /type="text"/);
  assert.match(html, /<input type="checkbox" checked="" disabled="">/);
});

test('images load over https only', () => {
  const html = render('<img src="http://example.com/a.png"> <img src="https://example.com/b.png">');
  assert.doesNotMatch(html, /http:\/\//);
  assert.match(html, /<img src="https:\/\/example.com\/b.png">/);
});

test('image URLs are read the way browsers read them', () => {
  const html = render('<img src="ht&#9;tp://example.com/a.png"> <img src="HTTP://example.com/b.png">');
  assert.doesNotMatch(html, /src=/);
});

test('background attributes are removed', () => {
  const html = render('<table background="https://example.com/t.png"><tr><td>x</td></tr></table>');
  assert.doesNotMatch(html, /background/);
  assert.match(html, /<td>x<\/td>/);
});

test('srcset needs every candidate to be https', () => {
  const bad = render('<picture><source srcset="http://example.com/a.png 1x, https://example.com/b.png 2x"><img src="c.png"></picture>');
  assert.doesNotMatch(bad, /srcset/);
  const good = render('<picture><source srcset="https://example.com/a.png 1x, https://example.com/b.png 2x"><img src="c.png"></picture>');
  assert.match(good, /srcset="https:\/\/example.com\/a.png 1x, https:\/\/example.com\/b.png 2x"/);
});

test('relative and data image sources are kept', () => {
  const html = render('<img src="images/local.png"> <img src="data:image/png;base64,iVBORw0KGgo=">');
  assert.match(html, /<img src="images\/local.png">/);
  assert.match(html, /<img src="data:image\/png;base64,iVBORw0KGgo=">/);
});

test('details, summary, kbd and sup render', () => {
  const html = render('<details><summary>More</summary>\n\nHidden **text**\n\n</details>\n\nPress <kbd>Cmd</kbd> + <kbd>K</kbd>, x<sup>2</sup>');
  assert.match(html, /<details><summary>More<\/summary>/);
  assert.match(html, /<strong>text<\/strong>/);
  assert.match(html, /<kbd>Cmd<\/kbd>/);
  assert.match(html, /x<sup>2<\/sup>/);
});

test('javascript links lose their href', () => {
  const html = render('<a href="javascript:alert(1)">x</a>');
  assert.match(html, /<a>x<\/a>/);
});

test('renderDocument refuses to run without a sanitizer', () => {
  assert.throws(() => renderDocument('# Hi'), TypeError);
});
