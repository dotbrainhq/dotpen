import { renderDocument, escapeHtml } from './document.js';
import { createSanitizer } from './sanitize.js';
import { rewriteLocalImages } from './assets.js';
import { buildOutline } from './outline.js';
import { applyMarks, fadeMarks, removeMarks, blockAt } from './marks.js';
import { showChip, nextChangeLine, revealBlock } from './chip.js';
import { createMap } from './map.js';
import { showMemory, topLine } from './memory.js';

const root = document.documentElement;
const post = (message) => window.webkit?.messageHandlers?.dotmd?.postMessage(message);
const sanitize = createSanitizer(window);
const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
const reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
// The last marks Swift sent. Every render puts them back, so a reload keeps them.
let marks = null;
const map = createMap(document);
// The line where reading stopped last time, put back after every render.
let memory = null;
let lastSentLine = null;
let scrollTimer = null;

// The line at the top of the view, sent once scrolling pauses, so Swift can remember where reading stopped.
window.addEventListener('scroll', () => {
  clearTimeout(scrollTimer);
  scrollTimer = setTimeout(() => {
    const line = topLine(document.getElementById('doc'));
    if (line && line !== lastSentLine) {
      lastSentLine = line;
      post({ type: 'scrollLine', line });
    }
  }, 400);
}, { passive: true });

function changeCount(changes) {
  return (changes.added?.length ?? 0) + (changes.changed?.length ?? 0) + (changes.removed?.length ?? 0);
}

function changeLines(changes) {
  const lines = [
    ...(changes.added ?? []).map((c) => c.start),
    ...(changes.changed ?? []).map((c) => c.start),
    ...(changes.removed ?? []).map((r) => Math.max(r.afterLine, 1)),
  ];
  return [...new Set(lines)].sort((a, b) => a - b);
}

// A revealed block sits 24 points under the top, so Next looks below that for the one after it.
function nextChange() {
  if (!marks) return;
  const doc = document.getElementById('doc');
  const topOf = (line) => {
    const block = blockAt(doc, line);
    return block ? block.getBoundingClientRect().top + window.scrollY : Infinity;
  };
  const line = nextChangeLine(changeLines(marks.changes), window.scrollY + 28, topOf);
  if (line) revealBlock(doc, line, { reduceMotion: reduceMotion() });
}

// DotMD's layers over the rendered page. Later tasks add the map, the reading line and the caret here.
function decorate(doc) {
  if (memory) showMemory(doc, memory);
  map.setChanges(marks ? changeLines(marks.changes) : []);
  if (!marks) return;
  applyMarks(doc, marks.changes);
  showChip(doc, { count: changeCount(marks.changes), since: marks.since }, {
    onNext: nextChange,
    onMarkRead: () => post({ type: 'markRead' }),
  });
}

document.addEventListener('keydown', (event) => {
  if (event.key !== 'n' && event.key !== 'N') return;
  if (event.metaKey || event.ctrlKey || event.altKey || !marks) return;
  if (event.target.closest?.('input, textarea, [contenteditable]')) return;
  event.preventDefault();
  nextChange();
});

function applyOptions(options = {}) {
  root.dataset.size = options.size ?? 'medium';
  root.dataset.font = options.font ?? 'serif';
  root.dataset.width = options.width ?? 'medium';
  root.dataset.paper = options.paper ?? 'auto';
}

function pageIsDark() {
  const paper = root.dataset.paper;
  if (paper === 'night') return true;
  if (paper === 'white' || paper === 'paper') return false;
  return darkQuery.matches;
}

// <picture> sources follow DotMD's page color, not the system appearance.
function applyPictureTheme(doc) {
  const dark = pageIsDark();
  for (const source of doc.querySelectorAll('picture source[media]')) {
    const media = source.dataset.media ?? source.getAttribute('media');
    source.dataset.media = media;
    if (!/prefers-color-scheme/i.test(media)) continue;
    const wantsDark = /prefers-color-scheme\s*:\s*dark/i.test(media);
    source.setAttribute('media', wantsDark === dark ? 'all' : 'not all');
  }
}

// A missing or blocked image becomes a quiet labeled box instead of a broken-image icon.
function showMissing(img) {
  const box = document.createElement('span');
  const label = img.getAttribute('alt') || 'Image not available';
  box.className = 'image-missing';
  box.setAttribute('role', 'img');
  box.setAttribute('aria-label', label);
  box.textContent = label;
  (img.closest('picture') ?? img).replaceWith(box);
}

function addCopyButtons(doc) {
  for (const figure of doc.querySelectorAll('figure.code-block')) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy';
    button.textContent = 'Copy';
    button.setAttribute('aria-label', 'Copy code');
    button.addEventListener('click', () => {
      post({ type: 'copyText', text: figure.querySelector('code').innerText });
      button.textContent = 'Copied';
      setTimeout(() => { button.textContent = 'Copy'; }, 1200);
    });
    figure.appendChild(button);
  }
}

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = src;
    script.onload = resolve;
    script.onerror = reject;
    document.head.appendChild(script);
  });
}

