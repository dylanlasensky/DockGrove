# Signing handoff for Malcolm

Apple certificate changes and notarization are intentionally deferred. No Apple private key or certificate was created, imported, used or modified by the commerce implementation.

The current local build uses ad-hoc signing. Build modes are explicit: `--development` produces `WaveDock.app` with a development bundle ID; `--commercial` validates the public license origin/key/key ID and produces `WaveDock-Commercial.app`; `--commercial-qa` produces a separate locked-state test artifact that must never be sold. Only `--commercial` is an input for a paid release. Keychain and app preferences are separated for development/QA. The future commercial artifact must compile with `WAVEDOCK_COMMERCIAL`, include the public licensing configuration described in `COMMERCE.md`, and pass offline license verification plus sandbox activation. Never ship a development build as the paid download.

After the owner approves the release identity, add Developer ID signing and hardened runtime in a protected release workflow, review required entitlements for the actual app behavior, notarize and staple, and test Gatekeeper installation on a Mac without development setup. Keep all Apple credentials in protected CI secrets/keychain and preserve separate test/development artifacts. Only the final verified commercial ZIP belongs in the private release bucket.

Review before signing: app and website version alignment, licenses/notices, universal architectures, receipt configuration, nested executable signing, optional permission descriptions, startup registration, exact Apple Dock restoration, and the paid app's permanent access to Quit and Restore Apple Dock even when activation fails.

Useful checks after signing: `codesign --verify --deep --strict <app>`, `codesign -dvv --entitlements - <app>`, `spctl --assess --type execute --verbose <app>`, and `xcrun stapler validate <app>`. Those are release checks for Malcolm; they have not been claimed as passed for a Developer ID release.
