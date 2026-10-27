import { escapeHtml } from './escape.js';

// MDX: Markdown with import and export lines, JSX components and {expressions}. dotPen shows them and never runs
// them. Module code and expressions show as labeled code, and a component shows as a labeled block around its
// Markdown children. Lowercase tags stay HTML, as in plain Markdown.

const COMMENT = /^\{\s*\/\*[\s\S]*\*\/\s*\}$/;

// The end of a quoted or template string that starts at i, or max when it never closes.
function skipString(src, i, max) {
  const quote = src[i];
  for (i++; i < max; i++) {
    if (src[i] === '\\') i++;
    else if (src[i] === quote) return i;
  }
  return max;
}

/** The index just past the brace that closes the expression opening at pos, or -1. */
export function scanExpression(src, pos, max) {
  let depth = 0;
  for (let i = pos; i < max; i++) {
    const c = src[i];
    if (c === '"' || c === "'" || c === '`') i = skipString(src, i, max);
    else if (c === '{') depth++;
    else if (c === '}' && --depth === 0) return i + 1;
  }
  return -1;
}

/** The tag that opens at pos: its name, whether it closes or closes itself, and the index just past its ">". */
export function scanTag(src, pos, max) {
  let i = pos + 1;
  const closing = src[i] === '/';
  if (closing) i++;
  const name = /^[A-Za-z_$][\w$.:-]*/.exec(src.slice(i, i + 200))?.[0] ?? '';
  for (i += name.length; i < max; i++) {
    const c = src[i];
    if (c === '"' || c === "'") i = skipString(src, i, max);
    else if (c === '{') {
      const end = scanExpression(src, i, max);
      if (end === -1) return null;
      i = end - 1;
    } else if (c === '>') return { name, closing, selfClosing: src[i - 1] === '/', end: i + 1 };
  }
  return null;
}

// A component starts with a capital letter; <> opens a fragment.
const startsComponent = (src, pos) => src[pos] === '<' && /[A-Z>]/.test(src[pos + 1] ?? '');

function lineAt(state, offset, from, to) {
  for (let line = from; line < to; line++) if (offset <= state.eMarks[line]) return line;
  return to - 1;
}

const lineText = (state, line) => state.src.slice(state.bMarks[line] + state.tShift[line], state.eMarks[line]);

function moduleCode(state, startLine, endLine, silent) {
  if (state.parentType !== 'root' || state.tShift[startLine] !== 0) return false;
  if (!/^(import|export)\b/.test(lineText(state, startLine))) return false;
  if (silent) return true;
  let next = startLine + 1;
  while (next < endLine && !state.isEmpty(next)) next++;
  const token = state.push('mdx_module', 'figure', 0);
  token.block = true;
  token.map = [startLine, next];
  token.content = state.getLines(startLine, next, 0, false).replace(/\n$/, '');
  state.line = next;
  return true;
}

function expressionBlock(state, startLine, endLine, silent) {
  const pos = state.bMarks[startLine] + state.tShift[startLine];
  if (state.src[pos] !== '{') return false;
  const end = scanExpression(state.src, pos, state.eMarks[endLine - 1]);
  if (end === -1) return false;
  const last = lineAt(state, end - 1, startLine, endLine);
  if (state.src.slice(end, state.eMarks[last]).trim()) return false;
  if (silent) return true;
  const content = state.src.slice(pos, end);
  const token = state.push(COMMENT.test(content) ? 'mdx_comment' : 'mdx_expression_block', 'figure', 0);
  token.block = true;
  token.map = [startLine, last + 1];
  token.content = content;
  state.line = last + 1;
  return true;
}

