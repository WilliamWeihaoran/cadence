# iOS Guide

The iOS/iPadOS app is early/stubbed. Do not assume macOS feature parity.

## Working Rules

- Keep iOS-specific UI in this subtree.
- Use shared models/services/components where appropriate, but avoid importing macOS-only managers or AppKit assumptions.
- Prefer small placeholder-safe changes unless the task explicitly asks to build out iOS features.
- When adding real iOS behavior, check shared SwiftData models and platform conditionals carefully.

## Current State

The macOS app is the primary product surface. iOS files are mostly placeholders or early views.
