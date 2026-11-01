# Native in-app purchases

The Xcode app uses StoreKit 2 with two non-consumable products. US base prices are $4.99 and $9.99; purchase buttons always use Apple's localized `Product.displayPrice`.

| Access | Product ID | One-time US price | Includes |
| --- | --- | --- | --- |
| Free | None | Free | App launching, app search, Focus, Tasks, clock, spacers, separators, and Dock/layout settings |
| Plus | `com.dylan.wavedock.plus` | $4.99 | All everyday widgets, including weather, calendars, music controls, notes, files, clipboard, system information, calculators, and utilities |
| Full Access | `com.dylan.wavedock.full` | $9.99 | Everything in Plus, all companions, GitHub, and every AI usage widget, including Codex |

`app/Sources/WidgetCatalog.swift` is the exhaustive widget-to-tier mapping. Full Access alone unlocks everything; a Plus purchase is not required first. These are separate products, not subscription tiers: buying Full Access after Plus costs the full displayed price, with no automatic credit for Plus. The app explains this to Plus owners and prevents offering already-included products. Connected third-party services may require their own accounts or subscriptions.

## Ownership and access

`PurchaseManager` loads products, checks each known product's latest verified StoreKit transaction, rejects revoked or unverified transactions, listens for transaction updates, finishes handled transactions, and refreshes access when the app activates. The latest-transaction API is appropriate here because both products are permanent non-consumables. It is not a subscription-expiration implementation. Restore Purchases explicitly calls `AppStore.sync()` and rebuilds ownership. Failed restores preserve the previously verified access state.

There is no preference or license-key switch that grants StoreKit access. Saved and imported layouts retain their widget choices, but the Dock filters those choices against current ownership. Removing a purchase stops the affected active monitors and clears clipboard history if its access is lost. Refund of Full Access falls back to Plus if Plus is still owned, otherwise Free. Core Dock controls and Quit remain available.

The Xcode target enables `DOCKGROVE_STOREKIT` in both Debug and Release. The separate shell development build remains an unrestricted source-testing artifact, and the existing `--commercial` shell build retains the website license system. Do not distribute either shell artifact as the StoreKit app. Website licenses are not silently converted into Apple purchases.

## Local testing

1. Open `app/DockGrove.xcodeproj`.
2. Select **DockGrove StoreKit Testing** and Run to try the $4.99 / $9.99 products without charges. Only that scheme attaches `DockGrove.storekit`; the regular **DockGrove** scheme uses Apple's real environment.
3. In Xcode, use **Debug → StoreKit → Manage Transactions** to inspect/reset local purchases.

Run the automated StoreKit tests:

```sh
xcodebuild -project app/DockGrove.xcodeproj \
  -scheme 'DockGrove StoreKit Testing' -destination 'platform=macOS' \
  -derivedDataPath app/.build/purchase-tests test
```

The tests use an isolated app host with its own bundle identifier, not the running Dock or the user's preferences. They exercise real StoreKitTest transactions: prices and widget tiers, each purchase, relaunch, restore, duplicate-purchase prevention, cancellation/failure/retry, pending approval, refunds, invalid signatures, and product-load failure/retry. All nine tests passed on October 30, 2026. This is local StoreKit evidence, not proof of an App Store sandbox or production sale.

## App Store setup

The app's existing bundle identifier is `com.dylan.wavedock.development`, team `G563Q4D3XW`. Its matching App Store Connect app is **DockGrove**, Apple ID **6829005855**. The suffix is part of the registered identifier; changing it requires a matching App Store app and provisioning configuration.

The Paid Apps Agreement was accepted by the account holder. Both non-consumable records were saved in App Store Connect on October 30, 2026:

- **DockGrove Plus**, Apple ID **6829005609**: $4.99 US base price, English (US) description, all 175 regions selected.
- **DockGrove Full Access**, Apple ID **6829006160**: $9.99 US base price, English (US) description, all 175 regions selected; **Prepare for Submission**.

These are draft products, not live purchases. Review screenshots and app submission remain outstanding.

The first in-app purchases must be submitted with an app version. Product records, localized descriptions, base prices, availability, and review screenshots must be complete before submission. App metadata, a distributable Mac App Store build, sandbox compatibility, and review remain release work; this native Dock currently uses an unsandboxed development target. Do not interpret successful local purchase tests as App Store approval.

References: [Apple: create non-consumable purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases), [latest transaction](https://developer.apple.com/documentation/storekit/transaction/latest(for:)), [StoreKit transactions](https://developer.apple.com/documentation/storekit/transaction).
