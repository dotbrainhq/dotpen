// Code, diagrams, math, front matter, MDX labels and dotPen's own marks aren't read as prose, so they don't count.
const NOT_PROSE = 'pre, figure, .meta, .katex, .mdx-label, [data-dotpen-ui]';
const WORDS_PER_MINUTE = 230;

const outlineHeadings = (doc) => [...doc.querySelectorAll(':scope > h1, :scope > h2')];

/** How many words of prose the page has. */
export function countWords(doc) {
  const prose = doc.cloneNode(true);
  prose.querySelectorAll(NOT_PROSE).forEach((el) => el.remove());
  // textContent runs adjacent blocks together, so a heading's last word would join the next paragraph's first.
  prose.querySelectorAll('p, li, h1, h2, h3, h4, h5, h6, td, th, dt, dd, div, blockquote').forEach((el) => el.append(' '));
  return prose.textContent.match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu)?.length ?? 0;
}

/** "1,240 words · 6 min read": minutes round up, and even a short page takes one. */
export function statsLabel(words) {
  const minutes = Math.max(1, Math.ceil(words / WORDS_PER_MINUTE));
  return `${words.toLocaleString('en-US')} ${words === 1 ? 'word' : 'words'} · ${minutes} min read`;
}

/**
 * The prototype's .toc: the page title and its sections in the right margin. Clicking one scrolls to it.
 * Only top-level h1 and h2 count, so headings inside raw HTML like <details> stay out. Comment cards in the margin
 * stay where they are. The word count and reading time sit under the last section.
 */
export function buildOutline(doc, margin, { reduceMotion = false } = {}) {
  margin.querySelector('.toc')?.remove();
  const headings = outlineHeadings(doc);
  if (headings.length < 2) return;
  const nav = doc.ownerDocument.createElement('nav');
  nav.className = 'toc';
  for (const heading of headings) {
    const item = doc.ownerDocument.createElement('button');
    item.type = 'button';
    item.textContent = heading.textContent.trim();
    item.addEventListener('click', () => heading.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'start' }));
    nav.appendChild(item);
  }
  const stats = doc.ownerDocument.createElement('p');
  stats.className = 'toc-stats';
  stats.textContent = statsLabel(countWords(doc));
  nav.appendChild(stats);
  margin.prepend(nav);
}

/**
 * The section being read: the last heading at or above offset from the top of the view, or the first when none
 * is yet. At the bottom of the page it's the last one, which may never reach the top.
 */
export function currentIndex(tops, offset, { atBottom = false } = {}) {
  if (atBottom) return tops.length - 1;
  let index = 0;
  tops.forEach((top, i) => { if (top <= offset) index = i; });
  return index;
}

/** Marks the outline entry for the section being read. */
export function markCurrent(margin, doc, { offset = 96, atBottom = false, topOf = (el) => el.getBoundingClientRect().top } = {}) {
  const buttons = [...margin.querySelectorAll('.toc button')];
  if (!buttons.length) return;
  const index = currentIndex(outlineHeadings(doc).map(topOf), offset, { atBottom });
  buttons.forEach((button, i) => {
    button.classList.toggle('current', i === index);
    if (i === index) button.setAttribute('aria-current', 'location');
    else button.removeAttribute('aria-current');
  });
}
