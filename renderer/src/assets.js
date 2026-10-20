const EXTERNAL = /^(?:[a-z][a-z0-9+.-]*:|\/\/|#)/i;

/**
 * Maps a relative image path to the dotmd-asset scheme, which the app serves from disk.
 * The whole path is one encoded segment so "../" survives URL parsing. A leading slash means
 * the watched folder's root, as it does on GitHub.
 */
export function localImageURL(src) {
  if (!src || EXTERNAL.test(src)) return null;
  let path = src.split(/[?#]/)[0];
  try {
    path = decodeURI(path);
  } catch {
    // Keep a path with a stray % as written.
  }
  const host = path.startsWith('/') ? 'root' : 'doc';
  return `dotmd-asset://${host}/${encodeURIComponent(path.replace(/^\/+/, ''))}`;
}

/** Points every relative img src and source srcset at the dotmd-asset scheme. */
export function rewriteLocalImages(doc) {
  for (const img of doc.querySelectorAll('img[src]')) {
    const url = localImageURL(img.getAttribute('src'));
    if (url) img.setAttribute('src', url);
  }
  for (const source of doc.querySelectorAll('source[srcset]')) {
    const candidates = source.getAttribute('srcset').split(',').map((part) => {
      const [src, ...descriptor] = part.trim().split(/\s+/);
      return [localImageURL(src) ?? src, ...descriptor].join(' ');
    });
    source.setAttribute('srcset', candidates.join(', '));
  }
}