function component(state, startLine, endLine, silent) {
  const pos = state.bMarks[startLine] + state.tShift[startLine];
  if (!startsComponent(state.src, pos)) return false;
  const tag = scanTag(state.src, pos, state.eMarks[endLine - 1]);
  if (!tag || tag.closing) return false;
  if (silent) return true;
  const tagLine = lineAt(state, tag.end - 1, startLine, endLine);
  const indent = state.sCount[startLine];

  if (tag.selfClosing) {
    const token = state.push('mdx_component_void', 'figure', 0);
    token.block = true;
    token.map = [startLine, tagLine + 1];
    token.meta = { name: tag.name };
    token.content = state.getLines(startLine, tagLine + 1, indent, false).replace(/\n$/, '');
    state.line = tagLine + 1;
    return true;
  }

  const open = state.src.slice(pos, tag.end).replace(/\s+/g, ' ');
  const label = open.length > 80 ? `<${tag.name} …>` : open;
  const closeTag = `</${tag.name}>`;
  const rest = state.src.slice(tag.end, state.eMarks[tagLine]);
  const sameLine = rest.indexOf(closeTag);

  let close = -1;
  if (sameLine === -1) {
    // The closing tag on a line of its own, counting nested tags with the same name.
    const opens = tag.name ? new RegExp(`^<${tag.name.replace(/[.$]/g, '\\$&')}[\\s>]`) : /^<>/;
    let depth = 1;
    for (let line = tagLine + 1; line < endLine && close === -1; line++) {
      const text = lineText(state, line);
      if (text.startsWith(closeTag) && --depth === 0) close = line;
      else if (opens.test(text) && !/\/>\s*$/.test(text)) depth++;
    }
  }
  const last = sameLine !== -1 ? tagLine : close === -1 ? endLine - 1 : close;

  const openToken = state.push('mdx_component_open', 'div', 1);
  openToken.block = true;
  openToken.map = [startLine, last + 1];
  openToken.meta = { name: tag.name, label };
  if (sameLine !== -1) {
    const inline = state.push('inline', '', 0);
    inline.content = rest.slice(0, sameLine).trim();
    inline.map = [tagLine, tagLine + 1];
    inline.children = [];
  } else {
    const end = close === -1 ? endLine : close;
    const [parentType, lineMax] = [state.parentType, state.lineMax];
    state.parentType = 'mdx';
    state.lineMax = end;
    state.md.block.tokenize(state, tagLine + 1, end);
    state.parentType = parentType;
    state.lineMax = lineMax;
  }
  state.push('mdx_component_close', 'div', -1).block = true;
  state.line = last + 1;
  return true;
}

function inlineExpression(state, silent) {
  if (state.src[state.pos] !== '{') return false;
  const end = scanExpression(state.src, state.pos, state.posMax);
  if (end === -1) return false;
  const content = state.src.slice(state.pos, end);
  if (!silent && !COMMENT.test(content)) state.push('mdx_expression', 'code', 0).content = content;
  state.pos = end;
  return true;
}

function inlineComponent(state, silent) {
  const { src, pos } = state;
  if (src[pos] !== '<' || !/[A-Z]/.test(src[pos + (src[pos + 1] === '/' ? 2 : 1)] ?? '')) return false;
  const tag = scanTag(src, pos, state.posMax);
  if (!tag) return false;
  if (!silent) {
    if (tag.selfClosing) state.push('mdx_inline_void', 'code', 0).content = src.slice(pos, tag.end);
    else if (tag.closing) state.push('mdx_inline_close', 'span', -1);
    else state.push('mdx_inline_open', 'span', 1).meta = { name: tag.name };
  }
  state.pos = tag.end;
  return true;
}

function moduleLabel(content) {
  const words = new Set(content.split('\n').map((line) => /^(import|export)\b/.exec(line)?.[1]).filter(Boolean));
  if (words.size === 2) return 'Imports and exports';
  return words.has('export') ? 'Exports' : 'Imports';
}

const codeFigure = (token, self, label) =>
  `<figure class="mdx-block mdx-code"${self.renderAttrs(token)}><figcaption class="mdx-label">${escapeHtml(label)}</figcaption>` +
  `<pre><code>${escapeHtml(token.content)}</code></pre></figure>\n`;

export function mdx(md) {
  // MDX has no indented code, so children indented under a component stay Markdown.
  md.block.ruler.disable('code');
  md.block.ruler.before('fence', 'mdx_module', moduleCode);
  md.block.ruler.before('html_block', 'mdx_component', component, { alt: ['paragraph'] });
  md.block.ruler.before('html_block', 'mdx_expression_block', expressionBlock);
  md.inline.ruler.before('html_inline', 'mdx_component', inlineComponent);
  md.inline.ruler.before('html_inline', 'mdx_expression', inlineExpression);

  const rules = md.renderer.rules;
  rules.mdx_module = (tokens, i, _, __, self) => codeFigure(tokens[i], self, moduleLabel(tokens[i].content));
  rules.mdx_expression_block = (tokens, i, _, __, self) => codeFigure(tokens[i], self, 'Expression');
  rules.mdx_component_void = (tokens, i, _, __, self) => codeFigure(tokens[i], self, `<${tokens[i].meta.name} />`);
  rules.mdx_comment = () => '';
  rules.mdx_component_open = (tokens, i, _, __, self) =>
    `<div class="mdx-block mdx-component"${self.renderAttrs(tokens[i])}><div class="mdx-label">${escapeHtml(tokens[i].meta.label)}</div><div class="mdx-children">`;
  rules.mdx_component_close = () => '</div></div>\n';
  rules.mdx_expression = (tokens, i) => `<code class="mdx-expression">${escapeHtml(tokens[i].content)}</code>`;
  rules.mdx_inline_void = (tokens, i) => `<code class="mdx-inline">${escapeHtml(tokens[i].content)}</code>`;
  rules.mdx_inline_open = (tokens, i) =>
    `<span class="mdx-inline-component" data-component="${escapeHtml(tokens[i].meta.name)}">`;
  rules.mdx_inline_close = () => '</span>';
}
