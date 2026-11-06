# StudyOS

An offline native iPhone study planner built with SwiftUI, SwiftData, Swift Charts and UserNotifications. Deployment target: iOS 18. No external packages, API keys, accounts, tracking, paid services or cloud synchronization.

This repository contains the application, shared Xcode scheme, unit tests and UI tests.

## Run in Xcode

1. Open `StudyOS.xcodeproj` in Xcode with the iOS SDK installed. This revision is verified with Xcode 27.2 (27B52), Swift 6, and the iOS 27.2 SDK; minimum deployment target is iOS 18.
2. Select the shared **StudyOS** scheme and an installed iPhone simulator.
3. Press **⌘R**. Complete onboarding. Templates and sample plans are optional; a clean launch has no invented work or statistics.
4. Use the books button or Settings → Subjects, goals, tasks & habits to manage studies. Add a task on Today, or use Flow → Shape your next seven days → review/edit → Confirm plan. Focus saves actual time; task completion is a separate choice.
5. Run tests with **⌘U**. UI tests use their own debug-only database and never reset the normal app database.

## Install on your iPhone

1. Connect the iPhone to the Mac by cable, unlock it, and accept **Trust This Computer** if prompted. The phone must run iOS 18 or later.
2. In Xcode → Settings → Accounts, add your Apple Account if it is not already configured. Credentials stay in Xcode; nothing is placed in this project.
3. Select the blue project icon → **TARGETS: StudyOS** → **Signing & Capabilities**. Enable **Automatically manage signing**, choose your **Team** (a Personal Team can be used for local development), and change `com.kyuwon.studyos` to an identifier unique to you if signing reports a conflict.
4. Select your connected iPhone in Xcode's run destination menu. Allow Xcode to prepare device support if needed.
5. Enable **Developer Mode** on the iPhone if prompted (Settings → Privacy & Security → Developer Mode; restart and confirm). If iOS asks you to trust the development profile, follow its prompt in Settings → General → VPN & Device Management.
6. Press **⌘R**. Leave the phone unlocked for the first install. Subsequent launches can use the StudyOS icon while the development signing remains valid.

Physical-device signing and installation require your Apple Account/device interaction and were not performed here. No App Store or TestFlight deployment is configured.

## Features

- Today: local date, honest completion/actual/planned metrics, next-up Focus, task completion, deadlines and a persisted evening reflection.
- Flow: Month/Week calendar and selectable days, confirmed/locked/missed block states, manual timed or flexible blocks, conflict checks, editable seven-day recommendations, explicit approval/discard, and preserved history.
- Studies: subjects/goals/tasks with priority, estimates, date-only or timed deadlines, editable steps, notes, URL resources and recurring weekday habits. Archive/restore retains history.
- Focus: real timestamp timer, pause/resume/finish/discard, one active session, quick notes, steps, links, optional understanding rating, explicit task completion, durable recovery and duplicate-save guards.
- Ocean: saved active time, distinct first-completion drops, seven-day consistency, subject breakdown, item-count goal progress, month/seven-day periods, session history, and explicitly rule-based coaching.
- Settings: system/light/dark, per-weekday availability, editable study window, opt-in granular notifications and quiet hours, JSON export and validated import preview.
- Water Flow: adaptive desaturated palette, rounded cards, native zoom into Focus, subtle completion ripple, animated progress, and a bounded water surface that pauses with Reduce Motion, Low Power Mode, backgrounding and offscreen state.

## Data and backup rules

Use Settings → Export JSON backup to save a copy in Files. Import validates the entire file before confirmation and adds only new UUIDs in one transaction. Existing IDs, local preferences and notification consent win. Incoming unfinished sessions are archived without credit; occurrence identity conflicts reject the whole import. No file is imported automatically. Export includes schema, timestamps, counts and all records. Maximum import: 20 MB / 100,000 records. Deleting the app can erase its local store.

A forced quit restores an active session **paused at its last saved checkpoint**. Unknown time after that checkpoint is not automatically credited. While foregrounded, checkpointing runs every 15 seconds, including outside Focus; moving into the background also checkpoints. Ordinary background/foreground timing continues from timestamps. Backward clock changes are clamped; a large manual forward clock adjustment can affect an open interval.

Lifetime drops count a task's first completion once and retain that history when reopened or archived. Actual time counts only finished sessions and excludes pauses. Sub-minute time is shown in seconds. Longer duration labels floor to whole minutes. Goal progress uses item count. Consistency means at least 10 saved active minutes on a local day. No metric estimates ability or pretends to be AI.

## Verification

