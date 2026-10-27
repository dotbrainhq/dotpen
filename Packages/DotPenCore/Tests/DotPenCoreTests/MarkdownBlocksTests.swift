import Testing
@testable import DotPenCore

/// The same document the renderer's line test uses; the expected lines are what markdown-it writes as data-line.
private let sample = """
---
status: in-review
agent: claude-code
---
# Rate limiter rollout

Move the API from a fixed per-IP limit to a token bucket per API key.
Ship it behind a flag.

## Steps

- [x] Add `TokenBucket` with Redis backing
- [x] Put it behind the `rate_limit_v2` flag
- [ ] Shadow mode: log every decision, block nothing
  continued line
- [ ] Roll out to internal keys for one day

1. First
2. Second

> [!NOTE]
> An alert.

```mermaid
flowchart LR
  A --> B
```

| a | b |
|---|---|
| 1 | 2 |

Burst $b = r$ and **bold** [link](x.md) ![cover](c.png).
"""

@Test func blockStartLinesMatchTheRenderer() {
    let blocks = MarkdownBlocks.parse(sample)
    #expect(blocks.map(\.startLine) == [5, 7, 10, 12, 13, 14, 16, 18, 19, 21, 24, 29, 33])
}

@Test func blockEndsLeaveOutTrailingBlankLines() {
    let blocks = MarkdownBlocks.parse(sample)
    #expect(blocks[5].startLine == 14 && blocks[5].endLine == 15)
    #expect(blocks[6].endLine == 16)
    #expect(blocks[8].endLine == 19)
}

@Test func wordsAreTheTextThePageShows() {
    let blocks = MarkdownBlocks.parse(sample)
    #expect(blocks[3].words == ["Add", "TokenBucket", "with", "Redis", "backing"])
    #expect(blocks[1].words == ["Move", "the", "API", "from", "a", "fixed", "per-IP", "limit", "to", "a", "token", "bucket", "per", "API", "key.", "Ship", "it", "behind", "a", "flag."])
    #expect(blocks[12].words == ["Burst", "$b", "=", "r$", "and", "bold", "link", "."])
}

@Test func keysIgnoreWhitespace() {
    let a = MarkdownBlocks.parse("Some   text\nhere.")
    let b = MarkdownBlocks.parse("Some text here.")
    #expect(a[0].key == b[0].key)
}

@Test func windowsLineEndingsKeepTheSameLines() {
    let blocks = MarkdownBlocks.parse("# A\r\n\r\nText\r\n")
    #expect(blocks.map(\.startLine) == [1, 3])
}

@Test func frontMatterBecomesBlankLines() {
    #expect(MarkdownBlocks.blankingFrontMatter("---\na: 1\n---\n# T\n") == "\n\n\n# T\n")
    #expect(MarkdownBlocks.blankingFrontMatter("# No front matter\n") == "# No front matter\n")
}
