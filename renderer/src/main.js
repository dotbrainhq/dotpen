import { renderDocument } from './document.js';
import { createSanitizer } from './sanitize.js';
import { rewriteLocalImages } from './assets.js';
import { buildOutline } from './outline.js';
import { applyMarks, fadeMarks, removeMarks, blockAt } from './marks.js';
import { showChip, nextChangeLine, previousChangeLine, revealBlock } from './chip.js';
import { createMap } from './map.js';
import { showMemory, topLine } from './memory.js';
import { markLive as glow, setWriting as showCaret } from './live.js';
import { selectionInfo, showSelectionBar, hideSelectionBar } from './selection.js';
import { renderComments, clearComments, openComposer, layoutCards } from './comments.js';
import { showNotice, diagramErrorHTML, diagramErrorMessage } from './notice.js';
import { prepareTasks, taskLine } from './tasks.js';
import { sourceHTML, sourceTopLine, blockForLine } from './source.js';
import { copyHTML } from './copy.js';
import { changeLines, changeAt, showChangeBar, hideChangeBar } from './review.js';

const root = document.documentElement;
const post = (message) => window.webkit?.messageHandlers?.dotpen?.postMessage(message);
const sanitize = createSanitizer(window);
const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
const reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
// The last marks Swift sent. Every render puts them back, so a reload keeps them.
let marks = null;
const map = createMap(document);
// The line where reading stopped last time, put back after every render.
let memory = null;
// Whether the file is being written, and its last written block, put back after every render.
let writing = { writing: false, lastLine: null };
// The file's comments and who writes them, put back after every render. Null outside the watched folders.
let comments = null;
let lastSentLine = null;
// Task boxes tick in the app; Quick Look never turns this on.
let tasksEditable = false;
// Show Source: the file as written instead of the page.
let showingSource = false;
// The last render, so Show Source and back can draw again without Swift.
let lastRender = null;
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

// A revealed block sits 24 points under the top, so Next looks below that for the one after it.
function nextChange(backwards = false) {
  if (!marks) return;
  const doc = document.getElementById('doc');
  const topOf = (line) => {
    const block = blockAt(doc, line);
    return block ? block.getBoundingClientRect().top + window.scrollY : Infinity;
  };
  const line = (backwards ? previousChangeLine : nextChangeLine)(changeLines(marks.changes), window.scrollY + 28, topOf);
  if (line) {
    revealBlock(doc, line, { reduceMotion: reduceMotion() });
    setCurrent(line);
  }
}

// The change being reviewed: the one Next landed on or the one clicked. The review bar acts on it.
let current = null;
// After an Accept, the line to move on from once Swift sends the new marks.
let advanceFrom = null;

function setCurrent(line) {
  current = marks ? changeAt(marks.changes, line) : null;
  if (!current) {
    hideChangeBar(document);
    return;
  }
  showChangeBar(document, current, {
    canSendBack: canComment(),
    onAccept: acceptCurrent,
    onSendBack: sendBackCurrent,
    onNext: () => nextChange(),
  });
}

function clearCurrent() {
  current = null;
  hideChangeBar(document);
}

// Takes the change into what dotPen counts as read. The file stays as the agent wrote it.
function acceptCurrent() {
  if (!current) return;
  advanceFrom = Math.max(current.at, 1);
  post({ type: 'acceptChange', kind: current.kind, line: current.at });
  clearCurrent();
}

// Sends the change back: the composer opens on the block, quoting its text as it reads now.
function sendBackCurrent() {
  if (!current || current.kind === 'removed') return;
  const block = blockAt(document.getElementById('doc'), current.at);
  if (!block) return;
  const copy = block.cloneNode(true);
  copy.querySelectorAll('.del, .del-gap, .gut, [data-dotpen-ui]').forEach((el) => el.remove());
  const text = copy.textContent.replace(/\s+/g, ' ').trim();
  const range = document.createRange();
  range.selectNodeContents(block);
  clearCurrent();
  compose({ info: { line: Number(block.dataset.line), text }, range });
}

// dotPen's layers over the rendered page. Later tasks add the map, the reading line and the caret here.
function decorate(doc) {
  if (memory) showMemory(doc, memory);
  showCaret(doc, writing.writing, writing.lastLine);
  map.setChanges(marks ? changeLines(marks.changes) : []);
  if (!marks) return;
  applyMarks(doc, marks.changes);
  showChip(doc, { count: changeCount(marks.changes), since: marks.since }, {
    onNext: nextChange,
    onMarkRead: () => post({ type: 'markRead' }),
  });
}

