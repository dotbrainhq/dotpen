// DotMD's own controls and KaTeX's hidden MathML aren't part of a block's words.
const SKIP = '[data-dotmd-ui], .katex-mathml, .code-lang, button.copy';

/** The text nodes a block shows, in order. */
export function textNodes(block) {
  const walker = block.ownerDocument.createTreeWalker(block, 4, {
    acceptNode: (node) => (node.parentElement?.closest(SKIP) ? 2 : 1),
  });
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  return nodes;
}

/**
 * Every word a block shows, with where it sits: a word can span several text nodes, as "**bo**ld" does.
 * Each word is a list of { node, start, end } pieces.
 */
export function wordPieces(block) {
  const nodes = textNodes(block);
  let joined = '';
  const starts = [];
  for (const node of nodes) {
    starts.push(joined.length);
    joined += node.data;
  }
  const words = [];
  const pattern = /\S+/g;
  let match;
  while ((match = pattern.exec(joined))) {
    const from = match.index;
    const to = from + match[0].length;
    const pieces = [];
    nodes.forEach((node, i) => {
      const start = Math.max(from, starts[i]);
      const end = Math.min(to, starts[i] + node.data.length);
      if (start < end) pieces.push({ node, start: start - starts[i], end: end - starts[i] });
    });
    words.push(pieces);
  }
  return words;
}

export function blockWords(block) {
  return wordPieces(block).map((pieces) => pieces.map((p) => p.node.data.slice(p.start, p.end)).join(''));
}
