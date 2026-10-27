import createDOMPurify from 'dompurify';

// GitHub's rules for raw HTML: keep structure and media, drop anything that runs code, submits data, or restyles the page.
const FORBID_TAGS = ['style', 'form', 'button', 'textarea', 'select', 'option', 'iframe', 'frame', 'frameset',
  'object', 'embed', 'audio', 'video', 'track', 'canvas', 'dialog', 'template', 'slot', 'link', 'meta', 'base'];

// Browsers drop tabs, newlines and other control characters inside a URL, so check the value the way they read it.
function allowedImageURL(value) {
  const normalized = value.replace(/[\u0000-\u0020]/g, '');
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(normalized);
  return !scheme || ['https', 'data'].includes(scheme[1].toLowerCase());
}

/** Returns sanitize(html) bound to a window, so the browser and the Node tests share one rule set. */
export function createSanitizer(window) {
  const purify = createDOMPurify(window);

  purify.addHook('uponSanitizeElement', (node, data) => {
    // Only task checkboxes may be inputs.
    if (data.tagName === 'input' && node.getAttribute('type') !== 'checkbox') node.remove();
  });

  purify.addHook('uponSanitizeAttribute', (node, data) => {
    // Images load over https (or inline data, or a relative path) only.
    if (data.attrName === 'src' || data.attrName === 'poster') {
      if (!allowedImageURL(data.attrValue)) data.keepAttr = false;
    }
    if (data.attrName === 'srcset') {
      const candidates = data.attrValue.split(',').map((c) => c.trim()).filter(Boolean);
      if (!candidates.every((c) => allowedImageURL(c.split(/\s+/)[0]))) data.keepAttr = false;
    }
  });

  purify.addHook('afterSanitizeAttributes', (node) => {
    if (node.nodeName === 'INPUT') node.setAttribute('disabled', '');
  });

  return (html) => purify.sanitize(html, {
    USE_PROFILES: { html: true, mathMl: true },
    FORBID_TAGS,
    ADD_TAGS: ['eq', 'eqn'],
    ADD_ATTR: ['align'],
    // Style attributes could restyle dotPen, and GitHub drops background images too.
    FORBID_ATTR: ['style', 'background'],
  });
}
