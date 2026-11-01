# AI usage connections

The 1.0 purchase does not include provider subscriptions, API credits, or access to private usage data. App license activation is separate from each provider connection. Swift is not an API-access limitation; supported interfaces and provider permissions determine availability.

DockGrove labels each source separately. A token count is not a subscription allowance.
No integration generates AI requests simply to refresh usage.

| Widget | What it measures | Setup |
| --- | --- | --- |
| Codex | Reported account allowances and reset windows | Sign in or use an existing Codex account in Connections |
| Claude Code limits | Supported Pro/Max rolling and weekly windows; optional gateway limit | Local status-line bridge |
| Gemini CLI usage | Latest imported session, per-model tokens and request counts | Import CLI JSON or pipe to capture command |
| OpenAI API | Organization input/output tokens over seven days | OpenAI organization admin key |
| Claude API | Organization API tokens over seven days | Anthropic organization admin key |
| Cursor team | Team agent/chat/composer requests and accepted tabs | Cursor team admin key |

## Claude Code

1. Put DockGrove in its permanent location, normally Applications.
2. Enable **Claude Code limits** in the widget library.
3. Open **Settings → Connections → Claude**. Choose **Sign in** or **Use CLI** to enable usage capture. **Options → Enable usage capture** also sets up the bridge separately.
4. Start a new Claude Code session. After an API response, a supported Claude
   version supplies allowance windows to DockGrove's helper.

The connection adds `statusLine` to `~/.claude/settings.json` and preserves all other
settings. If you already have a custom status line, DockGrove refuses to overwrite it.
You can integrate the capture command into your own script, passing the original JSON
stdin to `'/Applications/DockGrove.app/Contents/MacOS/DockGrove' --claude-statusline`.
The command prints a compact status line. Consult Claude's documentation before editing
an existing script; DockGrove does not execute or rewrite your custom command.

**Remove DockGrove status line** removes only the exact command this app owns. If the
setting was changed elsewhere, it is preserved. Reconnect after moving the app.

Missing windows display as unknown, never 0% used. Expired windows are removed.
Reports older than 30 minutes are labeled older reports. The status line updates
with Claude activity; it does not keep an idle session's remote quota current.
The optional session cost is API-equivalent usage, not your subscription bill.

## Gemini CLI

Enable **Gemini CLI usage**. Run Gemini yourself with `--output-format json`, save its
JSON output, and choose **Import Gemini session JSON…**. Alternatively, use **Copy CLI
capture command** and replace `YOUR PROMPT` with your intended prompt. That run may
consume your normal Gemini allowance; DockGrove itself never starts it.

```sh
gemini --output-format json -p 'YOUR PROMPT' | '/Applications/DockGrove.app/Contents/MacOS/DockGrove' --gemini-report
```

This captures the ordinary JSON output format, not `stream-json` or a telemetry log.
It retains the latest session only. Importing it again replaces the snapshot, avoiding
double counting. Prompt tokens already include cached input; the widget separates
uncached input and cache and uses the provider's total directly. Model totals can also
include thinking/tool tokens, so displayed input/output/cache need not sum to total.
No remaining Gemini web-chat or consumer-plan quota is inferred from these statistics.

## Privacy and testing

CLI helpers retain only allowlisted usage numbers and model identifiers under
`~/Library/Application Support/DockGrove/AI Usage/`. Files use mode 0600 in a private
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

## Account sign-in in Settings (October 30, 2026)

**Settings → Connections** includes ChatGPT / Codex alongside the existing provider
cards. Codex uses the installed CLI's `codex login`; Claude Code uses
`claude auth login --claudeai`. The CLI opens the provider's browser sign-in and
retains the credentials. DockGrove discards CLI stdout/stderr, waits for completion,
and refreshes usage after a successful exit. **Use existing sign-in** checks the
CLI's auth status first. A successful CLI login is not proof that the account
includes subscription allowances.

Claude's successful sign-in also enables the existing status-line bridge, preserving
any custom status line. Its usage remains unavailable until a supported Claude Code
session reports it. Gemini opens a dedicated Terminal session without a prompt;
choose **Sign in with Google**, or `/auth` to change accounts, then import a session
report in DockGrove. This is not an embedded Google OAuth client or a live Gemini
quota feed.

OpenAI API, Claude API, and Cursor team cards link to their official account
administration pages. Sign in there, obtain the appropriate admin key, and save it
in the card to fetch usage. Website sign-in does not itself connect an API account.
Keys continue to use macOS Keychain. No cookies or private consumer endpoints are
used. Cancel stops DockGrove's login attempt without logging out the shared CLI;
changing an account in the CLI affects other apps that use that CLI account.

References checked October 30, 2026:
- https://developers.openai.com/codex/auth/
- https://code.claude.com/docs/en/cli-reference
- https://geminicli.com/docs/get-started/authentication/
- https://platform.claude.com/docs/en/manage-claude/usage-cost-api
- https://cursor.com/docs/account/teams/admin-api


## Compact provider setup

Connections now groups AI setup into **OpenAI**, **Claude**, **Gemini** and **Cursor**,
with inline **Sign in**, **API token** and **Use CLI** methods. Only the selected
method's main action is shown. Refresh controls, installation links, cleanup and
advanced setup are collapsed under **Options**. Existing widget shortcuts still
route to their provider; API-widget shortcuts select the token method.

- OpenAI: browser sign-in via Codex, organization admin token, or an existing Codex account.
- Claude: browser sign-in via Claude Code, organization admin token, or an existing Claude Code account. CLI paths enable the status-line bridge; limits arrive after a supported session response.
- Gemini: Google sign-in in Gemini CLI or importing an existing CLI session. The API-token method is disabled because that token does not expose the usage displayed by this integration.
- Cursor: dashboard sign-in or a team admin token. Dashboard sign-in shows usage on Cursor; the token is required to display it in DockGrove. CLI usage is unavailable and disabled.

Switching providers or leaving token entry clears the unsaved token field. Saved
tokens continue to use Keychain. This presentation change does not add new OAuth
clients, change provider permissions, or infer subscription limits from API totals.
