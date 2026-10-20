// Tags blocks with their source lines so Swift can place change marks and comments by line.
export function lineNumbers(md) {
  md.core.ruler.push('dotmd_lines', (state) => {
    for (const token of state.tokens) {
      if (!token.map || token.nesting === -1) continue;
      if (token.level === 0 || token.type === 'list_item_open') {
        token.attrSet('data-line', String(token.map[0] + 1));
        token.attrSet('data-line-end', String(token.map[1]));
      }
    }
  });
}
