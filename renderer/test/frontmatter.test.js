import { test } from 'node:test';
import assert from 'node:assert/strict';
import { statusLineHTML, splitFrontMatter } from '../src/frontmatter.js';

const now = new Date('2026-10-20T16:00:00');

test('status, agent and updated time become the status line', () => {
  const { fields } = splitFrontMatter('---\nstatus: in-review\nagent: claude-code\nupdated: 2026-10-20T14:14:00\n---\n# Plan\n');
  assert.equal(
    statusLineHTML(fields, now),
    '<div class="meta"><span class="st st-review"><i></i>In review</span>'
      + '<span class="who"><span class="agent agent-claude">CC</span>Claude Code</span>'
      + '<span>Updated 2:14 PM</span></div>\n',
  );
});

test('an update on another day shows the date', () => {
  assert.match(statusLineHTML([['updated', '2026-10-18']], now), /<span>Updated Oct 18<\/span>/);
});

test('other fields follow as quiet pairs', () => {
  assert.equal(
    statusLineHTML([['owner', 'Shameem']], now),
    '<div class="meta"><span class="field">owner <b>Shameem</b></span></div>\n',
  );
});

test('unknown agents get initials and no color', () => {
  assert.match(statusLineHTML([['agent', 'gemini']], now), /<span class="agent">GE<\/span>Gemini/);
});

test('values are escaped', () => {
  assert.match(statusLineHTML([['status', '<b>x</b>']], now), /&lt;b&gt;x&lt;\/b&gt;/);
});

test('no fields, no line', () => {
  assert.equal(statusLineHTML([], now), '');
});
