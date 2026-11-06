# Recorded verification results

Verified with Xcode 27.2 (27B52), Swift 6 and the iOS 27.2 SDK. Minimum deployment target: iOS 18.

## Latest recovery and carry-over revision

- Main acceptance: **107 passed, 0 failed** (103 domain/persistence tests and 4 UI tests).
- Additional boundary UI validation: **2 passed, 0 failed**, using a separate validation copy with a prior-day active block and an injected save failure.
- Unsigned physical-iPhone Release build from the final project: **BUILD SUCCEEDED**.

Coverage includes durable recovery across repeated termination, transaction rollback and retry without duplicate credit, legacy SQLite migration, old JSON compatibility, carry-over and Undo preserving timers/history, and removal of delivered Focus goal reminders. The recovery UI test uses real 62-second termination intervals.

## Earlier usability acceptance

- Main suite: **94 passed, 0 failed** (82 domain/persistence and 12 UI tests).
- Small-device Dark/large-text follow-up: **2 passed, 0 failed**, with one repeated scenario.

These are historical run counts, not a claim that every UI scenario was rerun after the latest correction. See [TEST_PLAN.md](../TEST_PLAN.md) for commands, scope and limitations.

## Evidence policy

Raw result bundles, logs, screenshots, device identifiers and validation-only harnesses remain on the development Mac and are ignored by Git. The production app and its committed test targets do not include the injected validation hooks. StudyOSTests/Fixtures/Legacy.store is a deliberately constructed test database containing test-only records for migration checks.

Known simulator keyboard/presentation warnings are documented in TEST_PLAN.md. No physical-iPhone execution, actual notification delivery or VoiceOver validation is claimed.
