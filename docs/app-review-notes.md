# Cadence App Review Notes

Use these notes as the starting point for the App Store Connect "Notes for Review" field.

Cadence is a native productivity app for tasks, notes, calendars, goals, habits, and focus planning.

Platform:
- Cadence targets macOS 26.1 or later and iOS/iPadOS 26.2 or later from a single app target.
- macOS is the fuller surface. Where a feature is available on only one platform, these notes say which.

Calendar access:
- Cadence requests Calendar access to show Apple Calendar events and to create, update, or delete scheduled task events when the user asks it to.
- Calendar access is optional, but calendar features are limited when permission is not granted.

Reminders access:
- Cadence requests Reminders access to show the user's incomplete Apple Reminders in the Cadence Inbox, and to mark a reminder complete when the user checks it off there. Reminders are read through Apple's EventKit APIs.
- Marking a reminder complete is the only change Cadence makes to a reminder, and only in a reminders list that allows modification. Cadence never creates a reminder, never edits a reminder's title, notes, or dates, and never deletes one.
- Reminders access is requested separately from Calendar access; granting one does not grant the other. It is optional, and the rest of the app works without it — the Inbox simply shows no reminders.
- On both macOS and iOS/iPadOS, reminders appear in Settings > Reminders and in the Inbox. Reminders are held in memory for display only; Cadence does not copy them into its own store or sync them through iCloud with Cadence data.

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
- Cadence uses push notifications for exactly one purpose: CloudKit's silent sync notifications. The app ships the `com.apple.developer.aps-environment` entitlement (`development` in Debug, `production` in Release) and registers for remote notifications at launch on macOS, so CloudKit can tell the app that the user's private iCloud database changed and app data should be refreshed. Cadence builds macOS and iOS/iPadOS from one app target with one entitlements file, so the entitlement is present on both platforms; both sync through that same private database.
- These pushes are silent. They carry no alert, sound, or badge; Cadence has no remote-notification payload handling of its own, and no Cadence-operated server sends anything — the only sender is Apple's CloudKit. There are no marketing or promotional push notifications.

Local notifications:
- Separately from push, and through a different mechanism, Cadence schedules local notifications with `UNUserNotificationCenter`: a reminder at a task's scheduled start time, a reminder on a task's due date, and a daily reminder for habits that have a reminder time set. These are planned on-device from the user's own Cadence data and are never sent from a server.
- Apple Calendar events are deliberately excluded, because those already have their own alarms in Calendar.
- Local notification authorization is requested in exactly one place — Settings > Notifications — and never at first launch. A single toggle in that section governs all Cadence reminders.

Purchases:
- Cadence currently has no in-app purchases or subscriptions.

Ads and tracking:
- Cadence does not contain ads, third-party analytics, or tracking.

Widgets:
- Cadence includes widgets that read Cadence snapshots from the app group container.
