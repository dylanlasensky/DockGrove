import Link from "next/link";
import type { Metadata } from "next";
import { sharedOpenGraph } from "@/lib/metadata";
import Brand from "@/components/site/Brand";
import PreviewBanner from "@/components/site/PreviewBanner";
import SkipLink from "@/components/site/SkipLink";

/** The one place the support contact is defined. Replace it if an address is added. */
const SUPPORT_CONTACT = "https://github.com/dylanlasensky/DockGrove/issues";

const description =
  "Get help with DockGrove: how to contact support, system requirements, permissions, troubleshooting, restoring Apple’s Dock and uninstalling.";

export const metadata: Metadata = {
  title: "Support",
  description,
  alternates: { canonical: "/support" },
  openGraph: {
    ...sharedOpenGraph,
    title: "Support — DockGrove",
    description,
    url: "/support",
  },
};

const list = "my-[1em] list-disc space-y-2 pl-6 text-[var(--muted)]";
const steps = "my-[1em] list-decimal space-y-2 pl-6 text-[var(--muted)]";
const subheading = "mt-7 text-[1.0625rem] font-semibold";
const path = "[overflow-wrap:anywhere]";

export default function SupportPage() {
  return (
    <>
      <SkipLink />
      <PreviewBanner />
      <main className="section document" id="main">
        <Brand />
        <h1>Help with DockGrove.</h1>
        <p>
          How to reach support, set up DockGrove, manage its permissions, fix common problems and
          put Apple’s Dock back. This page describes the DockGrove 1.0 release candidate. Updated
          November 6, 2026.
        </p>
        <ul className={list}>
          <li>
            <a href="#contact">Contact support</a>
          </li>
          <li>
            <a href="#getting-started">Getting started</a>
          </li>
          <li>
            <a href="#permissions">Permissions</a>
          </li>
          <li>
            <a href="#troubleshooting">Troubleshooting</a>
          </li>
          <li>
            <a href="#restore-and-uninstall">Restoring Apple’s Dock and uninstalling</a>
          </li>
          <li>
            <a href="#purchases">Purchases and recovery</a>
          </li>
        </ul>

        <h2 id="contact">Contact support</h2>
        <p>
          Open an issue on GitHub at{" "}
          <a className={path} href={SUPPORT_CONTACT}>
            {SUPPORT_CONTACT.replace("https://", "")}
          </a>
          . You need a free GitHub account to open one. Replies appear on the issue. There is no
          guaranteed response time.
        </p>
        <p>
          Issues are public. Never post your email address, license key, payment details or API
          keys. If your question needs any of these, such as a purchase or data request, open an
          issue asking for a private contact method and leave the details out.
        </p>
        <p>
          It helps to include your macOS version, your Mac model, the DockGrove build you are using,
          what you did and what happened. Check screenshots for personal information before you
          attach them.
        </p>

        <h2 id="getting-started">Getting started</h2>
        <h3 className={subheading}>System requirements</h3>
        <ul className={list}>
          <li>macOS 14 Sonoma or newer.</li>
          <li>An Apple silicon or Intel Mac. DockGrove is a universal app.</li>
          <li>
            AI usage widgets also need the matching account, command-line tool or admin key. All
            other widgets work without them.
          </li>
        </ul>
        <p>
          DockGrove 1.0 is not on sale yet and has no public commercial download. Current review
          builds are not notarized by Apple. If macOS blocks a build you trust, use{" "}
          <strong>System Settings → Privacy &amp; Security → Open Anyway</strong>. Do not turn off
          Gatekeeper.
        </p>
        <h3 className={subheading}>First setup</h3>
        <ol className={steps}>
          <li>
            Open DockGrove. It runs from the menu bar and starts alongside Apple’s Dock, so nothing
            about your Dock changes yet.
          </li>
          <li>
            Open Settings from the DockGrove icon in the menu bar, or from the sliders button in
            DockGrove.
          </li>
          <li>
            In <strong>Library</strong>, drag widgets or apps into <strong>Your Dock</strong>, or
            directly onto the DockGrove bar.
          </li>
          <li>
            In <strong>Appearance</strong>, choose a theme, toolbar size and widget shapes.
          </li>
          <li>
            In <strong>Behavior</strong>, choose a display, automatic hiding and window snapping.
            Turn on <strong>Use DockGrove as my Dock</strong> if you want it to replace Apple’s
            Dock.
          </li>
          <li>
            In <strong>Connections</strong>, set up only the accounts and apps you want. All of them
            are optional.
          </li>
        </ol>
        <p>
          Changes save automatically. Select <strong>Quick start guide</strong> in Settings to see
          the guide again.
        </p>

        <h2 id="permissions">Permissions</h2>
        <p>
          DockGrove asks for a macOS permission only when you use a feature that needs it. Every
          permission is optional, and the rest of the app keeps working if you decline. You can
          change any of them in <strong>System Settings → Privacy &amp; Security</strong>. macOS may
          ask you to reopen DockGrove after a change, and a replaced or rebuilt copy may need
          permission again.
        </p>
        <p>
          DockGrove does not ask for camera or location access. The notch feature does not use the
          camera, and Weather uses the city you enter.
        </p>
        <h3 className={subheading}>Accessibility</h3>
        <ul className={list}>
          <li>
            <strong>Why:</strong> to find, restore, move and resize windows of other apps. The Your
            windows cube, the Windows widget and window snapping use it. Window titles stay in
            memory.
          </li>
          <li>
            <strong>Grant:</strong> choose <strong>Allow Accessibility</strong> in one of those
            features, turn on DockGrove in <strong>Privacy &amp; Security → Accessibility</strong>,
            then refresh windows.
          </li>
          <li>
            <strong>Revoke:</strong> turn off DockGrove in that same list.
          </li>
          <li>
            The Dock itself and ⌥⌘D do not need this permission. Window features do not need Screen
            Recording.
          </li>
        </ul>
        <h3 className={subheading}>Automation</h3>
        <ul className={list}>
          <li>
            <strong>Why:</strong> to show the current track and control playback in Spotify or Apple
            Music. It is also used for System Events when you set <strong>Open at Login</strong>{" "}
            for another app from its Dock menu.
          </li>
          <li>
            <strong>Grant:</strong> open your player and select a track. In{" "}
            <strong>Settings → Connections</strong>, choose the player and turn on{" "}
            <strong>Allow access</strong>, then approve the macOS prompt.
          </li>
          <li>
            <strong>Revoke:</strong> in <strong>Privacy &amp; Security → Automation</strong>, turn
            off the app under DockGrove. Turning off Allow access in DockGrove stops it reading your
            player.
          </li>
        </ul>
        <h3 className={subheading}>Microphone</h3>
        <ul className={list}>
          <li>
            <strong>Why:</strong> to record voice memos, only when you press Record. Audio stays on
            your Mac unless you export it.
          </li>
          <li>
            <strong>Grant:</strong> choose <strong>Record new memo</strong> in the voice memo
            widget, then approve the macOS prompt.
          </li>
          <li>
            <strong>Revoke:</strong> turn off DockGrove in{" "}
            <strong>Privacy &amp; Security → Microphone</strong>.
          </li>
        </ul>
        <h3 className={subheading}>Calendars</h3>
        <ul className={list}>
          <li>
            <strong>Why:</strong> to show the next seven days of events from the calendars set up on
            your Mac, including Google calendars added to macOS Internet Accounts. DockGrove does
            not edit events.
          </li>
          <li>
            <strong>Grant:</strong> in <strong>Settings → Connections</strong>, choose Calendar or
            Google Calendar, turn on <strong>Allow calendar access</strong>, then approve the macOS
            prompt.
          </li>
          <li>
            <strong>Revoke:</strong> turn off DockGrove in{" "}
            <strong>Privacy &amp; Security → Calendars</strong>.
          </li>
        </ul>
        <h3 className={subheading}>Reminders</h3>
        <ul className={list}>
          <li>
            <strong>Why:</strong> to list your incomplete reminders and mark the ones you choose as
            complete. Completing a reminder saves that change to Apple Reminders.
          </li>
          <li>
            <strong>Grant:</strong> in <strong>Settings → Connections</strong>, choose Reminders,
            select <strong>Allow / refresh Reminders access</strong>, then approve the macOS prompt.
          </li>
          <li>
            <strong>Revoke:</strong> turn off DockGrove in{" "}
            <strong>Privacy &amp; Security → Reminders</strong>.
          </li>
        </ul>
        <h3 className={subheading}>Screen capture</h3>
        <ul className={list}>
          <li>
            <strong>Why:</strong> the Screenshot widget uses the macOS capture tool, and only when
            you press its button. macOS handles any permission it needs.
          </li>
          <li>
            <strong>Grant or revoke:</strong> if capture is unavailable, check{" "}
            <strong>Privacy &amp; Security → Screen Recording</strong>, which newer macOS versions
            call Screen &amp; System Audio Recording.
          </li>
        </ul>
        <h3 className={subheading}>Login items</h3>
        <ul className={list}>
          <li>
            <strong>Why:</strong> to open DockGrove when you log in, if you choose that.
          </li>
          <li>
            <strong>Grant:</strong> turn on <strong>Open DockGrove at login</strong> in{" "}
            <strong>Settings → Behavior</strong>. If macOS asks for approval, allow DockGrove in{" "}
            <strong>System Settings → General → Login Items</strong>.
          </li>
          <li>
            <strong>Revoke:</strong> turn off that switch or remove DockGrove from Login Items.
          </li>
        </ul>

        <h2 id="troubleshooting">Troubleshooting</h2>
        <h3 className={subheading}>The Dock is not showing</h3>
        <ol className={steps}>
          <li>Press ⌥⌘D. This turns hiding off, or brings back a Dock that was switched off.</li>
          <li>
            If hiding is on, move the pointer to the screen edge and pause for a moment. The Dock
            hides again shortly after you move away.
          </li>
          <li>
            Open the DockGrove icon in the menu bar and choose <strong>Show DockGrove</strong> or{" "}
            <strong>Turn Hiding Off</strong>.
          </li>
          <li>
            In <strong>Settings → Behavior</strong>, check the selected display, and turn off{" "}
            <strong>Hide when windows overlap</strong> if it is on.
          </li>
        </ol>
        <p>
          DockGrove also stays out of sight during full-screen apps, when the active app covers the
          whole display, while your session is locked or inactive, and while the display sleeps. It
          returns on its own afterwards.
        </p>
        <h3 className={subheading}>Hiding and showing with ⌥⌘D</h3>
        <p>
          ⌥⌘D turns hiding on or off from any app. If you switched DockGrove off completely, it
          brings the Dock back with hiding off. <strong>Turn Hiding On</strong> and{" "}
          <strong>Turn Hiding Off</strong> are also in the menu bar, and the same setting is{" "}
          <strong>Automatically hide and show the Dock</strong> in Behavior.
        </p>
        <p>
          ⌥⌘D is also the macOS shortcut for hiding Apple’s Dock. If it seems to act on Apple’s Dock
          instead, use the menu bar item. While DockGrove is your Dock, turning off{" "}
          <strong>Show DockGrove</strong> hides it automatically, so a Dock is always reachable from
          the screen edge.
        </p>
        <h3 className={subheading}>Getting Apple’s Dock back</h3>
        <p>
          Open the DockGrove icon in the menu bar and choose <strong>Restore Apple Dock</strong>.
          See <a href="#restore-and-uninstall">Restoring Apple’s Dock</a> for other ways, including
          what to do if DockGrove will not open.
        </p>
        <h3 className={subheading}>A widget is not updating</h3>
        <p>Not every widget updates by itself. Here is how each one refreshes.</p>
        <ul className={list}>
          <li>
            <strong>Calendars:</strong> update every minute and when your calendars change, while
            connected. Check that Allow calendar access is on and that a calendar is selected.
          </li>
          <li>
            <strong>Spotify and Apple Music:</strong> update every ten seconds while connected. Open
            the player and select a track, then check Automation permission.
          </li>
          <li>
            <strong>Weather:</strong> updates only when you refresh it. It uses the first city that
            matches your search, and shows Fahrenheit.
          </li>
          <li>
            <strong>Currency:</strong> updates only when you choose Refresh rate. It shows daily
            reference rates.
          </li>
          <li>
            <strong>GitHub:</strong> choose Refresh GitHub, or turn on Refresh every five minutes.
          </li>
          <li>
            <strong>AI usage:</strong> choose <strong>Refresh usage</strong> in the menu bar for
            Codex. If a refresh fails, you see a marked earlier reading or an unavailable state, not
            a guessed value.
          </li>
          <li>
            <strong>Windows:</strong> choose Refresh windows, and check Accessibility permission.
          </li>
        </ul>
        <h3 className={subheading}>The notch</h3>
        <p>
          Notch quick access is off until you turn it on in{" "}
          <strong>Settings → Appearance → Notch quick access</strong>. It needs a display with a
          built-in camera notch. If you see “Not available on this display”, no compatible display
          is connected. With several displays, it uses the first compatible one.
        </p>
        <p>
          The strip opens by hover or click, depending on your notch settings. Press Esc or click
          outside to close it. It hides when DockGrove is hidden, during full-screen apps, on the
          lock screen and during sleep. It does not use the camera.
        </p>
        <h3 className={subheading}>Connecting usage sources</h3>
        <p>
          Add the widget from <strong>Library</strong>, then set it up in{" "}
          <strong>Settings → Connections</strong>. DockGrove does not include provider subscriptions
          or credits, and connecting a source does not run any AI requests.
        </p>
        <ul className={list}>
          <li>
            <strong>Codex:</strong> choose OpenAI, then <strong>Sign in</strong> or{" "}
            <strong>Use CLI</strong>. If Codex is not found, enter its location under Options. This
            shows the allowances Codex reports for your account. It does not count ordinary ChatGPT
            messages, and API-key-only accounts may show nothing.
          </li>
          <li>
            <strong>Claude Code:</strong> keep DockGrove in its permanent location, normally
            Applications. Choose Claude, then <strong>Sign in</strong> or <strong>Use CLI</strong>,
            and start a new Claude Code session. Usage appears after a response and updates with
            Claude Code activity. Connect again if you move the app.
          </li>
          <li>
            <strong>Gemini CLI:</strong> run Gemini with <code>--output-format json</code>, save the
            output, then choose <strong>Import Gemini session JSON…</strong>. Only the latest session
            is kept.
          </li>
          <li>
            <strong>OpenAI API, Claude API and Cursor team:</strong> these use an organization or
            team admin key, entered under <strong>API token</strong>, and cover the last seven days.
            Keys stay in macOS Keychain. They do not show personal plan limits.
          </li>
        </ul>

        <h2 id="restore-and-uninstall">Restoring Apple’s Dock and uninstalling</h2>
        <p>
          DockGrove does not patch macOS or remove icons from Apple’s Dock. When it replaces the
          Dock, it saves your original settings, then changes only two Dock preferences:{" "}
          <code>autohide</code> and <code>autohide-delay</code>. Restoring puts back those exact
          values and relaunches Apple’s Dock, so you may see a brief flash on the desktop.
        </p>
        <h3 className={subheading}>Restore Apple Dock</h3>
        <p>Any one of these works:</p>
        <ul className={list}>
          <li>
            In the menu bar, open the DockGrove icon and choose{" "}
            <strong>Restore Apple Dock</strong>.
          </li>
          <li>
            In Settings, select <strong>Restore Apple Dock…</strong> in the sidebar and confirm.
          </li>
          <li>
            In <strong>Settings → Behavior</strong>, turn off{" "}
            <strong>Use DockGrove as my Dock</strong>.
          </li>
          <li>
            Quit DockGrove. This also restores Apple’s Dock, but replacement stays on and returns
            the next time you open DockGrove unless you turn it off.
          </li>
        </ul>
        <h3 className={subheading}>If DockGrove quit unexpectedly</h3>
        <p>
          Your Dock settings stay changed until DockGrove restores them. Open DockGrove and use
          Restore Apple Dock. If it will not open, run this in Terminal with DockGrove not running,
          changing the path if the app is somewhere else:
        </p>
        <p>
          <code className={path}>
            /Applications/DockGrove.app/Contents/MacOS/DockGrove --restore-dock
          </code>
        </p>
        <p>
          You can also turn off auto-hide in <strong>System Settings → Desktop &amp; Dock</strong>.
          If you deleted DockGrove before restoring and later turn auto-hide back on, the Dock may
          seem not to appear. This command clears the delay DockGrove set:
        </p>
        <p>
          <code className={path}>defaults delete com.apple.dock autohide-delay; killall Dock</code>
        </p>
        <h3 className={subheading}>Uninstall DockGrove</h3>
        <ol className={steps}>
          <li>Restore Apple Dock using one of the options above, and check that it is back.</li>
          <li>
            If this Mac is activated, choose <strong>Deactivate this Mac</strong> in{" "}
            <strong>Settings → Purchases</strong> to free its activation.
          </li>
          <li>
            If you connected Claude Code, select <strong>Remove DockGrove status line</strong> in{" "}
            <strong>Settings → Connections → Claude</strong>. This keeps your other Claude settings
            and puts back any custom status line.
          </li>
          <li>
            Choose <strong>Disconnect &amp; forget key</strong> for any API usage widget, and turn
            off <strong>Open DockGrove at login</strong>.
          </li>
          <li>
            Export any voice memos you want to keep, then quit DockGrove and move it from
            Applications to the Trash.
          </li>
        </ol>
        <p>
          Removing the app leaves your data on the Mac. To delete it too, remove{" "}
          <code className={path}>~/Library/Application Support/DockGrove</code>, which holds voice
          memos and imported usage figures, and{" "}
          <code className={path}>~/Library/Preferences/com.dylan.wavedock.plist</code>, which holds
          your notes, tasks, layouts and settings. Deleting them cannot be undone. Any permission
          entries left in Privacy &amp; Security can be removed there.
        </p>

        <h2 id="purchases">Purchases and recovery</h2>
        <p>
          Sales are not open yet. DockGrove is not accepting live payments, so there are no live
          purchases to recover or refund. The planned terms are in the{" "}
          <Link href="/terms">terms</Link>, and what the app and website collect is in the{" "}
          <Link href="/privacy">privacy information</Link>.
        </p>
        <p>
          When sales open, you will be able to get your license key again from{" "}
          <Link href="/recover">Restore purchase</Link> using your purchase email, with no new
          purchase needed. Recovery links expire after 15 minutes and work once. The recovery
          service is not deployed yet, so that page cannot send a link today.
        </p>
        <p>
          If you lose access to your purchase email, <a href={SUPPORT_CONTACT}>open an issue</a>{" "}
          asking for a private contact method. Do not include your license key or payment details.
        </p>
        <p>
          Accessibility information is on the <Link href="/accessibility">accessibility page</Link>.
        </p>

        <p className="support-link">
          <Link href="/">← Back to DockGrove</Link> · <a href={SUPPORT_CONTACT}>Support</a> ·{" "}
          <Link href="/privacy">Privacy</Link>
        </p>
      </main>
    </>
  );
}