document.addEventListener('keydown', (event) => {
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  if (event.target.closest?.('input, textarea, [contenteditable]')) return;
  if ((event.key === 'n' || event.key === 'N') && marks) {
    event.preventDefault();
    nextChange(event.shiftKey);
  } else if ((event.key === 'c' || event.key === 'C') && selected && canComment()) {
    event.preventDefault();
    compose(selected);
  } else if (event.key === '?') {
    post({ type: 'showShortcuts' });
  } else if (event.key === 'f' || event.key === 'F') {
    // Following only means something while an agent writes the file; Swift ignores it otherwise.
    post({ type: 'toggleFollow' });
  } else if ((event.key === 'a' || event.key === 'A') && current) {
    event.preventDefault();
    acceptCurrent();
  } else if (event.key === 'Escape' && current) {
    clearCurrent();
  } else if (event.key === 'j' || event.key === 'k') {
    // Next and previous file in the list; Swift ignores them in a document window.
    post({ type: 'stepFile', by: event.key === 'j' ? 1 : -1 });
  }
});

// A click or Space on a task box. Swift writes the tick to the file, or draws the page again if it can't.
document.addEventListener('change', (event) => {
  const line = taskLine(event.target);
  if (line) post({ type: 'toggleTask', line, checked: event.target.checked });
});

