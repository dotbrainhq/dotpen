import { blockAt } from './marks.js';

/** Where each change sits along the page, as fractions of its height, for the map's ticks. */
export function tickPositions(lines, topOf, pageHeight) {
  if (pageHeight <= 0) return [];
  return [...new Set(lines)]
    .map((line) => topOf(line))
    .filter((top) => top != null)
    .map((top) => Math.min(1, Math.max(0, top / pageHeight)));
}

/** The view's place on the page, as fractions: where it starts and how much of the page it shows. */
export function viewportBox(scrollY, viewHeight, pageHeight) {
  if (pageHeight <= viewHeight) return { top: 0, height: 1 };
  return { top: scrollY / pageHeight, height: viewHeight / pageHeight };
}

/**
 * The prototype's change map: a thin track on the right in place of the scrollbar, with the view's box, a
 * green tick at each change and a ringed dot at each comment. Clicking the track jumps there; dragging the box scrolls.
 */
export function createMap(document) {
  const win = document.defaultView;
  const map = document.createElement('div');
  map.className = 'map';
  map.setAttribute('aria-hidden', 'true');
  const box = document.createElement('div');
  box.className = 'vp';
  map.appendChild(box);
  document.body.appendChild(map);
  let lines = [];
  let commentLines = [];

  const pageHeight = () => document.documentElement.scrollHeight;
  const topOf = (line) => {
    const block = blockAt(document.getElementById('doc'), line);
    return block ? block.getBoundingClientRect().top + win.scrollY : null;
  };

  function layout() {
    const viewHeight = win.innerHeight;
    map.hidden = pageHeight() <= viewHeight + 1;
    const view = viewportBox(win.scrollY, viewHeight, pageHeight());
    box.style.top = `${view.top * 100}%`;
    box.style.height = `${view.height * 100}%`;
    map.querySelectorAll('i').forEach((tick) => tick.remove());
    const place = (positions, className) => {
      for (const position of positions) {
        const tick = document.createElement('i');
        if (className) tick.className = className;
        tick.style.top = `${position * 100}%`;
        map.appendChild(tick);
      }
    };
    place(tickPositions(lines, topOf, pageHeight()), '');
    place(tickPositions(commentLines, topOf, pageHeight()), 'c');
  }

  let queued = false;
  const schedule = () => {
    if (queued) return;
    queued = true;
    win.requestAnimationFrame(() => {
      queued = false;
      layout();
    });
  };
  win.addEventListener('scroll', schedule, { passive: true });
  win.addEventListener('resize', schedule);
  new win.ResizeObserver(schedule).observe(document.getElementById('doc'));

  const scrollToFraction = (fraction) => win.scrollTo(0, fraction * pageHeight() - win.innerHeight / 2);
  map.addEventListener('pointerdown', (event) => {
    const rect = map.getBoundingClientRect();
    const at = (y) => (y - rect.top) / rect.height;
    scrollToFraction(at(event.clientY));
    map.setPointerCapture(event.pointerId);
    const move = (e) => scrollToFraction(at(e.clientY));
    const up = () => {
      map.removeEventListener('pointermove', move);
      map.removeEventListener('pointerup', up);
    };
    map.addEventListener('pointermove', move);
    map.addEventListener('pointerup', up);
  });

  return {
    setChanges(changeLines) {
      lines = changeLines;
      schedule();
    },
    setComments(lines) {
      commentLines = lines;
      schedule();
    },
    refresh: schedule,
  };
}
