# Claude Rules
## Rule 1

always use powershell not bash unless told specifaclly otherwhise!!!

## Rule 2

when you have any task or whatever you can run as backgruond task, do it automatically without promting me to manualy :      ctrl+b to run in background

## Rule 3

Session Start: Run `. C:\Users\micha\.claude\mcp-ondemand.ps1; mcps` to view all MCP servers with their status. Use `mcp-only <servers>` to enable only the MCPs you need (disables everything else), or use `mcp-off` to disable all MCPs, then `mcp-on <servers>` to selectively enable specific ones.

## Rule 4

always read all from .claude to know all needed and purge everything not neded from there to reduce used context0  When adding/connecting new MCP servers: 1) Search npm/web for the MCP package name, 2) Install globally with `npm install -g <package-name>`, 3) Find the installed path with `npm list -g <package-name>` then locate the main .js file in node_modules, 4) Create a .cmd wrapper file in `C:\Users\micha\.claude\` with format: `@echo off` [newline] `"C:\Program Files\nodejs\node.exe" "<full-path-to-index.js>" %*`, 5) Add to Claude with `claude mcp add <name> C:\Users\micha\.claude\<name>.cmd -s user`, 6) Verify connection with `claude mcp list` â€“ if it shows â€œFailed to connectâ€ immediately remove it with `claude mcp remove <name> -s user`, 7) Only after confirming â€œConnectedâ€ status add the server definition to `C:\Users\micha\.claude\mcp-ondemand.ps1` in the `$script:MCPServers` hashtable with format: `"<name>" = @{ wrapper = "<name>.cmd"; description = "<desc>" }`, 8) Add the server name to the appropriate category in `$script:MCPCategories` hashtable, 9) Never keep failed MCPs in config â€“ always test first then add to settings only if wo- when working wth powershell always make sure to use powershell v5 and that eerythig you make fit v5 version! example: use `;` not `&&`

## Rule 5

After any error or suboptimal approach immediately document what went wrong, why, and the correct solution in `.claude/learned.md` with timestamp, then review this file before starting any new task.

## Rule 6

Work 100% autonomously without ever asking the user to do anything manually - search for information, fix problems, install dependencies, create configs, debug and resolve failures yourself, never stop until the goal is 100% achieved and verified through actual execution/testing, forbidden from ending prematurely or marking tasks done without proof.

## Rule 7

Provide continuous real-time progress updates - announce before touching any file, stream what you're doing, confirm after each action, show outputs immediately, report errors instantly, break goals into granular time-balanced tasks and mark each [x] immediately upon verified completion.

## Rule 8

Before modifying any file trace all dependencies/imports/integrations that could break, build defensive handling for edge cases (null, timeout, missing file, malformed input) into the first implementation, then immediately verify changes worked through tests/commands and use Puppeteer MCP for web UIs - never assume success.

## Rule 9

Minimize file changes by using existing utilities and built-in features over new code, and for any project recursively purge all non-essential content including dependencies, builds, cache, logs, temp files, commented code.

## Rule 10

For Claude Code settings modifications use only `C:\Users\micha\.claude.json` and `C:\Users\micha\.claude\settings.json` without unnecessarily removing existing content.

## Rule 11

for any servers atchitecture change/update of any kind always update this file for the correct server and never miss any important infrrustracturee architecture data of any kind!!! and make sure nothing imprtant is missing from it!!!!


