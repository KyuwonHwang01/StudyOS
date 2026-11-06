# Architecture

Native SwiftUI iPhone app, iOS 18+, Swift 6 strict concurrency, SwiftData, Charts and UserNotifications. No packages or remote services. Xcode filesystem-synchronized groups include new files in their app/test targets.

## Storage and transactions

Eight SwiftData models: Subject, StudyGoal, StudyTask, RecurrenceRule, StudyPlanBlock, FocusSession, DailyReview and UserPreferences. Explicit UUID references retain history when a parent is archived. The main-actor StudyStore retains its ModelContainer, disables autosave, saves mutations explicitly, rolls back failures, reloads collections and refreshes reminders. Quick-note edits use a lightweight explicit save. Launch failures never erase the database.

This revision adds optional skippedAt/reviewSourceID task fields and planBlockID/targetMinutes session fields. Existing SQLite stores use SwiftData lightweight migration; a real previous-version database fixture is tested for record/session preservation. Optional snapshot fields preserve old schema-1 JSON import compatibility. No reset or destructive migration exists. The fixture belongs only to the test target.

DraftRepository keeps uncommitted Codable values in a separate atomic, protected JSON sidecar. Writes debounce 400 ms and flush on close/background. Editor leases prevent delayed dismissal from resurrecting consumed drafts or overwriting a newer editor. Fieldwise merges preserve model changes outside the draft. Restore is visible and Start fresh discards it. Draft errors are surfaced; committed records and JSON backups are independent.

## Planning and lifecycle

PlanningEngine operates on immutable value snapshots. It respects local calendar days, availability, maximum, the daily study window, timed collisions, task/goal deadlines and subject balance. Work splits into quarter-hour blocks up to 60 minutes. Saved study reduces estimates; unfinished work keeps a minimum 15-minute next session. Daily capacity subtracts actual study plus the remaining confirmed reservation minutes, avoiding double-counting study linked to a block. Completed/canceled future blocks do not reserve capacity.

Proposal computation is cancellable and off the main actor. Review/edit/discard is local until explicit approval, which revalidates current work in one save. Confirmed blocks never move automatically. Direct Move edits the existing ID; multiple blocks require an explicit choice. Partially consumed and missed blocks retain historical records while the remainder gets one new reservation. Locked changes require explicit action. The legal-slot search checks capacity, time, deadlines and collisions for up to 30 days.

Completing a task settles current/past blocks and cancels future reservations. Maintenance repairs previous-version future blocks wrongly marked completed. Completion is explicit; an all-checked checklist only suggests it. Parent archive previews descendants, optionally pauses linked rules and archives pending work, and saves active time only as part of the disclosed confirmation. History survives. Goal completion with unfinished work offers archive or detach. Restoring pending work under a closed goal detaches it rather than reopening its parent silently.

Undo captures before/after value snapshots for lifecycle actions and lasts eight seconds. It restores only affected state, refuses conflicting newer edits/reservations, and rolls back on validation failure. Actual saved focus seconds are never undone. Reopen/recomplete preserves the first-completion ledger; immediate Undo reverses an accidental first drop.

Recurrence uses (rule UUID, local calendar day) identity over a rolling 14-day horizon, including completed/archived/skipped records in duplicate detection. Unfinished past habit occurrences become skipped history unless protected by an active session, a confirmed future plan or their own deadline. Ordinary one-off tasks retain their backlog. Habit editing updates eligible unstudied future occurrences; pausing can preserve explicit plans or remove them after confirmation, including locked blocks. Resume reuses occurrence IDs and preserves studied history.

## Focus and measurements

One global focus route owns the full-screen presentation. The session target is the chosen reservation's remaining minutes, otherwise the task's remaining estimate. Switching work explicitly saves the current session; no second active timer is created. Finish pauses; Back resumes only if it was running. Close preserves the session. Returning to a previous-version archived active session is allowed solely to settle that existing timer; starting new archived work is forbidden.

ClockProvider injects time. Elapsed = accumulated active seconds plus a nonnegative open interval. Pause excludes idle time. Finish requires positive active time and is status guarded. Root checkpoints every 15 seconds and on background. Ordinary backgrounding preserves timestamp timing; process recovery pauses at the last checkpoint, giving no unknown-time credit. A sudden kill can lose the checkpoint interval. Manual forward clock jumps can affect an open interval.

Actual study includes only finished active seconds, attributed to the local end day. Sub-minute labels use seconds; longer labels floor to whole minutes. Consistency requires ten saved minutes on a local day. Goal progress is task count, excluding skipped occurrences. Lifetime drops count first completion once, including archived/reopened history. Understanding is optional self-report, never an ability inference or automatic completion. A low rating offers an explicit, deduplicated review task without scheduling it automatically.

## Notifications and backups

NotificationService serializes cancellable rebuilds, stable IDs and up to 60 earliest reminders from approved timed blocks, active goals and the seven-day reflection horizon. Quiet-hour reminders are skipped. Saved reflections and already-started blocks suppress requests and stale delivered reminders. Cold-launch taps buffer until root routing is ready. Task/goal taps navigate to meaningful details, pause other active work, close forms after preserving drafts, and never start a timer automatically. Permission is requested on user opt-in; delivery belongs to iOS.

JSON schema 1 validates size/record limits, counts, IDs, references, occurrence keys, values and URLs before preview/confirmation. Merge is one transaction: existing IDs, preferences and consent win; incoming unfinished sessions are archived without time credit. Conflicting occurrence identity rejects the import. Optional additive fields decode older backups. These are merge backups of committed records, not device clones or draft exports.

## Performance and deferred scope

The personal app favors consistent whole-collection fetches over incremental caches. Very large multi-year datasets need pagination/profiling. No cloud sync, external calendar, PDF library, external AI, widget, Live Activity, Watch app, 3D ocean or iPad-specific UI is claimed. Resources are validated http/https links opened by the system. Hardware delivery, VoiceOver interaction and battery/frame profiling remain manual checks.

## Durable recovery decision

FocusSession optionally stores pendingRecoveryStartedAt and pendingRecoveryEndedAt, alongside its trusted accumulated time. Store recovery captures the bounded 1-minute–12-hour gap and pauses the session in the same save. The public recovery view is derived from that record rather than a volatile store property. Subsequent launches retain the original interval and do not extend it. Accept/decline use the same transaction and rollback boundary as the time change; failed writes preserve the candidate. Resume and finish require resolution, while explicit discard clears the fields without credit. Maintenance rejects finalizing a session with an unresolved interval, covering parent archive and other direct finish paths. Save operations default to ModelContext.save; an injected save operation enables deterministic failure/rollback verification.

Past confirmed blocks protected by an active timer still belong to their original calendar history. Only current/future confirmed reservations suppress a task's flexible scheduledDay, so an explicit carry-over displays on Today without moving or resetting its active block/session. Delivered Focus reminder cleanup is a pure tested predicate requiring notifications to be enabled and the matching session to be running.
