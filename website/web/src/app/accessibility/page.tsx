import Link from "next/link";
import type { Metadata } from "next";
import Brand from "@/components/site/Brand";
import PreviewBanner from "@/components/site/PreviewBanner";
import SkipLink from "@/components/site/SkipLink";

export const metadata: Metadata = {
  title: "Accessibility",
  description:
    "What DockGrove and its website support for VoiceOver, keyboard use, Reduce Motion, Increase Contrast, text size and Dark Mode, and the known gaps.",
  alternates: { canonical: "/accessibility" },
  openGraph: {
    title: "Accessibility — DockGrove",
    description:
      "What DockGrove and its website support today, the known gaps, and how to report a problem.",
    type: "website",
    url: "/accessibility",
    images: ["/assets/DockGrove-wordmark.png"],
  },
};

/** Every claim here is backed by app/Sources or website/web/src. Keep it that way when either changes. */
export default function AccessibilityPage() {
  return (
    <>
      <SkipLink />
      <PreviewBanner />
      <main className="section document" id="main">
        <Brand />
        <h1>Accessibility</h1>
        <p>
          What the DockGrove 1.0 release candidate and this website support today, and where they
          fall short. Updated November 6, 2026.
        </p>
        <p>
          This statement describes what the code does. It has not been audited, and DockGrove claims
          no conformance level or certification. A feature listed here is built in, but not every
          task has been tested with it. Automated tests read accessibility labels to find controls
          and check Reduce Motion for the companions. Hands-on accessibility testing on supported
          Macs is still an open release task, and no full VoiceOver run has been recorded.
        </p>

        <h2>VoiceOver</h2>
        <p>
          DockGrove is built with native SwiftUI and AppKit controls, which carry standard
          accessibility behavior. Custom controls have their own labels in the main places you would
          expect:
        </p>
        <ul className="my-4 list-disc space-y-2 pl-5 text-[var(--muted)]">
          <li>App tiles speak the app’s name and say when an app is unavailable.</li>
          <li>Dock page buttons and the settings button are named.</li>
          <li>The companion tile speaks the companion’s name and mood.</li>
          <li>Dock size controls in Settings report their current value.</li>
          <li>
            The file tray and AirDrop area offer named actions, such as removing a file or clearing a
            selection, so they do not depend on dragging.
          </li>
          <li>Decorative artwork is hidden from VoiceOver.</li>
        </ul>

        <h2>Keyboard</h2>
        <ul className="my-4 list-disc space-y-2 pl-5 text-[var(--muted)]">
          <li>
            <strong>⌥⌘D</strong> turns Dock hiding on or off from anywhere, the same shortcut as
            Apple’s Dock. It needs no Accessibility permission.
          </li>
          <li>
            The menu bar menu lists shortcuts for Settings (⌘,), hiding (⌥⌘D), showing or hiding
            DockGrove (⌘D) and refreshing usage (⌘R). Only ⌥⌘D is registered system-wide.
          </li>
          <li>
            The Applications launcher has a search field. Arrow keys move the selection, Return opens
            the result, and Esc closes the launcher.
          </li>
          <li>
            App stacks accept arrow keys, Return, Esc, and typing a letter or number to jump to a
            name.
          </li>
          <li>
            Esc closes Settings and the app windows panel. It also closes the open notch when that
            option is on, and cancels a window snap in progress.
          </li>
          <li>Text fields in widgets, such as tasks and the calculator, submit with Return.</li>
        </ul>
        <p>
          Reordering does not require dragging: app tiles have Move left and Move right, and widgets
          have Move earlier and Move later, in their menus. Widgets can also be added or removed with
          a click in Settings. The Windows widget moves a selected window with its controls, as an
          alternative to dragging it to a screen edge.
        </p>

        <h2>Reduce Motion</h2>
        <p>
          With Reduce Motion on in macOS, app tiles stop lifting and scaling on hover, and animated
          changes in Settings and the notch are removed. Companions stop walking and hold a still
          pose, and their drawing drops to one frame per second.
        </p>

        <h2>Contrast and transparency</h2>
        <p>
          With Increase Contrast on, the outline of the Dock becomes much stronger. Standard macOS
          controls follow the setting on their own. With Reduce Transparency on, the Dock uses a
          solid system background and widget surfaces become more solid.
        </p>

        <h2>Text size</h2>
        <p>
          The app does not offer a text size setting, and most of its custom text uses fixed sizes.
          Settings can make icons larger, from 32 to 64 points, and make the Dock taller, but this
          does not enlarge the text.
        </p>

        <h2>Dark Mode</h2>
        <p>
          The Automatic theme follows your macOS appearance. Pearl always stays light. Glass and
          Graphite always stay dark. The notch is always dark.
        </p>

        <h2>This website</h2>
        <p>
          Pages declare their language, and the home, terms, privacy and accessibility pages have a
          skip link. Links and controls show a visible focus ring. Reduced-motion settings turn off
          CSS animations and transitions. Document pages like this one follow your system’s light or
          dark setting, respond to increased-contrast and reduced-transparency settings, and size
          their text so it follows your browser’s font setting. Page zoom is not blocked on any page.
        </p>

        <h2>Known gaps</h2>
        <ul className="my-4 list-disc space-y-2 pl-5 text-[var(--muted)]">
          <li>
            <strong>VoiceOver.</strong> Some icon-only buttons rely on a tooltip instead of an
            explicit label. App tiles do not announce whether an app is running.
          </li>
          <li>
            <strong>Keyboard.</strong> No shortcut moves focus into the Dock, so opening a Dock tile
            from the keyboard alone has not been shown to work. Tile menus open by right-click,
            Control-click or a long press, and keyboard access to them has not been verified.
          </li>
          <li>
            <strong>Window snapping.</strong> Snapping to screen edges needs a pointer drag. Use the
            Windows widget instead.
          </li>
          <li>
            <strong>Motion.</strong> Reduce Motion does not yet cover everything. The Applications
            launcher, app stack panels and Dock reordering keep their short animations, and panels
            still fade in and out.
          </li>
          <li>
            <strong>Contrast.</strong> Among DockGrove’s own designs, Increase Contrast changes only
            the Dock outline. Widgets and cards do not change. Contrast over Glass varies with your
            wallpaper and has not been measured, and accent colors are your choice, so some may be
            harder to read.
          </li>
          <li>
            <strong>Text size.</strong> The app has no Dynamic Type or equivalent scaling, so its
            text will not grow with a system text size preference.
          </li>
          <li>
            <strong>Not evaluated.</strong> Voice Control and use without color cues have not been
            evaluated.
          </li>
          <li>
            <strong>Website.</strong> The home page has a fixed design. It does not follow your
            system’s dark setting, much of its text uses pixel sizes that ignore browser font
            settings, and it does not change for increased contrast. The purchase and recovery pages
            have no skip link. No automated accessibility audit is part of the site’s tests.
          </li>
        </ul>

        <h2>Report a problem</h2>
        <p>
          If something in DockGrove or on this site stops you from doing what you came to do, tell us
          through <Link href="/support">support</Link>. Say what you were trying to do, your macOS
          version, and any assistive technology you use. Do not post email addresses, license keys
          or payment information publicly.
        </p>
        <p className="support-link">
          <Link href="/">← Back to DockGrove</Link> · <Link href="/support">Support</Link> ·{" "}
          <Link href="/privacy">Privacy</Link> · <Link href="/terms">Terms</Link>
        </p>
      </main>
    </>
  );
}
