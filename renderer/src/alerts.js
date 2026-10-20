const LABELS = { NOTE: 'Note', TIP: 'Tip', IMPORTANT: 'Important', WARNING: 'Warning', CAUTION: 'Caution' };

// GitHub alerts: a blockquote whose first line is [!NOTE], [!TIP], [!IMPORTANT], [!WARNING] or [!CAUTION].
export function alerts(md) {
  md.core.ruler.after('block', 'dotmd_alerts', (state) => {
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'blockquote_open') continue;
      const inline = tokens[i + 2];
      if (!inline || inline.type !== 'inline') continue;
      const match = inline.content.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:\n|$)/);
      if (!match) continue;
      inline.content = inline.content.slice(match[0].length);
      tokens[i].attrJoin('class', `alert alert-${match[1].toLowerCase()}`);
      tokens[i].attrSet('data-alert', LABELS[match[1]]);
    }
  });
}
