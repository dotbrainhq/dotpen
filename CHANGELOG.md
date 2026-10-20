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
