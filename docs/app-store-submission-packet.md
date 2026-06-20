# Cadence App Store Submission Packet

Last updated: June 17, 2026

This is the repo-tracked source for App Store Connect submission fields and review preparation. Keep it aligned with `docs/apple-release-readiness.md`, `docs/privacy.html`, `docs/support.html`, and `docs/app-review-notes.md`.

## App Store Connect Fields

- App name: Cadence
- Bundle ID: `com.haoranwei.Cadence`
- SKU: `cadence-macos`
- Category: Productivity
- Platforms: macOS
- Minimum OS: macOS 26.1
- Version: `1.0`
- Build: current project build number
- Encryption: uses only exempt or standard platform encryption; `ITSAppUsesNonExemptEncryption` is false.
- Support URL: `https://williamweihaoran.github.io/cadence/support.html`
- Privacy Policy URL: `https://williamweihaoran.github.io/cadence/privacy.html`
- Sign in required: no
- Demo account required: no
- Purchases: none
- Ads/tracking: none
- User-facing push notifications: none

## Review Notes

Paste `docs/app-review-notes.md` into App Store Connect "Notes for Review" and update only if behavior changed for the submitted build.

Required notes:

- Calendar access is optional and permission-gated.
- Sign in with Apple is optional.
- Account/data deletion is available in Settings, Account and Settings, Data Safety.
- AI is optional, requires the user's own OpenAI API key, and sends selected note content only when the user runs an AI command.
- CloudKit sync may use the user's private iCloud database.
- Cadence has no purchases, subscriptions, ads, tracking, or user-facing push notifications.

## Privacy Details

Use `docs/apple-release-readiness.md` as the privacy-label source of truth. The current App Store Connect privacy answers should include:

- Data linked to the user for app functionality: name, email address, user ID, and other user content.
- No data used to track the user.
- No tracking domains.
- Calendar access described as permission-gated app functionality.
- Optional OpenAI processing disclosed in the privacy policy and review notes.

Do not answer "Data Not Collected" for the app target because Cadence stores and may sync user-created productivity content.

## Screenshot And Metadata Checklist

Prepare screenshots that show actual product functionality, not placeholder/sample-only screens:

- Today or timeline planning surface.
- Notes/editor surface.
- Calendar integration surface.
- Goals or habits surface.
- Settings privacy/data safety surface.
- Widget examples if widgets are highlighted in metadata.

Metadata must avoid claims that are not true for the build:

- Do not claim iOS feature parity.
- Do not claim AI runs locally.
- Do not claim Calendar access is required.
- Do not claim push notifications are a user-facing feature.
- Do not mention MCP integrations unless they are part of the shipped app experience.

## Pre-Upload Gates

- Run the verification commands in `docs/apple-release-readiness.md`.
- Confirm support/privacy URLs are publicly reachable.
- Confirm App Store Connect capabilities match entitlements: iCloud/CloudKit, Sign in with Apple, App Groups, Calendar, widgets, and remote notification capability for CloudKit sync.
- Confirm the submitted archive uses distribution signing and does not contain debug-only test frameworks.
- Confirm `CadenceMCPServer` and `plugins/cadence-mcp` are not embedded in the app archive.
