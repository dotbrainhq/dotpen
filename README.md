<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/cover-dark.png">
  <img src=".github/assets/cover-light.png" alt="DotMD: read what your agents write. A free, open-source Mac app. Next to the tagline, a Markdown plan written by Claude Code, rendered by DotMD with its status, heading, a formula, ticked and open tasks, and a Swift code block.">
</picture>

# DotMD

DotMD is Preview for Markdown, with a review desk for what AI agents write. Open any `.md` file and read it rendered, the way it was meant to look. Point it at the folders where Claude Code, Codex, or Cursor work, and it shows what's new, marks what changed since you last read a file, and sends your comments back to the agent.

DotMD is a free, open-source, native Mac app. It's in early development, and there's no release yet.

## What it does

- **Reads Markdown well:** GitHub Flavored Markdown, code with highlighting, Mermaid diagrams, math, front matter, alerts, and task lists, in New York, SF Pro, or SF Mono.
- **Shows what agents wrote:** a list of your watched folders with unread files marked, and a live indicator while an agent is writing.
- **Marks changes:** what changed since you last read a file, marked in the page like an editor marks a proof. No git needed.
- **Sends comments back:** select text, comment, and send your notes to the agent as a prompt.
- **Fits the Mac:** Quick Look previews in Finder, PDF and HTML export, keyboard shortcuts, and light and dark mode.

## Connect an agent

Turn on the agent bridge in Settings > Integrations. Each agent has a row there with a Copy button: run the copied command once in Terminal, or for Cursor, add the copied entry to `~/.cursor/mcp.json`.

| Agent | Command |
|---|---|
| Claude Code | `claude mcp add --transport http --scope user dotmd http://127.0.0.1:47319/mcp` |
| Codex | `codex mcp add dotmd --url http://127.0.0.1:47319/mcp` |
| Gemini CLI | `gemini mcp add --scope user --transport http dotmd http://127.0.0.1:47319/mcp` |
| Grok CLI | `grok mcp add --transport http dotmd http://127.0.0.1:47319/mcp` |

Your agent can then list your open comments, read the ones on a file, and resolve them when it's done. It can also ask for your review of a file and wait: DotMD marks the file and shows the request on the page, and when you press Done Reviewing, the agent gets your comments. Any other agent that speaks MCP over HTTP connects to `http://127.0.0.1:47319/mcp`. The bridge listens on your Mac only.

## Command line

`dotmd` opens a Markdown file in DotMD, or watches a folder:

```
dotmd plan.md
dotmd ~/code/api
```

Install it from Settings > Integrations > Command line, which copies a one-line install command, or from a clone of this repo:

```
sudo install -m 755 cli/dotmd /usr/local/bin/dotmd
```

## Build from source

You need macOS 15 or later, Xcode 27, XcodeGen, and Node 22.

```
brew install xcodegen
git clone https://github.com/dotbrainhq/dotmd.git
cd dotmd
xcodegen generate
xcodebuild -project DotMD.xcodeproj -scheme DotMD -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/DotMD.app
```

The renderer that draws documents is a small Node project in `renderer/`. Its built output is checked in, so you only need Node when you change it:

```
cd renderer
npm install
npm test
npm run build
```

## Project layout

| Path | What it is |
|---|---|
| `App/` | The SwiftUI app: windows, toolbar, settings. |
| `Packages/DotMDCore/` | Logic with no UI, like watching files. |
| `Packages/DotMDRender/` | The document view, the bridge to the renderer, and export. |
| `Packages/DotMDBridge/` | The agent bridge: a local MCP server that hands your comments to agents. |
| `QuickLook/` | The Finder Quick Look extension. |
| `cli/` | The `dotmd` command. |
| `renderer/` | The Markdown renderer that runs inside the document view. |
| `fixtures/` | Sample documents for checking the renderer by hand. |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security issue, see [SECURITY.md](SECURITY.md).

## License

The code is released under the [MIT License](LICENSE). The DotMD name and the DotMD icon are not covered by the license, so please use your own name and icon if you ship a copy.
