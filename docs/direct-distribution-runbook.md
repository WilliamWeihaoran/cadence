# Cadence Direct Distribution Runbook

Last updated: June 17, 2026

Use this only for direct macOS distribution outside the Mac App Store. The Mac App Store path remains primary. Direct distribution requires Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper validation, and a developer-managed update/support path.

## Preconditions

- Apple Developer Program membership is active.
- Developer ID Application signing identity is installed.
- App-specific password or notarytool keychain profile is configured for Apple's notary service.
- Release archive is built from a clean tree and tested with the same verification commands used for App Store readiness.
- Hardened Runtime remains enabled.
- App Sandbox remains enabled unless a future direct-only build has a documented reason to differ.

## Archive And Export

Create an archive:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild archive -project Cadence.xcodeproj -scheme Cadence -destination 'generic/platform=macOS' -derivedDataPath /tmp/cadence-archive-$$ -archivePath build/Cadence.xcarchive
```

Export with a Developer ID export options plist:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -exportArchive -archivePath build/Cadence.xcarchive -exportPath build/export-developer-id -exportOptionsPlist build/ExportOptions-DeveloperID.plist
```

The export options plist is intentionally not committed here because team IDs, signing identities, and notarization credentials can vary by release machine. Keep it outside source control if it contains machine-specific or secret-adjacent values.

## Signing Validation

Inspect the exported app:

```sh
codesign -dvvv --entitlements :- build/export-developer-id/Cadence.app
codesign --verify --deep --strict --verbose=2 build/export-developer-id/Cadence.app
spctl -a -vv --type execute build/export-developer-id/Cadence.app
```

Expected release properties:

- Signed with Developer ID Application for direct distribution.
- Hardened Runtime flag is present.
- App Sandbox entitlement is present.
- App group, iCloud/CloudKit, Calendar, network client, Sign in with Apple, and widget extension entitlements match the release intent.
- Nested app extension signatures validate.

## Notarization

Package the app before notarization:

```sh
ditto -c -k --keepParent build/export-developer-id/Cadence.app build/Cadence.zip
```

Submit and wait:

```sh
xcrun notarytool submit build/Cadence.zip --keychain-profile "CadenceNotaryProfile" --wait
```

Staple and validate:

```sh
xcrun stapler staple build/export-developer-id/Cadence.app
xcrun stapler validate build/export-developer-id/Cadence.app
spctl -a -vv --type execute build/export-developer-id/Cadence.app
```

If notarization fails, inspect the notary log first and separate code-signing, nested-code, entitlement, and malware-scan issues before changing app behavior.

## Direct-Distribution Responsibilities

- Provide a public download page, privacy policy, support URL, and contact method.
- Provide update delivery outside the Mac App Store.
- Provide clear uninstall and data deletion instructions.
- Keep the same privacy disclosures as the App Store build unless the direct build differs.
- Re-run signing, notarization, stapling, and Gatekeeper checks for every release artifact.
