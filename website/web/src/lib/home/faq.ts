/** FAQ entries for #questions. Started from the original index.html; keep answers true to the current app. */

export interface FaqItem {
  question: string;
  answer: string;
}

export const FAQ: readonly FaqItem[] = [
  {
    question: "Does it replace the macOS Dock?",
    answer:
      "Replacement mode places DockGrove at the bottom edge and hides Apple’s Dock while DockGrove is running. It restores your original Dock preferences when you quit or choose Restore Apple Dock. Native Handoff, arbitrary notification badges and system-wide reserved window space are not fully reproduced. You can also use DockGrove without enabling replacement mode.",
  },
  {
    question: "Which Mac do I need?",
    answer:
      "DockGrove targets macOS 14 or later and includes Apple silicon and Intel binaries. This early-access build has been tested on the development Mac; every macOS version and monitor arrangement has not been certified.",
  },
  {
    question: "What will DockGrove cost?",
    answer:
      "The proposed price is $9.99 once for major version 1, its maintenance updates, and up to three personal Macs. No subscription. Future major upgrades are separate. Checkout is disabled while the commercial release is prepared. Existing copies of the earlier MIT release keep their original permissions.",
  },
  {
    question: "What do the AI widgets measure?",
    answer:
      "Codex reports account allowances. Claude shows every limit your plan reports, including the five-hour window, the week, and per-model limits such as Fable. Gemini CLI reports session token activity from a JSON report, not remaining chat quota. OpenAI and Claude API widgets show organization tokens; Cursor reports team activity. Each connection identifies its data source and setup requirements. API spend is separate from a ChatGPT subscription allowance.",
  },
  {
    question: "Can I change the size of the Dock?",
    answer:
      "Yes. Set Dock length from 35% to 100% of your display, or let it fit its contents, then adjust height and icon size in Studio. Press ⌥⌘D to turn hiding on or off.",
  },
  {
    question: "Which Macs get the notch shelf?",
    answer:
      "The notch shelf appears on Macs whose built-in display has a camera housing. DockGrove detects it from the display itself, and you can turn the shelf off in Appearance settings. Everything else works on any Mac running macOS 14 or later.",
  },
  {
    question: "Where does my data go?",
    answer:
      "Notes and voice memos stay on your Mac. API keys stay in Keychain. Connect only the widgets you want, and grant permissions when a feature needs them.",
  },
  {
    question: "Is this ready for everyone?",
    answer:
      "It is an early-access preview. The app is not Apple-notarized yet, some integrations require account setup, and it does not offer every feature of commercial Dock apps. Read the setup guide and known limitations before installing.",
  },
];