let diagramCount = 0;
// Drawn diagrams by source, so a reload reuses them instead of drawing them again.
let diagramCache = new Map();

async function renderDiagram(source, theme) {
  window.mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme,
    fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
  });
  const { svg } = await window.mermaid.render(`dotmd-diagram-${++diagramCount}`, source);
  return svg;
}

// Mermaid bakes colors into the SVG, so each diagram is drawn in both themes and the
// stylesheet shows the one that fits the page color, the system appearance, or print.
// Runs before the scroll position is restored, so the page above the reader keeps its height
// and a reload doesn't move the text. Diagrams that changed keep the old figure's height until drawn.
function placeDiagrams(doc, oldHeights) {
  const used = new Map();
  doc.querySelectorAll('figure.mermaid-block').forEach((figure, index) => {
    const source = figure.querySelector('pre.mermaid')?.textContent ?? '';
    const html = diagramCache.get(source);
    if (html) {
      figure.innerHTML = html;
      figure.classList.add('rendered');
      used.set(source, html);
    } else if (oldHeights[index]) {
      figure.style.minHeight = `${oldHeights[index]}px`;
    }
  });
  diagramCache = used;
}

async function renderDiagrams(doc) {
  const blocks = [...doc.querySelectorAll('figure.mermaid-block:not(.rendered)')];
  if (!blocks.length) return;
  if (!window.mermaid) await loadScript('mermaid.js');
  for (const figure of blocks) {
    const source = figure.querySelector('pre.mermaid')?.textContent ?? '';
    try {
      const light = await renderDiagram(source, 'neutral');
      const dark = await renderDiagram(source, 'dark');
      const html = `<div class="diagram-light">${light}</div><div class="diagram-dark">${dark}</div>`;
      figure.innerHTML = html;
      figure.style.minHeight = '';
      figure.classList.add('rendered');
      diagramCache.set(source, html);
    } catch (error) {
      const message = String(error?.message ?? error).split('\n')[0];
      figure.style.minHeight = '';
      figure.classList.add('failed');
      figure.innerHTML = `<div class="diagram-error"><b>This diagram didn't render</b><code>${escapeHtml(message)}</code></div>`;
      post({ type: 'diagramError', line: Number(figure.dataset.line ?? 0), message });
    }
  }
}

document.addEventListener('error', (event) => {
  if (event.target instanceof HTMLImageElement) showMissing(event.target);
}, true);

darkQuery.addEventListener('change', () => applyPictureTheme(document.getElementById('doc')));

document.addEventListener('click', (event) => {
  const link = event.target.closest('a[href]');
  if (!link) return;
  event.preventDefault();
  const href = link.getAttribute('href');
  if (href.startsWith('#')) {
    const fragment = href.slice(1);
    let id = fragment;
    try { id = decodeURIComponent(fragment); } catch { /* malformed escape: use the raw fragment */ }
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
    return;
  }
  post({ type: 'linkActivated', href });
});

window.DotMD = {
  async render({ markdown, options }) {
    applyOptions(options);
    const doc = document.getElementById('doc');
    const y = window.scrollY;
    const oldHeights = [...doc.querySelectorAll('figure.mermaid-block')].map((figure) => figure.offsetHeight);
    doc.innerHTML = renderDocument(markdown, sanitize);
    rewriteLocalImages(doc);
    applyPictureTheme(doc);
    // An image whose source was stripped (http) never fires an error, so it gets its placeholder now.
    for (const img of doc.querySelectorAll('img:not([src]):not([srcset])')) {
      if (!img.closest('picture')?.querySelector('source[srcset]')) showMissing(img);
    }
    placeDiagrams(doc, oldHeights);
    addCopyButtons(doc);
    decorate(doc);
    buildOutline(doc, document.getElementById('margin'), { reduceMotion: matchMedia('(prefers-reduced-motion: reduce)').matches });
    window.scrollTo(0, y);
    await renderDiagrams(doc);
    post({ type: 'rendered' });
  },
  applyMarks({ changes, since }) {
    marks = { changes, since };
    decorate(document.getElementById('doc'));
  },
  clearMarks(fade) {
    const doc = document.getElementById('doc');
    marks = null;
    map.setChanges([]);
    const chip = doc.querySelector('.chip');
    if (!fade) {
      removeMarks(doc);
      chip?.remove();
      return;
    }
    chip?.classList.add('mark-out');
    fadeMarks(doc, { reduceMotion: reduceMotion(), done: () => chip?.remove() });
  },
  setMemory({ line, label }) {
    memory = line ? { line, label } : null;
    showMemory(document.getElementById('doc'), memory ?? {});
  },
  setLayout(layout) {
    root.dataset.layout = layout === 'document' ? 'document' : 'files';
  },
  setReadingOptions(options) {
    applyOptions(options);
    applyPictureTheme(document.getElementById('doc'));
  },
  exportHTML() {
    const clone = document.getElementById('doc').cloneNode(true);
    removeMarks(clone);
    clone.querySelectorAll('[data-dotmd-ui], button.copy').forEach((el) => el.remove());
    return clone.innerHTML;
  },
};

post({ type: 'ready' });
