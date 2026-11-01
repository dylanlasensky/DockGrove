/** Accent swatches and appearance preview from the original home.js / app.js. */

export interface Swatch {
  /** Hex color written to `--accent`. */
  color: string;
  /** Accessible name, e.g. "Pearl accent". */
  label: string;
}

export const SWATCHES: readonly Swatch[] = [
  { color: "#f5f5f7", label: "Pearl accent" },
  { color: "#79dbb8", label: "Mint accent" },
  { color: "#92b9ff", label: "Blue accent" },
  { color: "#c4abff", label: "Lilac accent" },
  { color: "#efab95", label: "Coral accent" },
];

export const DEFAULT_ACCENT = SWATCHES[0].color;
export const DEFAULT_ACCENT_NAME = "Pearl. A little understated.";

/** `document.documentElement.style.setProperty('--accent', color)` */
export function applyAccent(color: string): void {
  document.documentElement.style.setProperty("--accent", color);
}

/** Caption shown after picking a preset swatch. */
export function swatchCaption(swatch: Swatch): string {
  return swatch.label.replace(" accent", "") + ". Make it your own.";
}

/** Caption shown after picking a custom color. */
export function customAccentCaption(color: string): string {
  return "Your custom accent. " + color.toUpperCase();
}

export type Appearance = "auto" | "light" | "dark";

export const APPEARANCES: readonly { value: Appearance; label: string }[] = [
  { value: "auto", label: "Automatic" },
  { value: "light", label: "Light" },
  { value: "dark", label: "Dark" },
];

/** Mirrors app.js: `auto` removes `data-appearance`, others set it on `<html>`. */
export function applyAppearance(value: Appearance): void {
  if (value === "auto") document.documentElement.removeAttribute("data-appearance");
  else document.documentElement.dataset.appearance = value;
}
