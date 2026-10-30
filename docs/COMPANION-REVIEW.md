# Pixel companion implementation

The current local revision replaces the cutout rig completely with coherent full-body pixel artwork. The owner approved publication with the DockGrove rebrand. All nine species load `Assets/Companions/<slug>-pixel.png`, a 4×4 atlas: eight walking poses (dragon flight), four idle poses (dragon hover), then settling, curling and two sleeping poses. Fractional grid boundaries are rounded and the occasional 313/314-pixel source cell is padded onto one common canvas. Every fixed cell must have clear transparent margins.

The renderer caches all sixteen native CGImages. It computes one alpha union for the entire animal, applies that identical crop to every cell, and uses a shared scale and baseline. A one-time nearest-neighbor decode creates a shared 80-pixel logical grid; nearest-neighbor display preserves pixel edges. Exactly one full-body pose is drawn per frame; no separate limbs, head/body overlaps, rotations, ghost crossfades or body flattening remain. Species anatomy is baked into each complete illustration.

Horizontal velocity eases toward its target. Walking phase advances with actual visible pixel distance traveled relative to sprite width and species stride, so slowing movement also slows feet. The animal brakes before reversing; its full silhouette mirrors only when stationary. Idle breathing uses a slow two-pose cycle with brief 120 ms blinks around every 5.3 seconds, offset by species. Dragon hover uses all eight wing poses at a slower cadence than traveling flight. Sleep progresses through lowering and curling before the two breathing poses; waking reverses the settling poses. Hidden views pause and Reduce Motion freezes motion. The timer targets 60 updates per second, while illustrated pose changes use their own lower cadence. This is pixel sprite animation, not an assurance of measured display FPS.

Manual Play still triggers autonomous activity and care state, but the sixteen-frame contract does not contain bespoke grooming or play poses; these activities use idle artwork. Future additional poses should be authored as whole animals, never assembled by independently moving limbs.

## Validation

`Scripts/CheckCompanionAssets.swift` validates all sixteen nonempty fixed cells per animal, two clear edge pixels, and identical cropped dimensions, plus 32 mirrored native render bounds per animal (288 total). Motion tests simulate five minutes per species with deterministic seeds and check bounded travel, varied activities, eased acceleration, stationary gait, braking before turns, hidden pause, manual Rest/Wake and Reduce Motion.

The current review directory is `.build/pixel-redesign/`. Previous anatomical source and assets remain recoverable in its `previous/` directory. Earlier cutout videos and grids are superseded and must not be presented as the pixel revision. The same approved atlas artwork is included in the DockGrove website.
