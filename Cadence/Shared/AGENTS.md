# Shared Guide

This folder contains cross-platform design tokens, shared components, hover styles, and date/time helpers.

## Working Rules

- Only put code here when it is genuinely shared across platforms or intentionally platform-conditional.
- Use `Theme` tokens and existing shared components before introducing new one-off styling.
- Use `DateFormatters` and `TimeFormatters`; do not create inline date formatters in views.
- Preserve hover semantics in `CadenceHoverStyles.swift`: task/event/bundle hovers should preserve original color and lift/brighten rather than gray out.
- Keep shared components small and dependency-light. Avoid pulling macOS-only managers into shared code.

## Component Expectations

- Components should be reusable through explicit props and bindings.
- Avoid hidden global state unless the existing component pattern already uses it.
- Match the app's compact, desktop-focused visual language.