// A drawn diagram as a PNG for Google Docs, from its light version at twice its size. Throws if WebKit won't let
// the canvas be read, and the caller falls back to the diagram's source.
async function diagramPNG(svg) {
  const box = svg.viewBox.baseVal;
  const width = box?.width || svg.getBoundingClientRect().width;
  const height = box?.height || svg.getBoundingClientRect().height;
  const copy = svg.cloneNode(true);
  copy.setAttribute('width', width);
  copy.setAttribute('height', height);
  const image = new Image();
  image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(new XMLSerializer().serializeToString(copy))}`;
  await image.decode();
  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(width * 2);
  canvas.height = Math.ceil(height * 2);
  const context = canvas.getContext('2d');
  context.fillStyle = '#ffffff';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.scale(2, 2);
  context.drawImage(image, 0, 0, width, height);
  return canvas.toDataURL('image/png');
}

// The file as written, numbered by line. The page's marks, comments and outline wait until it's shown again.
function renderSource(doc, markdown) {
  doc.innerHTML = sourceHTML(markdown);
  map.setChanges([]);
  clearComments(doc, margin());
  buildOutline(doc, margin(), { reduceMotion: reduceMotion() });
  hideSelectionBar(doc);
  selected = null;
}

const margin = () => document.getElementById('margin');

// Comments are kept for files in watched folders, and written in the margin, which a narrow window or the
// comments panel hides.
function canComment() {
  return Boolean(comments?.canComment) && root.dataset.panel !== 'on' && getComputedStyle(margin()).display !== 'none';
}

function showComments(doc) {
  if (!comments) {
    clearComments(doc, margin());
    map.setComments([]);
    return;
  }
  renderComments(doc, margin(), comments.items, comments.author, {
    onEdit: (comment) => openComposer(doc, margin(), comment, comments.author, {
      onSubmit: saveComment,
      onCancel: () => composing(false),
    }),
    onResolve: (comment) => post({ type: 'resolveComment', id: comment.id }),
  });
  map.setComments(comments.items.map((comment) => comment.line));
}

function saveComment({ line, quote, body, id }) {
  CSS.highlights?.delete('compose');
  composing(false);
  post({ type: 'saveComment', line, quote, body, id });
}

// While a composer has focus, ⌘↩ saves the comment. Swift turns off the toolbar's ⌘↩ (Send to agent) meanwhile.
let isComposing = false;
function composing(active) {
  if (active === isComposing) return;
  isComposing = active;
  post({ type: 'composing', active });
}
document.addEventListener('focusin', (event) => composing(Boolean(event.target.closest?.('.cmt.compose'))));
document.addEventListener('focusout', (event) => {
  if (!event.relatedTarget?.closest?.('.cmt.compose')) composing(false);
});

// The selection under the bar, with its range, so Comment can still find it once the composer takes focus.
let selected = null;

function compose({ info, range }) {
  const doc = document.getElementById('doc');
  hideSelectionBar(doc);
  selected = null;
  // The passage keeps its selection color while the composer has focus, as in the prototype.
  if (window.Highlight) CSS.highlights.set('compose', new Highlight(range));
  openComposer(doc, margin(), { line: info.line, quote: info.text }, comments.author, {
    onSubmit: saveComment,
    onCancel: () => {
      CSS.highlights?.delete('compose');
      composing(false);
    },
  });
}

function updateSelectionBar() {
  const doc = document.getElementById('doc');
  const selection = window.getSelection();
  const info = selectionInfo(doc, selection);
  if (!info) {
    selected = null;
    hideSelectionBar(doc);
    return;
  }
  const range = selection.getRangeAt(0).cloneRange();
  selected = { info, range };
  const done = () => {
    selected = null;
    hideSelectionBar(doc);
  };
  showSelectionBar(doc, range.getClientRects()[0] ?? range.getBoundingClientRect(), {
    canComment: canComment(),
    onComment: () => compose({ info, range }),
    onCopy: () => {
      post({ type: 'copyText', text: info.text });
      done();
    },
    onPrompt: () => {
      post({ type: 'copyPrompt', line: info.line, quote: info.text });
      done();
    },
  });
}

document.addEventListener('mouseup', (event) => {
  if (event.target.closest?.('[data-dotpen-ui]')) return;
  // The selection settles after mouseup.
  setTimeout(updateSelectionBar, 0);
});
document.addEventListener('keyup', (event) => {
  if (event.shiftKey) updateSelectionBar();
});
document.addEventListener('selectionchange', () => {
  if (window.getSelection().isCollapsed && selected) {
    selected = null;
    hideSelectionBar(document.getElementById('doc'));
  }
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

// <picture> sources follow dotPen's page color, not the system appearance.
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
    // dotPen shows its own card in the figure; Mermaid's error graphic would land at the end of the page.
    suppressErrorRendering: true,
    theme,
    fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
  });
  const { svg } = await window.mermaid.render(`dotpen-diagram-${++diagramCount}`, source);
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
      figure.dataset.source = source;
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
      figure.dataset.source = source;
      figure.style.minHeight = '';
      figure.classList.add('rendered');
      diagramCache.set(source, html);
    } catch (error) {
      const message = diagramErrorMessage(error, source);
      figure.style.minHeight = '';
      figure.classList.add('failed');
      figure.dataset.source = source;
      figure.innerHTML = diagramErrorHTML(message, source);
      post({ type: 'diagramError', line: Number(figure.dataset.line ?? 0), message });
    }
  }
}

document.addEventListener('error', (event) => {
  if (event.target instanceof HTMLImageElement) showMissing(event.target);
}, true);

darkQuery.addEventListener('change', () => applyPictureTheme(document.getElementById('doc')));

document.addEventListener('click', (event) => {
  // A click on a marked block makes it the change under review.
  if (marks && !event.target.closest('a, button, [data-dotpen-ui]:not(.gut)')) {
    const block = event.target.closest('#doc [data-line]');
    if (block && changeAt(marks.changes, Number(block.dataset.line))) setCurrent(Number(block.dataset.line));
  }
  // Show Source on a diagram that didn't render.
  const toggle = event.target.closest('.dg-err .nb');
  if (toggle) {
    const source = toggle.closest('.dg-err').querySelector('.dg-src');
    source.hidden = !source.hidden;
    toggle.textContent = source.hidden ? 'Show Source' : 'Hide Source';
    return;
  }
  const link = event.target.closest('a[href]');
  if (!link) return;
  event.preventDefault();
  const href = link.getAttribute('href');
  if (href.startsWith('#')) {
    const fragment = href.slice(1);
    let id = fragment;
    try { id = decodeURIComponent(fragment); } catch { /* malformed escape: use the raw fragment */ }
    document.getElementById(id)?.scrollIntoView({ behavior: reduceMotion() ? 'auto' : 'smooth' });
    return;
  }
  post({ type: 'linkActivated', href });
});

window.dotPen = {
  async render({ markdown, options }) {
    lastRender = { markdown, options };
    applyOptions(options);
    const doc = document.getElementById('doc');
    const y = window.scrollY;
    root.dataset.view = showingSource ? 'source' : 'page';
    if (showingSource) {
      renderSource(doc, markdown);
      window.scrollTo(0, y);
      post({ type: 'rendered' });
      return;
    }
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
    prepareTasks(doc, tasksEditable);
    decorate(doc);
    buildOutline(doc, margin(), { reduceMotion: matchMedia('(prefers-reduced-motion: reduce)').matches });
    CSS.highlights?.delete('compose');
    selected = null;
    hideSelectionBar(doc);
    showComments(doc);
    window.scrollTo(0, y);
    await renderDiagrams(doc);
    post({ type: 'rendered' });
  },
  applyMarks({ changes, since }) {
    marks = { changes, since };
    const doc = document.getElementById('doc');
    decorate(doc);
    if (advanceFrom !== null) {
      const lines = changeLines(changes);
      const next = lines.find((line) => line >= advanceFrom) ?? lines[0];
      advanceFrom = null;
      if (next) {
        revealBlock(doc, next, { reduceMotion: reduceMotion() });
        setCurrent(next);
      }
    } else if (current) {
      setCurrent(Math.max(current.at, 1));
    }
  },
  clearMarks(fade) {
    const doc = document.getElementById('doc');
    marks = null;
    advanceFrom = null;
    clearCurrent();
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
  markLive(lines) {
    glow(document.getElementById('doc'), lines);
  },
  setWriting({ writing: isWriting, lastLine }) {
    writing = { writing: isWriting, lastLine: lastLine ?? null };
    showCaret(document.getElementById('doc'), writing.writing, writing.lastLine);
  },
  setComments(payload) {
    comments = payload;
    showComments(document.getElementById('doc'));
  },
  // A comment chosen in the panel: its passage comes into view and flashes, as Next does for a change.
  reveal(line) {
    revealBlock(document.getElementById('doc'), line, { reduceMotion: reduceMotion() });
  },
  // Following an agent: the block it just wrote stays in view, without the flash Next uses.
  follow(line) {
    const block = blockAt(document.getElementById('doc'), line);
    block?.scrollIntoView({ block: 'center', behavior: reduceMotion() ? 'auto' : 'smooth' });
  },
  nextChange() {
    nextChange();
  },
  // A file that went away dims its last version under the notice; a large file shows in part under one.
  setNotice(notice) {
    root.dataset.edge = notice?.dim ? 'deleted' : '';
    showNotice(document, notice, (id) => post({ type: 'noticeAction', id }));
  },
  setTasksEditable(editable) {
    tasksEditable = editable;
    if (!showingSource) prepareTasks(document.getElementById('doc'), editable);
  },
  // Show Source and back keep the line at the top of the view.
  async setSource(on) {
    if (on === showingSource || !lastRender) return;
    const doc = document.getElementById('doc');
    const line = showingSource ? sourceTopLine(doc) : topLine(doc);
    showingSource = on;
    await this.render(lastRender);
    const block = line && (on ? doc.querySelector(`.sl[data-line="${line}"]`) : blockForLine(doc, line));
    if (block) window.scrollTo(0, block.getBoundingClientRect().top + window.scrollY - 24);
  },
  setPanel(open) {
    root.dataset.panel = open ? 'on' : 'off';
    layoutCards(document.getElementById('doc'), margin());
  },
  setLayout(layout) {
    root.dataset.layout = layout === 'document' ? 'document' : 'files';
  },
  setReadingOptions(options) {
    applyOptions(options);
    applyPictureTheme(document.getElementById('doc'));
  },
  // Copy for Slack or Google Docs: the page as paste-ready HTML.
  async copyFor(target) {
    const doc = document.getElementById('doc');
    const diagramImages = new Map();
    if (target === 'docs') {
      for (const figure of doc.querySelectorAll('figure.mermaid-block.rendered')) {
        const svg = figure.querySelector('.diagram-light svg');
        if (!svg) continue;
        try {
          diagramImages.set(figure, await diagramPNG(svg));
        } catch {
          // The diagram pastes as its source instead.
        }
      }
    }
    return copyHTML(doc, target, { diagramImages });
  },
  exportHTML() {
    const clone = document.getElementById('doc').cloneNode(true);
    removeMarks(clone);
    clone.querySelectorAll('[data-dotpen-ui], button.copy').forEach((el) => el.remove());
    clone.querySelectorAll('.anch').forEach((el) => el.replaceWith(...el.childNodes));
    prepareTasks(clone, false);
    return clone.innerHTML;
  },
};

// Cards follow their passages as images load, diagrams draw and the window resizes.
new ResizeObserver(() => layoutCards(document.getElementById('doc'), margin())).observe(document.getElementById('doc'));

post({ type: 'ready' });
