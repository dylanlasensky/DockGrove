/**
 * Shared Tailwind class strings that reproduce the original home.css element and
 * utility rules (`.section`, `.eyebrow`, `.fine`, `h2`, `h3`, `p`, `.button`, `.text-link`).
 * Kept here so every Home B section renders identically without relying on global CSS.
 */

/** `.section` + `section{scroll-margin-top}` + `.section{overflow-wrap:anywhere}` */
export const sectionClass =
  "scroll-mt-[100px] px-[max(6vw,24px)] py-[125px] [overflow-wrap:anywhere] max-[700px]:px-6 max-[700px]:py-20";

/** `.eyebrow` */
export const eyebrowClass =
  "m-0 mb-[26px] text-[0.6875rem] font-[650] leading-[1.55] tracking-[.15em]";

/** `.fine` (color overridden per section where the original does) */
export const fineClass = "m-0 text-[0.75rem] leading-[1.65]";

/** `.fine` default color; sections that recolor `.fine` pass their own `text-[…]` instead. */
export const fineMutedClass = `${fineClass} text-[var(--muted)]`;

/** `h1,h2` base + `h2` size */
export const h2Class =
  "m-0 text-[clamp(44px,6.3vw,84px)] font-semibold leading-[1.04] tracking-[-.065em]";

/** `h2 span` (final override color) */
export const h2SpanClass = "text-[#737980]";

/** `h3` */
export const h3Class = "m-0 text-[1.6875rem] font-bold leading-[1.15] tracking-[-.035em]";

/** `p` */
export const pClass = "m-0 leading-[1.55]";

/** `em` */
export const emClass =
  "not-italic font-normal tracking-[-.07em] [font-family:Georgia,'Times_New_Roman',serif]";

/** `.section-intro` */
export const sectionIntroClass = "mx-auto max-w-[1120px]";

/** `.section-intro>p:last-child` (with the accessible color override) */
export const sectionIntroLedeClass =
  "m-0 mt-6 max-w-[510px] text-[1.25rem] leading-[1.55] text-[#59625c] max-[700px]:text-[1.0625rem]";

/**
 * `.button` with the later accessibility overrides (border 0, wrap, min size, disabled).
 * Colors are NOT included: Tailwind resolves same-property utilities by stylesheet order,
 * so each use passes its own `bg-[…] text-[…] hover:bg-[…]` (default: ink / white / #3a3d43).
 */
export const buttonClass =
  "inline-flex min-h-[44px] min-w-[44px] items-center justify-center gap-8 rounded-[30px] border-0 px-[25px] py-[17px] text-center text-[0.875rem] leading-[normal] font-[550] [transition:transform_.25s,background_.25s] hover:-translate-y-0.5 active:not-disabled:brightness-[.92] disabled:cursor-default disabled:opacity-75 disabled:hover:translate-y-0";

/** `.text-link` without its font size (for sections that resize it, e.g. `.download`). */
export const textLinkBaseClass =
  "inline-flex gap-4 leading-[normal] font-[550] no-underline hover:underline hover:underline-offset-[5px]";

/** `.text-link` */
export const textLinkClass = `${textLinkBaseClass} text-[0.875rem]`;

/** `a,button,input,summary:focus-visible` */
export const focusRingClass =
  "focus-visible:outline-3 focus-visible:outline-[#3461a4] focus-visible:outline-offset-[5px]";

/** `.card-kicker` */
export const cardKickerClass = "text-[.6875rem] font-semibold tracking-[.08em]";
