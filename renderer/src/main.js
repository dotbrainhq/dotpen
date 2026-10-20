import { renderDocument, escapeHtml } from './document.js';

const root = document.documentElement;
const post = (message) => window.webkit?.messageHandlers?.dotmd?.postMessage(message);

function applyOptions(options = {}) {
  root.dataset.size = options.size ?? 'medium';
  root.dataset.font = options.font ?? 'serif';
  root.dataset.width = options.width ?? 'medium';
  root.dataset.paper = options.paper ?? 'auto';
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
async function renderDiagrams(doc) {
  const blocks = [...doc.querySelectorAll('figure.mermaid-block')];
  if (!blocks.length) return;
  if (!window.mermaid) await loadScript('mermaid.js');
  for (const figure of blocks) {
    const source = figure.querySelector('pre.mermaid')?.textContent ?? '';
    try {
      const light = await renderDiagram(source, 'neutral');
      const dark = await renderDiagram(source, 'dark');
      figure.innerHTML = `<div class="diagram-light">${light}</div><div class="diagram-dark">${dark}</div>`;
      figure.classList.add('rendered');
    } catch (error) {
      const message = String(error?.message ?? error).split('\n')[0];
      figure.classList.add('failed');
      figure.innerHTML = `<div class="diagram-error"><b>This diagram didn't render</b><code>${escapeHtml(message)}</code></div>`;
      post({ type: 'diagramError', line: Number(figure.dataset.line ?? 0), message });
    }
  }
}

document.addEventListener('click', (event) => {
  const link = event.target.closest('a[href]');
  if (!link) return;
  event.preventDefault();
  const href = link.getAttribute('href');
  if (href.startsWith('#')) {
    document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView({ behavior: 'smooth' });
    return;
  }
  post({ type: 'linkActivated', href });
});

window.DotMD = {
  async render({ markdown, options }) {
    applyOptions(options);
    const doc = document.getElementById('doc');
    const y = window.scrollY;
    doc.innerHTML = renderDocument(markdown);
    addCopyButtons(doc);
    window.scrollTo(0, y);
    await renderDiagrams(doc);
    post({ type: 'rendered' });
  },
  setReadingOptions(options) {
    applyOptions(options);
  },
  exportHTML() {
    const clone = document.getElementById('doc').cloneNode(true);
    clone.querySelectorAll('button.copy').forEach((b) => b.remove());
    return clone.innerHTML;
  },
};

post({ type: 'ready' });
