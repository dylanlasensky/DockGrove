# AI usage connections

WaveDock labels each source separately. A token count is not a subscription allowance.
No integration generates AI requests simply to refresh usage.

| Widget | What it measures | Setup |
| --- | --- | --- |
| Codex | Reported account allowances and reset windows | Existing signed-in Codex CLI |
| Claude Code limits | Supported Pro/Max rolling and weekly windows; optional gateway limit | Local status-line bridge |
| Gemini CLI usage | Latest imported session, per-model tokens and request counts | Import CLI JSON or pipe to capture command |
| OpenAI API | Organization input/output tokens over seven days | OpenAI organization admin key |
| Claude API | Organization API tokens over seven days | Anthropic organization admin key |
| Cursor team | Team agent/chat/composer requests and accepted tabs | Cursor team admin key |

## Claude Code

1. Put WaveDock in its permanent location, normally Applications.
2. Enable **Claude Code limits** in the widget library.
3. Open it and choose **Connect Claude Code status line**.
4. Start a new Claude Code session. After an API response, a supported Claude
   version supplies allowance windows to WaveDock's helper.

The connection adds `statusLine` to `~/.claude/settings.json` and preserves all other
settings. If you already have a custom status line, WaveDock refuses to overwrite it.
You can integrate the capture command into your own script, passing the original JSON
stdin to `'/Applications/WaveDock.app/Contents/MacOS/WaveDock' --claude-statusline`.
The command prints a compact status line. Consult Claude's documentation before editing
an existing script; WaveDock does not execute or rewrite your custom command.

**Remove WaveDock status line** removes only the exact command this app owns. If the
setting was changed elsewhere, it is preserved. Reconnect after moving the app.

Missing windows display as unknown, never 0% used. Expired windows are removed.
Reports older than 30 minutes are labeled older reports. The status line updates
with Claude activity; it does not keep an idle session's remote quota current.
The optional session cost is API-equivalent usage, not your subscription bill.

## Gemini CLI

Enable **Gemini CLI usage**. Run Gemini yourself with `--output-format json`, save its
JSON output, and choose **Import Gemini session JSON…**. Alternatively, use **Copy CLI
capture command** and replace `YOUR PROMPT` with your intended prompt. That run may
consume your normal Gemini allowance; WaveDock itself never starts it.

```sh
gemini --output-format json -p 'YOUR PROMPT' | '/Applications/WaveDock.app/Contents/MacOS/WaveDock' --gemini-report
```

This captures the ordinary JSON output format, not `stream-json` or a telemetry log.
It retains the latest session only. Importing it again replaces the snapshot, avoiding
double counting. Prompt tokens already include cached input; the widget separates
uncached input and cache and uses the provider's total directly. Model totals can also
include thinking/tool tokens, so displayed input/output/cache need not sum to total.
No remaining Gemini web-chat or consumer-plan quota is inferred from these statistics.

## Privacy and testing

CLI helpers retain only allowlisted usage numbers and model identifiers under
`~/Library/Application Support/WaveDock/AI Usage/`. Files use mode 0600 in a private
directory. Prompts, response text, transcript paths, session IDs and credentials are
discarded. Imports are bounded to 20 MB. **Clear local snapshot** deletes the stored
metrics; future CLI reports can create a new snapshot if the bridge remains enabled.

Provider contracts, invalid/missing values, expiry, stale data, duplicate imports,
privacy filtering and non-destructive setup are covered by deterministic tests.
Personal Claude/Gemini account access was not exercised, at the user's request.

Primary references, checked October 28, 2026:
- https://code.claude.com/docs/en/statusline
- https://geminicli.com/docs/cli/headless/
- https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/telemetry/uiTelemetry.ts
