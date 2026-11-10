import Link from "next/link";
import type { Metadata } from "next";
import { sharedOpenGraph } from "@/lib/metadata";
import Brand from "@/components/site/Brand";
import PreviewBanner from "@/components/site/PreviewBanner";
import SkipLink from "@/components/site/SkipLink";

const description =
  "What DockGrove keeps on your Mac, what the developer receives, which services you can connect, and how to delete your data or revoke consent.";

export const metadata: Metadata = {
  title: "Privacy",
  description,
  alternates: { canonical: "/privacy" },
  openGraph: { ...sharedOpenGraph, title: "Privacy — DockGrove", description, url: "/privacy" },
};

const listClass = "list-disc space-y-2 pl-5 text-[var(--muted)]";
const subheadClass = "mt-6 mb-0 text-[1.0625rem] font-semibold tracking-normal";
const cellClass = "border-b border-[var(--line)] py-3 pr-4 align-top";
const headClass = `${cellClass} text-left font-semibold`;

type Row = { name: string; policy: string; receives: string; when: string };

const connections: Row[] = [
  {
    name: "Apple",
    policy: "https://www.apple.com/legal/privacy/",
    receives:
      "Weather: the city you type, then its coordinates. AirDrop: the files you choose and the recipient you pick.",
    when: "You press Get weather, or you send a file with AirDrop.",
  },
  {
    name: "Frankfurter",
    policy: "https://frankfurter.dev",
    receives: "The currency pair. Your amount stays on your Mac.",
    when: "You refresh a rate in the currency widget.",
  },
  {
    name: "GitHub",
    policy:
      "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement",
    receives:
      "The repository name you enter. If you turn on the GitHub CLI option, the request uses the account you signed in to with gh.",
    when: "You refresh the GitHub widget, or every five minutes if you turn on auto refresh.",
  },
  {
    name: "OpenAI",
    policy: "https://openai.com/policies/privacy-policy/",
    receives:
      "OpenAI API widget: your organization admin key and a seven-day date range. Codex widget: your own Codex app or CLI asks for your allowance windows under your signed-in account.",
    when: "You save a key or connect Codex. Saved keys refresh at launch, when you ask, and hourly if you turn on auto refresh.",
  },
  {
    name: "Anthropic",
    policy: "https://www.anthropic.com/legal/privacy",
    receives:
      "Claude API widget: your organization admin key and a date range. Claude Code limits widget: your own Claude Code CLI runs its /usage command under your signed-in account.",
    when: "You save a key, or the Claude Code limits widget is enabled. With that widget on, /usage runs at most every five minutes.",
  },
  {
    name: "Cursor",
    policy: "https://cursor.com/privacy",
    receives:
      "Your team admin key and a seven-day date range. Cursor’s reply covers your team; DockGrove adds up four request counters and discards the rest.",
    when: "You save a key. It refreshes at launch, when you ask, and hourly if you turn on auto refresh.",
  },
  {
    name: "Google",
    policy: "https://policies.google.com/privacy",
    receives:
      "DockGrove sends Google nothing itself. Gemini CLI, which you run, talks to Google under your own account. The Google Calendar widget reads calendars already added to macOS.",
    when: "You run Gemini CLI or finish its sign-in in Terminal.",
  },
  {
    name: "Spotify",
    policy: "https://www.spotify.com/legal/privacy-policy/",
    receives:
      "A request for the current album artwork from Spotify’s image service. Playback control stays between DockGrove and the Spotify app on your Mac.",
    when: "The Spotify widget is connected and a track has artwork.",
  },
  {
    name: "DuckDuckGo",
    policy: "https://duckduckgo.com/privacy",
    receives: "Your search text, opened in your default browser.",
    when: "You search the web with this engine selected. It is the default.",
  },
  {
    name: "Google Search",
    policy: "https://policies.google.com/privacy",
    receives: "Your search text, opened in your default browser.",
    when: "You search the web with this engine selected.",
  },
  {
    name: "Microsoft Bing",
    policy: "https://www.microsoft.com/privacy/privacystatement",
    receives: "Your search text, opened in your default browser.",
    when: "You search the web with this engine selected.",
  },
];

