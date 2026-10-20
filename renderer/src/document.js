import MarkdownIt from 'markdown-it';
import taskLists from 'markdown-it-task-lists';
import footnote from 'markdown-it-footnote';
import texmath from 'markdown-it-texmath';
import katex from 'katex';
import hljs from 'highlight.js/lib/common';
import { lineNumbers } from './lines.js';
import { alerts } from './alerts.js';
import { splitFrontMatter, frontMatterHTML } from './frontmatter.js';
import { escapeHtml } from './escape.js';

export { escapeHtml };

// Inline math may not contain a dollar sign, so prices like "$5 and $10" before a real formula stay text.
texmath.rules.dollars.inline.find((rule) => rule.name === 'math_inline').rex =
  /\$((?:[^\s\\$])|(?:[^\s$][^$]*?[^\s\\$]))\$/gy;

// KaTeX output carries inline styles the sanitizer would strip, so it never goes through the sanitizer.
// The engine hands markdown-it a placeholder, and renderDocument swaps the real markup in afterwards.
// The nonce is fresh per render, so a document cannot forge a slot.
let mathNonce = '';
let mathStore = [];
const mathEngine = {
  renderToString(tex, options) {
    mathStore.push(katex.renderToString(tex, options));
    return `<span data-math-slot="${mathNonce}-${mathStore.length - 1}"></span>`;
  },
};

const md = new MarkdownIt({ html: true, linkify: true, typographer: false })
  .use(taskLists, { enabled: false })
  .use(footnote)
  .use(texmath, { engine: mathEngine, delimiters: 'dollars', katexOptions: { throwOnError: false } })
  .use(alerts)
  .use(lineNumbers);

md.renderer.rules.fence = (tokens, idx) => {
  const token = tokens[idx];
  const lang = (token.info || '').trim().split(/\s+/)[0];
  const lines = token.map ? ` data-line="${token.map[0] + 1}" data-line-end="${token.map[1]}"` : '';
  if (lang === 'mermaid') {
    return `<figure class="mermaid-block"${lines}><pre class="mermaid">${escapeHtml(token.content)}</pre></figure>\n`;
  }
  const body = lang && hljs.getLanguage(lang)
    ? hljs.highlight(token.content, { language: lang, ignoreIllegals: true }).value
    : escapeHtml(token.content);
  const label = lang ? `<span class="code-lang">${escapeHtml(lang)}</span>` : '';
  return `<figure class="code-block"${lines}>${label}<pre><code class="hljs">${body}</code></pre></figure>\n`;
};

/** Renders Markdown to HTML. Raw HTML is allowed in the source, so the caller must pass a sanitizer. */
export function renderDocument(src, sanitize) {
  if (typeof sanitize !== 'function') throw new TypeError('renderDocument needs a sanitize function');
  const { body, fields } = splitFrontMatter(src);
  mathNonce = globalThis.crypto.randomUUID();
  mathStore = [];
  const store = mathStore;
  const nonce = mathNonce;
  const clean = sanitize(frontMatterHTML(fields) + md.render(body));
  return clean.replace(new RegExp(`<span data-math-slot="${nonce}-(\\d+)"></span>`, 'g'), (_, i) => store[Number(i)]);
}
