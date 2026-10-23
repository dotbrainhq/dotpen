# Changelog

Every release of DotMD is listed here. Versions follow semantic versioning.

## Unreleased

### Added

- App shell that opens Markdown files in a document window, with the Trail app icon and the DotMD green accent.
- App Sandbox from the start, so the same app can ship on the Mac App Store and as a direct download.
- Aa reading options for text size, font, line width and page color. The window follows the page color.
- Export as PDF (⌘E) and as a self-contained HTML file (⇧⌘E) from the File menu or the share menu. PDF pages are always white, and diagrams switch to match the page.
- Quick Look preview for Markdown files in Finder, drawn by the same renderer as the app.
- Opening several files puts them in tabs in one window, whatever the system tab setting is.
- Files window that watches the folders where agents write and lists every Markdown file in them, grouped by folder, with kind icons, the git branch, and unread and changed marks. A pencil moves while an agent is writing a file.
- Filter, unread and changed toggles, sort by last changed or name, and pinned files in the file list. node_modules, build folders and .gitignore paths stay hidden until you show them.
- First launch finds the projects in your code folder by their CLAUDE.md, AGENTS.md or .cursor files and offers to watch them.
- Raw HTML in Markdown renders the way GitHub does. Images linked by relative path load from the document's folder, and relative Markdown links open in DotMD.
- Settings with a Folders pane to add, remove and reconnect watched folders.
- The reader page follows DotMD's design: a status line from front matter, the outline in the right margin, and task boxes.
- Changes since you last read a file: changed words struck and rewritten in green, a bar beside added blocks, and a tag where lines were removed. A chip counts them, Next (or N) walks through them, and Mark read clears them.
- A change map on the scrollbar and a dotted line where you stopped reading.
- Live writing: blocks an agent writes into an open file glow as they arrive.
- Comments: select text and press C to comment in the margin. Each comment underlines its passage, follows it when lines move, and shows as a dot on the change map.
- A comments panel with open and resolved comments, and Copy as prompt for any selection.
- Send to agent turns your comments into a prompt with the exact lines they point at, copies it, and marks them sent.
- The agent bridge: a local MCP server your agents use to read your comments and resolve them. Settings > Integrations has setup for Claude Code, Codex, Gemini CLI, Grok CLI and Cursor.
- DotMD names the agent that wrote a file, from Claude Code and Codex session logs you allow in Settings > Integrations.
- While an agent writes the open file, a pill follows along; when it stops, Review Changes takes you to what changed.
- A banner when an agent writes a new file, and "Connected to Claude Code in api-gateway" in the Send sheet.
- A menu bar item with what's being written, new and changed files, and Pause watching for 1 hour.
- Open anything with ⌘K: recent files, headings in the open file, and commands.
- A keyboard shortcuts overlay on ? or ⌘/, with Shift-N for the previous change, ⇧⌘M to mark read, ⇧⌘C to copy as prompt, and ⌘+ and ⌘− for text size.
- Watched files in Spotlight by title, headings and text.
- Shortcuts actions: Open File, Get Changes Since Last Read, List Open Tasks and Send Comments to Agent.
- Open in DotMD in Finder's Services menu, and a `dotmd` command that opens files and watches folders.
- A file that's moved or deleted while open stays on screen, faded, with Find It to locate it again.
- Large files open at their first 2,000 lines, with Show All for the rest.
- A diagram that doesn't render says which line Mermaid stopped at and shows its source.
- Screens for a folder DotMD can no longer open and for folders with no Markdown yet.