See [TEST_PLAN.md](TEST_PLAN.md) for reproduction commands and [Verification/README.md](Verification/README.md) for recorded results. Raw machine-specific logs, result bundles and screenshots are retained locally and excluded from Git. `ARCHITECTURE.md`, `DESIGN_SYSTEM.md`, and `IMPLEMENTATION_PLAN.md` describe engineering choices and scope.

Deferred: cloud sync, PDF library, external calendars, widgets/Live Activities/Watch, 3D water, iPad-specific layouts and external AI integrations. Real-device performance, VoiceOver reading order, actual reminder delivery and Files-provider interactions need device QA.

## Availability, calendar, and goal improvements

Daily maximum automatically rises when daily availability (onboarding) or any weekday's availability (Settings) rises above it. It cannot be edited below the highest available day. Reducing availability keeps a higher maximum you already chose. Existing stored preferences with a smaller maximum are repaired on launch without changing your study records.

Flow now opens with a full **Month** calendar; **Week** is available in the segmented control. Arrows move by the selected period, Today returns to the current date, and tapping a day updates the timeline and the default day for new tasks/blocks. Dots indicate tasks and diamonds indicate active goal deadlines. Week starts, adjacent-month dates, leap days and daylight-saving changes use the local Calendar. Each date exposes its full spoken date and task/deadline counts. The compact grid caps only its day-number font; the selected-day heading and timeline retain full Dynamic Type scaling.

New task shows an optional Goal section. An empty goal list has no dropdown: it explains the empty state and offers **Add goal**. Creating a goal there keeps the task draft and automatically selects the new goal. Existing goals remain selectable, and tasks can still be saved without a goal. No database reset is required.

## Everyday convenience

- Completing a task removes its future reservations and their reminders. Completed work folds into history. Complete/archive/remove-block actions offer Undo for eight seconds; conflicting newer changes are protected. Saved focus time is retained when undoing completion.
- Move opens an existing reservation, preserving its identity. Multiple reservations show an explicit chooser; adding another is a separate action. Moving partially studied or missed work preserves its historical portion. A legal-slot shortcut respects availability, conflicts and deadlines.
- Focus uses the selected block's remaining minutes. Finish → Back resumes a previously running timer. Close keeps the session available. Switching tasks asks to save the current time in the same flow. Empty sessions can be discarded without inventing time.
- Habit occurrences expire quietly into skipped history, without a catch-up backlog. An active session, explicit future reservation or task-specific deadline protects unfinished work. Pausing a habit lets you keep confirmed blocks or explicitly remove them. Resuming avoids duplicate occurrences.
- Parent archive previews affected work, lets you include related pending tasks/habits, releases their blocks, and retains history. Finishing a goal with remaining work offers archive or keep as independent tasks. Restoring a task does not silently reopen its archived goal.
- Create subjects/goals inline. Choosing a goal fills an empty subject; conflicting choices require one explicit resolution. Add tasks directly from a goal. Pasted links and pending checklist entries are included by Save, without an extra Add step.
- Appearance shows the full current mode at large text sizes. Selecting a mode saves it and returns immediately.
- Closing an editor retains an uncommitted local draft. Restored drafts are labeled and can be discarded with Start fresh. Draft merging preserves external completion/checklist/habit changes. Successful Save consumes the draft so it cannot reappear. Drafts use a separate local sidecar and are not part of committed-data JSON backups.
- An all-checked checklist suggests completion on Finish, and you can turn it off. Understanding 1–5 is optional self-assessment: even 5/5 does not itself complete a task. Ratings 1–2 offer an optional, once-per-session 15-minute review task. No review or calendar reservation is added without your choice.
- Saved evening reflections and already-started block reminders are suppressed, including stale delivered notifications. Reminder taps open the relevant work without starting a timer automatically.

See `USABILITY_IMPLEMENTATION.md` for the behavior and verification map. Existing SwiftData records migrate through additive optional fields; an actual prior-version SQLite store and old JSON backups are covered by compatibility tests. No database reset is used for production.

## Recovery and overnight carry-over fixes

An unanswered recovery interval now lives on its FocusSession in SwiftData. Its start/end stay fixed across further app termination, and accepting or declining clears the interval in the same transaction as the time update. A failed save leaves the choice available; Focus shows an inline retry action. Unreviewed time is never credited automatically, and resuming/finishing waits for that decision. Explicit session discard clears the pending choice without counting its time. The recovery UI test uses two real 62-second termination intervals.

Moving an active previous-day task to today now includes it in today's task list while retaining the original block and timer. Undo restores its previous date. Pausing a session removes its delivered goal reminder as well as its pending request; finishing, discarding or disabling reminders also removes that delivered reminder.

The two new recovery fields are optional and migrate without a database reset. Older JSON remains importable. Backups preserve pending recovery metadata, but imported unfinished sessions remain discarded without time credit and do not revive the pending choice.
