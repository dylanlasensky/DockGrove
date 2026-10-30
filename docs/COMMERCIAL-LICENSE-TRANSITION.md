# Commercial transition — proposal for owner approval

Status: release-candidate proposal, not an enacted replacement for the MIT license.

## Evidence reviewed

The repository at baseline `97c9fed` contains the MIT license with copyright attributed to Dylan Lasensky. `git shortlog -sne HEAD` records 20 commits by `dylanlasensky`. This is evidence of recorded commit authorship, not proof that every contribution, image, or dependency is solely owned. Commit trailers, externally contributed code, and any private agreements still need owner confirmation before a proprietary release.

The historical 0.8 companion artwork README records image-generation prompts and repair passes. This non-pet publication retains the baseline companion renderer and full-animal pose sheets unchanged; the separate local pet redesign is excluded. Any retained generated artwork still has its own documented provenance; no claim is made that provenance automatically resolves every commercial-use or exclusivity question. Native frameworks are used under their platform terms. Any additional dependency introduced for the commercial release must retain its own required notices.

## Boundary

- Previously distributed DockGrove 0.8 source and binaries retain their MIT permissions. Existing recipients may continue exercising those rights subject to the notice requirement.
- The root `LICENSE` is retained. No history is rewritten and no notices are removed.
- The new payment service, activation flow, website changes and non-pet interaction work in this candidate are proposed additions. They have **not yet been placed under a final separate proprietary license**. Until the owner approves a legally coherent file/release boundary, do not claim that changing marketing text makes the checkout or its history closed source.
- A future proprietary distribution may include MIT-derived material with the required notices, while separately licensing owned additions and the commercial distribution offer. The owner must approve which files and versions carry which terms, including contribution rights. A paid purchase does not itself revoke source-license rights.
- Public repository visibility is unchanged. Previously public source and downloads cannot be made secret retroactively. A private future development repository is a separate owner decision, not part of this implementation.

## Proposed commercial offer

US $9.99 one time, current major version 1 and its maintenance updates, all nine included companions, three personal Macs. No recurring subscription and no automatic entitlement to future major upgrades. The centralized executable policy is `website/backend/product.mjs`.

The candidate activation policy uses a signed entitlement valid offline for 30 days; online refresh renews it if the license remains active. Purchase revocation prevents refresh; any refund or dispute suspends the purchase pending owner review. A cached offline entitlement remains usable until its signed expiration, so instant offline revocation is not promised. Restoration of Apple’s Dock and safe exit remain available regardless of license state.

## Before any live sale

Approve ownership and contribution rights; the commercial file/release boundary and notices; customer terms; actual seller identity; refund/support policy; taxes and geographic availability; privacy retention/deletion process. Obtain appropriate legal review where needed. No legal approval is inferred from implementation tests.

The website `terms.html` is visibly a draft. It must not be presented as accepted final commercial terms until approved. The payment backend is test-only, and a development app is never an appropriate artifact for commercial fulfillment.

## Connected-service commercial-use review

Checked October 29, 2026 against [Open-Meteo terms](https://open-meteo.com/en/terms) and [pricing](https://open-meteo.com/en/pricing). The hosted free API is restricted to non-commercial use; the provider expressly lists commercial products as commercial use. Commercial plans provide an appropriate customer endpoint and API key. The data license and hosted-service access terms are separate.

The commercial candidate must not call the free weather endpoint. Weather remains unavailable in that build until an owner-approved commercial service configuration exists. No paid weather plan was purchased or enabled. The website does not advertise weather as an active commercial feature.
