# Cadence App Review Notes

Use these notes as the starting point for the App Store Connect "Notes for Review" field.

Cadence is a native productivity app for tasks, notes, calendars, goals, habits, and focus planning.

Platform:
- Cadence currently targets macOS 26.1 or later.

Calendar access:
- Cadence requests Calendar access to show Apple Calendar events and to create, update, or delete scheduled task events when the user asks it to.
- Calendar access is optional, but calendar features are limited when permission is not granted.

Sign in with Apple:
- Sign in with Apple is optional.
- Local app use and iCloud sync do not depend on signing in with Apple.
- Users can sign out in Settings.
- Users can initiate account deletion in Settings > Account. The delete action opens the account and data deletion controls.

AI features:
- AI features are optional.
- AI requires the user to save their own OpenAI API key in Settings.
- Cadence sends selected note content to OpenAI only after the user explicitly runs an AI action, such as summarizing a note or extracting task drafts.
- Users can remove the saved API key in Settings.

Account and data deletion:
- Users can delete their Cadence account and data in Settings > Account or Settings > Data Safety.
- The delete flow removes Cadence-created content from the current store, removes local Cadence backups and pending restores, removes the saved OpenAI API key, and clears the local Apple account profile.

Sync:
- Cadence may sync user-created app data through the user's private iCloud database using CloudKit.

Push notifications:
- Cadence does not use push notifications.

Purchases:
- Cadence currently has no in-app purchases or subscriptions.

Ads and tracking:
- Cadence does not contain ads, third-party analytics, or tracking.

Widgets:
- Cadence includes widgets that read Cadence snapshots from the app group container.
