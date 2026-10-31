/** The nine pixel-art companions shown in #companions, in original order. */

export interface Companion {
  /** Sprite sheet file name under /assets/companions/. */
  file: string;
  /** Name used in the aria-label ("…, animated pixel-art companion"). */
  ariaName: string;
  heading: string;
  tagline: string;
}

export const COMPANIONS: readonly Companion[] = [
  { file: "miso", ariaName: "Miso", heading: "Miso", tagline: "Siamese curiosity" },
  { file: "black-cat", ariaName: "Black cat", heading: "Black cat", tagline: "A little midnight company" },
  { file: "orange-cat", ariaName: "Orange cat", heading: "Orange cat", tagline: "A warm-hearted tabby" },
  { file: "golden-dog", ariaName: "Golden retriever", heading: "Golden retriever", tagline: "Always happy to see you" },
  { file: "husky", ariaName: "Husky", heading: "Husky", tagline: "A bright-eyed explorer" },
  { file: "dragon", ariaName: "Dragon", heading: "Dragon", tagline: "A little flight of fancy" },
  { file: "cow", ariaName: "Cow", heading: "Cow", tagline: "Taking the day slowly" },
  { file: "rabbit", ariaName: "Rabbit", heading: "Rabbit", tagline: "A soft spot for small hops" },
  { file: "fox", ariaName: "Fox", heading: "Fox", tagline: "Quietly curious" },
];

export function companionSprite(companion: Companion): string {
  return `/assets/companions/${companion.file}.png`;
}
