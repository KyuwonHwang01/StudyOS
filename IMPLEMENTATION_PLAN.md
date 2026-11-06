# StudyOS delivery

The native iOS project is StudyOS.xcodeproj at the repository root.

Implemented: local SwiftData transactions; subjects/goals/tasks/steps/resources/habits; Month/Week Flow; reviewed seven-day planning; real Focus time and recovery; Ocean statistics; granular reminders; atomic validated JSON merge; Water Flow motion; and the full approved usability audit.

The usability revision connects completion, scheduling, Focus, habits, archiving, drafts and notification routing through shared store actions. Historical study time remains stable, automatic behavior is limited to predictable cleanup/defaults, and substantive completion/review/planning choices stay explicit. See USABILITY_IMPLEMENTATION.md for the delivered behavior matrix and TEST_PLAN.md for verified evidence.

Production records are preserved through additive optional model migration. Compatibility is tested using an actual old SQLite store and old JSON. UI tests use an isolated debug-only store and draft file. Signing settings and user Xcode state are preserved when deploying source changes.

Completion criteria: source compiles; domain/persistence/migration and UI tests pass; small-device Dark/large text is inspected; unsigned physical-iPhone Release builds; verification logs and run instructions are retained. Real-device provisioning/install, actual notification delivery, VoiceOver and performance profiling remain clearly identified manual checks. No physical-phone execution or guarantee of defect-free software is claimed.
