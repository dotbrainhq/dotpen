import { escapeHtml } from './escape.js';

// Replaces front matter with the same number of blank lines, so line numbers below it stay true.
export function splitFrontMatter(src) {
  const match = src.match(/^---\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/);
  if (!match) return { body: src, fields: [] };
  const lineCount = match[0].split('\n').length - (match[0].endsWith('\n') ? 1 : 0);
  const fields = match[1]
    .split(/\r?\n/)
    .map((line) => line.match(/^([A-Za-z0-9_-]+):[ \t]*(.*)$/))
    .filter(Boolean)
    .map(([, key, value]) => [key, value.replace(/^["']|["']$/g, '')]);
  return { body: '\n'.repeat(lineCount) + src.slice(match[0].length), fields };
}

// Known agents: initials, the name to show, and the color class from the prototype.
const AGENTS = {
  'claude-code': ['CC', 'Claude Code', 'claude'],
  claude: ['CC', 'Claude Code', 'claude'],
  codex: ['CX', 'Codex', 'codex'],
  cursor: ['CU', 'Cursor', 'cursor'],
};

const REVIEW = /review|waiting|pending/i;

function humanize(value) {
  const words = value.replace(/[-_]+/g, ' ').trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

// "2:14 PM" for today, "Oct 18" otherwise. Values that aren't dates show as written.
function updatedLabel(value, now) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  const sameDay = date.toDateString() === now.toDateString();
  return sameDay
    ? date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
    : date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

/** The prototype's `.meta` line: status with its dot, the agent, when it was updated, then any other fields. */
export function statusLineHTML(fields, now = new Date()) {
  if (!fields.length) return '';
  const parts = [];
  for (const [key, value] of fields) {
    const name = key.toLowerCase();
    if (name === 'status') {
      const tone = REVIEW.test(value) ? ' st-review' : '';
      parts.push(`<span class="st${tone}"><i></i>${escapeHtml(humanize(value))}</span>`);
    } else if (name === 'agent') {
      const known = AGENTS[value.toLowerCase()];
      const [initials, label, color] = known ?? [value.slice(0, 2).toUpperCase(), humanize(value), null];
      const cls = color ? `agent agent-${color}` : 'agent';
      parts.push(`<span class="who"><span class="${cls}">${escapeHtml(initials)}</span>${escapeHtml(label)}</span>`);
    } else if (name === 'updated' || name === 'date' || name === 'modified') {
      parts.push(`<span>Updated ${escapeHtml(updatedLabel(value, now))}</span>`);
    } else {
      parts.push(`<span class="field">${escapeHtml(key)} <b>${escapeHtml(value)}</b></span>`);
    }
  }
  return `<div class="meta">${parts.join('')}</div>\n`;
}
