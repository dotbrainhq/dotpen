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

const md = new MarkdownIt({ html: false, linkify: true, typographer: false })
  .use(taskLists, { enabled: false })
  .use(footnote)
  .use(texmath, { engine: katex, delimiters: 'dollars', katexOptions: { throwOnError: false } })
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

export function renderDocument(src) {
  const { body, fields } = splitFrontMatter(src);
  return frontMatterHTML(fields) + md.render(body);
}
