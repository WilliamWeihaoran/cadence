# Cadence App Review Notes

Use these notes as the starting point for the App Store Connect "Notes for Review" field.

Cadence is a native productivity app for tasks, notes, calendars, goals, habits, and focus planning.

Platform:
- Cadence targets macOS 26.1 or later and iOS/iPadOS 26.2 or later from a single app target.
- macOS is the fuller surface. Where a feature is available on only one platform, these notes say which.

Calendar access:
- Cadence requests Calendar access to show Apple Calendar events and to create, update, or delete scheduled task events when the user asks it to.
- Calendar access is optional, but calendar features are limited when permission is not granted.

Sign in with Apple:
- Sign in with Apple is optional, and is offered on macOS only. iPhone and iPad have no Cadence account, so Settings has no Account category there.
- Local app use and iCloud sync do not depend on signing in with Apple.
- Users can sign out in Settings > Account on macOS.
- On macOS, Settings > Account also offers account deletion; its delete action opens the account and data deletion controls in Settings > Data Safety.

AI features:
- AI features are optional.
- AI requires the user to save their own OpenAI API key in Settings.
- Cadence sends selected note content to OpenAI only after the user explicitly runs an AI action, such as summarizing a note or extracting task drafts.
- Users can remove the saved API key in Settings.

Account and data deletion:
- On macOS, users delete their Cadence account and data in Settings > Account or Settings > Data Safety.
- On iPhone and iPad, users delete their Cadence data in Settings > Data Safety. There is no Account category on those platforms because Sign in with Apple is macOS-only, so there is no separate account to delete.
- Both platforms run the same deletion: it removes Cadence-created content from the current store, removes local Cadence backups and pending restores, removes the saved OpenAI API key, and cancels pending Cadence notifications. On macOS it additionally clears the local Apple account profile.
- Deletion is confirmed before anything is removed. macOS asks for confirmation in a modal dialog that lists what will be deleted. iPhone and iPad open a confirmation sheet that lists the same items and requires the word DELETE to be typed before the destructive button becomes active.
- Because Cadence syncs through the user's private iCloud database, deletions propagate to the user's other devices. Apple Calendar events that already exist in Calendar are managed by Calendar and are not deleted.

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
