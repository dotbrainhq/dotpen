/**
 * The prototype's .toc: the page title and its sections in the right margin. Clicking one scrolls to it.
 * Only top-level h1 and h2 count, so headings inside raw HTML like <details> stay out. Comment cards in the margin
 * stay where they are.
 */
export function buildOutline(doc, margin, { reduceMotion = false } = {}) {
  margin.querySelector('.toc')?.remove();
  const headings = [...doc.querySelectorAll(':scope > h1, :scope > h2')];
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
  margin.prepend(nav);
}
