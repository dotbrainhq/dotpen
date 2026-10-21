import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tickPositions, viewportBox } from '../src/map.js';

test('ticks sit at each change\'s share of the page', () => {
  const tops = { 3: 160, 9: 260, 20: 660 };
  assert.deepEqual(tickPositions([3, 9, 20], (l) => tops[l], 1000), [0.16, 0.26, 0.66]);
});

test('changes without a block on the page get no tick', () => {
  assert.deepEqual(tickPositions([3, 4], (l) => (l === 3 ? 100 : null), 1000), [0.1]);
});

test('the view box follows the scroll', () => {
  assert.deepEqual(viewportBox(500, 460, 1000), { top: 0.5, height: 0.46 });
  assert.deepEqual(viewportBox(0, 1200, 1000), { top: 0, height: 1 });
});
