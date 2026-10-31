/** `<a class="skip" href="#main">Skip to content</a>` from the original pages. */
export default function SkipLink({ href = "#main" }: { href?: string }) {
  return (
    <a
      href={href}
      className="fixed -top-[100px] left-4 z-10 bg-[var(--bg)] p-3 focus:top-2"
    >
      Skip to content
    </a>
  );
}
