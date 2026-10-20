import createDOMPurify from 'dompurify';

// GitHub's rules for raw HTML: keep structure and media, drop anything that runs code, submits data, or restyles the page.
const FORBID_TAGS = ['style', 'form', 'button', 'textarea', 'select', 'option', 'iframe', 'frame', 'frameset',
  'object', 'embed', 'audio', 'video', 'track', 'canvas', 'dialog', 'template', 'slot', 'link', 'meta', 'base'];

/** Returns sanitize(html) bound to a window, so the browser and the Node tests share one rule set. */
export function createSanitizer(window) {
  const purify = createDOMPurify(window);

  purify.addHook('uponSanitizeElement', (node, data) => {
    // Only task checkboxes may be inputs.
    if (data.tagName === 'input' && node.getAttribute('type') !== 'checkbox') node.remove();
  });

  purify.addHook('uponSanitizeAttribute', (node, data) => {
    // KaTeX places glyphs with inline styles. Anywhere else a style attribute could restyle DotMD.
    if (data.attrName === 'style' && !node.closest('.katex, .katex-display')) data.keepAttr = false;
    // Images load over https only.
    if (data.attrName === 'src' && /^\s*http:/i.test(data.attrValue)) data.keepAttr = false;
    if (data.attrName === 'srcset' && /(^|,)\s*http:/i.test(data.attrValue)) data.keepAttr = false;
  });

  purify.addHook('afterSanitizeAttributes', (node) => {
    if (node.nodeName === 'INPUT') node.setAttribute('disabled', '');
  });

  return (html) => purify.sanitize(html, {
    USE_PROFILES: { html: true, mathMl: true },
    FORBID_TAGS,
    ADD_TAGS: ['eq', 'eqn'],
    ADD_ATTR: ['align'],
  });
}
