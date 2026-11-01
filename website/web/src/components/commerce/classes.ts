// Tailwind equivalents of the base.css rules the purchase/recover documents use.
// Values mirror the computed styles of website/public/{purchase,recover}.html.

/** `.button` plus the 44px hit-target, hover/active/disabled and focus rules. */
export const button =
  "inline-flex min-h-11 min-w-11 cursor-pointer items-center justify-center gap-3 rounded-full border-0 bg-[var(--button)] px-6 py-[15px] text-[0.9375rem] leading-[1.55] font-semibold text-[var(--button-ink)] no-underline hover:brightness-[1.12] enabled:active:brightness-90 disabled:cursor-not-allowed disabled:opacity-65 focus-visible:outline-3 focus-visible:outline-offset-5 focus-visible:outline-[var(--focus)]";

/** `.form-card button{margin-top:12px}` */
export const cardButton = `${button} mt-3`;

/** `.full` */
export const full = "w-full";

/** `.document p` — every paragraph in a document is 0.9375rem, muted, 1em margins. */
export const p = "my-[1em] text-[0.9375rem] text-[var(--muted)]";

/** `.fine` inside `.document`: size is overridden to 0.9375rem, line-height stays 1.65. */
export const fine = `${p} leading-[1.65]`;

/** `.status-message` */
export const statusMessage = `${p} rounded-[10px] bg-[var(--soft)] p-[14px] [overflow-wrap:anywhere]`;

/** `.license-output` */
export const licenseOutput =
  "rounded-[10px] bg-[var(--soft)] p-[18px] [font-family:ui-monospace,monospace] [overflow-wrap:anywhere] select-all";

/** `.form-card h2` (h2 base rules with margin-top:0) */
export const h2 =
  "mt-0 mb-7 text-[1.625rem] leading-[1.07] font-[510] tracking-[-0.045em] [overflow-wrap:anywhere]";

/** `.document h1` */
export const h1 =
  "my-6 text-[3.25rem] leading-[1.04] font-[530] tracking-[-0.065em] [overflow-wrap:anywhere] max-[600px]:text-[2.625rem]";

/** `.form-card` */
export const formCard =
  "mx-auto my-[35px] max-w-[560px] rounded-[20px] border border-[var(--line)] bg-[var(--surface)] p-[30px] max-[600px]:p-[22px]";

/** `label` */
export const label = "block text-[0.8125rem] font-medium";

/** `input[type=email]` with the `--control-line` border and visible placeholder. */
export const input =
  "my-2 w-full min-w-0 rounded-[9px] border border-[var(--control-line)] bg-[var(--surface)] p-3 text-[var(--ink)] placeholder:text-[var(--muted)] placeholder:opacity-100 focus-visible:outline-3 focus-visible:outline-offset-5 focus-visible:outline-[var(--focus)]";

/** Links inherit color and keep the browser underline the original relied on. */
export const link =
  "underline focus-visible:outline-3 focus-visible:outline-offset-5 focus-visible:outline-[var(--focus)]";

/** `.section.document` */
export const document =
  "mx-auto max-w-[800px] px-[30px] pt-[70px] pb-[100px] [overflow-wrap:anywhere] max-[850px]:px-6 max-[850px]:pt-[70px] max-[850px]:pb-[70px] max-[600px]:px-5 max-[600px]:pt-[58px] max-[600px]:pb-[58px]";
