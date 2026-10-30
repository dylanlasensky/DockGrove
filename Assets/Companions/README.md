# DockGrove pixel companions

The current runtime uses the nine `*-pixel.png` files: transparent 4×4 atlases with sixteen complete-body poses, eight walking/flight frames, idle/blink and settling/sleep frames. See [implementation](../../docs/COMPANION-REVIEW.md) and `PIXEL-PROMPTS*` for the exact generation prompts. The old six-pose sheets below are retained as historical source assets and are not the current renderer.

## Historical artwork provenance

# Companion artwork

Generated individually with the built-in image generator, October 29, 2026. Transparent RGBA PNGs, 1536 × 1024; six 512 × 512 poses in row-major order. Runtime slices the original sheets once and caches them. The sixth frame is resting. No remote asset requests, common pad, emoji, or vector animal fallback.

## Miso

Cream-and-brown fluffy ragdoll, blue eyes, long silky fur. Poses: stepping left forepaw, standing tail curling, stepping right forepaw, grooming paw, head tilted meowing, curled sleeping. Same six-cell transparent gouache/colored-pencil specification below.

## Prompt template

Use case: illustration-story. One production sprite-sheet asset for a premium Mac companion. Exactly SIX EQUAL CELLS in a precise 3-column by 2-row grid, each cell 512 square within a 1536x1024 canvas. TRUE TRANSPARENT BACKGROUND, no painted backdrop or shared pad, no floor, no cast shadow, no text, no labels or border. Subject in every cell: the same SUBJECT. Distinct realistic animal anatomy; sophisticated detailed hand-painted gouache and colored-pencil storybook illustration, never vector, geometric, emoji, clipart or 3D. Six full-body poses left to right then next row: POSES. Center each full animal inside its own cell at consistent scale with generous transparent padding so no part crosses a cell boundary. Face right in three-quarter side view; maintain identical character design. Fine fur or scale detail, refined believable illustration.

## black-cat

SUBJECT: a slender black oriental shorthair cat, glossy midnight fur with cool highlights, large expressive green eyes, elegant long ears and long tail

POSES: stalk with left paw, stand looking back tail raised, stalk right paw, stretch forelegs, sit lifting a paw, curl asleep

## orange-cat

SUBJECT: a stocky orange tabby cat, richly striped ginger fur, white chin and paws, amber eyes, round expressive face

POSES: walk left forepaw, stand tail raised, walk right forepaw, roll playfully on back, sit meowing mouth open, curl asleep

## golden-dog

SUBJECT: a young golden retriever dog, richly textured golden fur, floppy ears, brown eyes, feathered wagging tail

POSES: trot left forepaw, sit alert, trot right forepaw, play bow tail up, lift paw happily tongue out, curl asleep

## husky

SUBJECT: a silver gray and white Siberian husky dog with blue eyes, distinct facial mask, upright ears and thick curled tail

POSES: walk left forepaw, stand proud, walk right forepaw, head lifted howling, play bow, curl asleep

## dragon

SUBJECT: an elegant small emerald green dragon, anatomically convincing fantasy creature, detailed overlapping scales, gold horns, expressive amber eyes, long sinuous tail, two broad batlike wings with turquoise membranes

POSES: hover wings high upstroke, hover wings half up, hover wings fully extended horizontal, hover wings sweeping downstroke, hover wings folded slightly returning up, perched curled asleep wings folded

## cow

SUBJECT: a young Holstein cow with distinct black white patches, pink muzzle, small warm horns and expressive brown eyes, finely painted coat

POSES: step left front leg, stand chewing, step right front leg, turn head licking nose, flick tail and ears, lie curled resting eyes closed

## rabbit

SUBJECT: a small white and warm gray lop rabbit with long soft floppy ears, velvety detailed fur, pink nose and dark lively eyes

POSES: crouch before hop, airborne gentle hop forelegs forward, land forepaws, sit grooming cheek with paw, sit ears perked nose twitch, curl asleep

## fox

SUBJECT: an elegant red fox with detailed russet coat, black stockings, cream chest, pointed ears, bushy white tipped tail and bright eyes

POSES: prowl left forepaw, stand looking curiously back, prowl right forepaw, crouch ready to pounce, leap with tail balancing, curl asleep nose under tail

## Layout repair pass

The built-in generator edited sheets with tight margins, preserving the original animal and six poses. Prompt: Keep the 1536x1024 canvas and 3 by 2 layout. Shrink every complete animal to the central 350x350 pixels of its own 512x512 cell, with at least 81 pixels of transparent padding on all sides. No tails, ears, paws, wings or horns may touch a cell boundary. Keep all six poses including the sleeping sixth pose, detailed illustrated style and true alpha. No grid lines, pads, floor, shadows, backdrop, text or new objects. Four initial repairs requested 55-pixel padding at 75 percent scale; the same preservation constraints applied.

The Fox sheet received a final repair: halve each pose to a 250-pixel maximum and center the six animals at the six cell centers. The renderer scales this padded sheet 2× to match the visible size of the other companions.