/** Port of website/public/privacy.html. */
export default function PrivacyPage() {
  return (
    <>
      <SkipLink />
      <PreviewBanner />
      <main className="section document" id="main">
        <Brand />
        <h1>
          Your Mac.
          <br />
          Your control.
        </h1>
        <p>
          Privacy policy for DockGrove and dockgrove.com. Updated November 6, 2026. This describes
          the DockGrove 1.0 commercial release candidate. Live sales are not enabled. The public
          website currently serves static pages only. The purchase, activation and recovery
          services described below are not deployed, so no customer purchase records exist yet.
        </p>
        <p>
          DockGrove and this website are provided by the developer of DockGrove, called “the
          developer” below.
        </p>
        <ul className={listClass}>
          <li>DockGrove has no accounts, advertising, analytics or crash reporting.</li>
          <li>Your notes, tasks, voice memos, files and calendar stay on your Mac.</li>
          <li>Other services hear from DockGrove only when you turn on a feature that uses them.</li>
          <li>DockGrove never sends your prompts or files to an AI service.</li>
          <li>You can disconnect, delete or revoke everything described here.</li>
        </ul>

        <h2>Data stored on your Mac</h2>
        <p>
          You create this data by using DockGrove. It is saved on your Mac and is not uploaded to
          the developer. Your own Mac backups may include it.
        </p>
        <ul className={listClass}>
          <li>
            <strong>Preferences.</strong> Notes, tasks, habits, water count, bookmarks, world clocks,
            app groups, layouts, shortcuts, widget choices, companion progress, selected calendars,
            your GitHub repository name and your Codex executable path. Shortcuts keep a file’s
            path, not its contents. These are saved in macOS preferences.
          </li>
          <li>
            <strong>Voice memos.</strong> Recording starts only when you press Record. Audio is saved
            to the Voice Memos folder in DockGrove’s Application Support folder and is not uploaded.
          </li>
          <li>
            <strong>App search.</strong> AppIndex.yml lists your installed apps’ names and locations,
            and the searches that led you to open them, so results improve over time.
          </li>
          <li>
            <strong>AI usage reports.</strong> Saved in the AI Usage folder. See AI usage below.
          </li>
          <li>
            <strong>macOS Keychain.</strong> AI provider admin keys, your license key, your signed
            activation and a random installation identifier. These items do not sync to your other
            devices.
          </li>
          <li>
            <strong>Dock backup.</strong> If DockGrove hides the macOS Dock, it saves your original
            Dock settings so it can restore them.
          </li>
          <li>
            <strong>Layout exports.</strong> Saved only to a file you choose.
          </li>
        </ul>
        <p>
          DockGrove’s Application Support folder is ~/Library/Application Support/DockGrove, or
          WaveDock if you installed an earlier version.
        </p>
        <p>
          Some data is only held in memory and disappears when you quit: clipboard history, calendar
          events, reminders, current track, window titles, system readings, your weather city, and
          usage totals from provider APIs. Clipboard history is off until you turn it on, keeps up
          to 20 text items, and skips items marked as concealed by password managers.
        </p>

        <h2>Permissions macOS asks for</h2>
        <p>Each one is optional, and DockGrove only asks when you use the feature that needs it.</p>
        <ul className={listClass}>
          <li>
            <strong>Microphone.</strong> Voice memos, only while you record.
          </li>
          <li>
            <strong>Calendars.</strong> Shows events from the next seven days, using macOS EventKit.
            This includes any Google calendars already added in macOS Internet Accounts. DockGrove
            does not sign in to Google for this.
          </li>
          <li>
            <strong>Reminders.</strong> Shows your incomplete reminders and marks them complete when
            you ask.
          </li>
          <li>
            <strong>Automation.</strong> Reads the track, artist, playback state and artwork from
            Spotify or Apple Music, and sends the playback commands you choose. System Events is
            used to read and change apps’ Open at Login setting when you use that control.
          </li>
          <li>
            <strong>Accessibility.</strong> Lets window tools read window titles and positions, and
            move the windows you choose.
          </li>
          <li>
            <strong>Files and folders.</strong> DockGrove opens only what you add or choose. The
            folder widget lists names and dates, starting in Downloads.
          </li>
          <li>
            <strong>Screen tools.</strong> The screenshot and color tools use the macOS capture and
            color picker when you start them. Screenshots go to your clipboard.
          </li>
        </ul>
        <p>
          DockGrove also reads your running apps, CPU, memory, network speed, storage, battery and
          audio devices to show them on screen. It does not record this. It does not request your
          device’s location.
        </p>

        <h2>AI usage</h2>
        <p>
          DockGrove shows how much of your AI allowance you have used. It does not run AI inference,
          and it does not send your prompts, notes or files to any AI provider. These connections
          are optional, and each one starts only when you enable it.
        </p>
        <ul className={listClass}>
          <li>
            <strong>Claude Code status line.</strong> When you connect, DockGrove adds a status line
            command to ~/.claude/settings.json, keeps the rest of your settings, and saves any custom
            status line command so it can be restored. Claude Code then passes session details to
            that command. DockGrove keeps only limit percentages, reset times and session cost, in
            claude.json. It discards the rest, including prompts, responses, transcript paths and
            session IDs. Your own status line command, if you have one, still receives the full
            input.
          </li>
          <li>
            <strong>Claude Code limits.</strong> While this widget is enabled, DockGrove runs{" "}
            <code>claude -p /usage</code> on your Mac at most every five minutes. It saves your limit
            windows, reset times, the “Last 24h” summary line and up to three short “what’s
            contributing” lines in claude-usage.json. Those lines are text written by Claude Code, so
            not every saved value is a number.
          </li>
          <li>
            <strong>Codex.</strong> DockGrove starts your installed Codex app or CLI and asks only
            for your allowance windows, using your existing sign-in. It does not read your token
            files, and it does not save the result. It does not count ordinary ChatGPT messages.
          </li>
          <li>
            <strong>Gemini CLI.</strong> DockGrove never starts a prompt. If you import a report or
            pipe one in, it keeps only model names, token counts and request counts in gemini.json.
            Response text is discarded. Its sign-in helper opens Terminal and is saved in the Gemini
            Sign In folder.
          </li>
          <li>
            <strong>OpenAI, Claude and Cursor APIs.</strong> Your admin key stays in Keychain and is
            sent only to the provider it belongs to. DockGrove asks for seven days of organization
            totals and keeps those totals in memory.
          </li>
          <li>
            <strong>Sign-in.</strong> “Sign in” starts the provider’s own CLI, and you finish in your
            browser or Terminal. DockGrove never sees your password, and CLI output does not enter
            app logs.
          </li>
        </ul>

        <h2>Data the developer receives</h2>
        <p>
          Using DockGrove’s widgets sends nothing to the developer. The developer receives data only
          in the cases below, once these services are live, and only for the purposes listed.
        </p>
        <h3 className={subheadClass}>Purchases</h3>
        <p>
          Stripe hosts checkout and processes card details. The developer never receives your card
          number. DockGrove stores the purchase email, Stripe session and payment identifiers,
          payment status, the product, amount and currency, the purchase time, and license records.
        </p>
        <h3 className={subheadClass}>Activation</h3>
        <p>
          On a commercial build, the app sends your license key and a random installation identifier
          when you activate or deactivate, and to refresh your activation about once a day. The
          activation service stores a hash of that identifier, its status and when it last changed,
          to enforce the personal-device allowance. It does not receive your Mac’s serial number,
          documents, or browsing history. License keys and recovery tokens are checked against
          cryptographic hashes; a signed activation is cached locally in Keychain.
        </p>
        <h3 className={subheadClass}>Purchase recovery</h3>
        <p>
          If you ask to recover a purchase, the service uses your email address to find it. Resend
          delivers the message and receives your email address and the recovery message, once it is
          configured. Recovery links carry a short-lived token in the URL fragment, which the
          recovery page removes before completing verification.
        </p>
        <h3 className={subheadClass}>Support</h3>
        <p>
          The developer receives whatever you choose to send when you ask for help. GitHub issues are
          public, so do not post email addresses, license keys, or payment information there.
        </p>
        <h3 className={subheadClass}>How this data is used</h3>
        <p>
          Purchase and activation data is used to complete your purchase, deliver and verify your
          license, enforce the device allowance, recover a lost license, handle refunds and disputes,
          limit abuse, and answer you. It is not sold, and it is not used for advertising or to track
          you across apps or websites.
        </p>
        <h3 className={subheadClass}>App Store purchases</h3>
        <p>
          The planned release is sold directly. Some builds also contain Apple in-app purchase code.
          In those builds, Apple processes the purchase under its own policy, and the app checks
          Apple’s verified transactions on your Mac to decide which features you own.
        </p>

        <h2>Optional third-party connections</h2>
        <p>
          DockGrove contacts these services only for the features you turn on. Each one also sees
          your IP address and normal request details, as with any internet request. They apply their
          own privacy policies.
        </p>
        <div
          className="overflow-x-auto"
          role="region"
          aria-label="Third-party connections"
          tabIndex={0}
        >
          <table className="w-full min-w-[640px] border-collapse text-[0.875rem] text-[var(--muted)]">
            <thead>
              <tr>
                <th className={headClass} scope="col">
                  Service
                </th>
                <th className={headClass} scope="col">
                  What it receives
                </th>
                <th className={headClass} scope="col">
                  Only when
                </th>
              </tr>
            </thead>
            <tbody>
              {connections.map((row) => (
                <tr key={row.name}>
                  <th className={`${cellClass} whitespace-nowrap text-left font-normal`} scope="row">
                    <strong>{row.name}</strong>
                    <br />
                    <a href={row.policy}>
                      {row.name === "Frankfurter" ? "Website" : "Privacy policy"}
                    </a>
                  </th>
                  <td className={cellClass}>{row.receives}</td>
                  <td className={cellClass}>{row.when}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <h2>How third parties protect your data</h2>
        <p>
          The app contains no analytics tools, advertising networks or third-party SDKs. Cloudflare,
          Stripe and Resend handle data on the developer’s behalf for the purposes above. Any service
          provider or related party given access to user data must provide the same or equal
          protection as this policy and Apple’s App Store guidelines require.
        </p>
        <p>
          The services in the table above work differently. You connect them yourself, usually with
          your own account, and DockGrove sends them only what the table shows. Your relationship
          with them is governed by their own terms and privacy policies, so read those before you
          connect.
        </p>

        <h2>Website, cookies and hosting</h2>
        <p>
          Cloudflare hosts dockgrove.com and processes network requests, including IP addresses and
          other network metadata. The website has no advertising or analytics, and its pages load no
          third-party scripts. The static pages live today set no cookies and use no browser storage.
        </p>
        <p>
          When sales are live, an essential HttpOnly purchase-session cookie, lasting seven days, lets
          you retrieve your own purchase after checkout. License keys are not stored in localStorage.
          The planned backend uses Cloudflare Workers, D1 and private R2 storage. Rate limiting uses
          short-lived hashes derived from request details.{" "}
          <a href="https://www.cloudflare.com/privacypolicy/">Cloudflare</a>,{" "}
          <a href="https://stripe.com/privacy">Stripe</a> and{" "}
          <a href="https://resend.com/legal/privacy-policy">Resend</a> publish their own privacy
          policies.
        </p>

        <h2>Retention and deletion</h2>
        <p>
          <strong>On your Mac.</strong> Local data stays until you delete it. Removing the DockGrove
          app does not remove it.
        </p>
        <ul className={listClass}>
          <li>Delete notes, tasks, bookmarks and shortcuts in the app.</li>
          <li>
            Choose Clear history for clipboard text, or quit DockGrove. Clipboard history is never
            written to disk.
          </li>
          <li>
            Use All recordings in Finder to find voice memos, then delete the files. Choose Clear
            local snapshot to delete a saved AI usage report.
          </li>
          <li>Disconnect a provider to remove its admin key from Keychain.</li>
          <li>
            To remove everything, delete DockGrove’s Application Support folder, delete the
            com.dylan.wavedock preferences file in ~/Library/Preferences, and use Keychain Access to
            delete items named app.wavedock.ai-usage or starting with com.dylan.wavedock.license.
          </li>
        </ul>
        <p>
          <strong>On the developer’s services.</strong> Once live, recovery tokens expire after 15
          minutes and are deleted about a day later. Queued recovery messages are deleted once sent
          or expired. Rate-limit records are cleared within minutes. Purchase, license and activation
          records have no automatic deletion, because they are needed for activation and recovery.
          Deactivating a Mac frees its slot but keeps the record. A final retention period requires
          owner review before live sales, and this policy will state it.
        </p>
        <p>
          <strong>Deletion requests.</strong> You can ask the developer to access, correct or delete
          the purchase and license data held about you. Use the contact route below. Deleting these
          records ends activation and recovery for that license. Stripe, Resend and Cloudflare keep
          their own records under their own policies, and connected services keep theirs. Ask them
          directly.
        </p>

        <h2>Revoking consent</h2>
        <ul className={listClass}>
          <li>
            Revoke Microphone, Calendars, Reminders, Automation or Accessibility access in System
            Settings › Privacy &amp; Security.
          </li>
          <li>Turn off Capture copied text, or remove any widget, to stop that feature.</li>
          <li>
            Choose Remove DockGrove status line to restore your Claude Code settings. Remove the
            Claude Code limits widget to stop /usage.
          </li>
          <li>
            Disconnect an API provider in Settings › Connections. To sign out of a CLI, use that
            provider’s own sign-out command; DockGrove leaves your CLI accounts as they are.
          </li>
          <li>Deactivate a Mac from the app before transferring its activation slot.</li>
        </ul>
        <p>
          Revoking access stops future collection. It does not delete what is already saved, so use
          the steps above for that.
        </p>

        <h2>Children</h2>
        <p>
          DockGrove is not directed at children under 13, and the developer does not knowingly collect
          personal data from them. If you think a child has given the developer personal data, use
          the contact route below and it will be deleted.
        </p>

        <h2>Changes to this policy</h2>
        <p>
          When this policy changes, the updated version will be posted here with a new date. If a
          change affects how your data is used, this page will be updated before it takes effect.
        </p>

        <h2>Contact</h2>
        <p>
          For privacy questions, access or deletion requests, go to{" "}
          <Link href="/support">DockGrove support</Link> and request a private contact method. Do not
          post email addresses, license keys, or payment information publicly.
        </p>

        <h2>Release status</h2>
        <p>
          This candidate is not Apple-notarized and has not undergone a production security audit.
          Live checkout, approved customer terms, and final support handling are release
          prerequisites.
        </p>
        <p className="support-link">
          <Link href="/">← Back to DockGrove</Link> · <Link href="/support">Support</Link> ·{" "}
          <Link href="/privacy">Privacy</Link>
        </p>
      </main>
    </>
  );
}
