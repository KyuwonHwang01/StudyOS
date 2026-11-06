# Usability delivery map

Automatic behavior is limited to predictable cleanup and helpful defaults. Study history remains intact; creating reviews, completing work, moving reservations and accepting plans remain explicit choices.

| Situation | Delivered behavior | Verification |
| --- | --- | --- |
| Task completed early | Future reservations/reminders are released; completed work folds into history | Transaction tests; checklist/Undo UI |
| Completion/archive mistake | Eight-second Undo; newer edits and reservation conflicts are protected; saved focus time stays saved | Lifecycle/conflict tests; archive and completion UI |
| Move existing work | Single block opens directly; multiple blocks show a chooser; Add another is explicit | Identity/partial/missed-block tests; Move UI |
| No usable default time | Legal-slot search respects capacity, conflicts and deadlines | Planning/slot tests |
| Finish then Back | Previously running timer resumes; paused timer stays paused | Focus UI; session clock tests |
| Close Focus or start other work | Return preserves session; switch explicitly saves current time; empty time is discarded | Focus/switch domain tests and UI |
| Focus on one block of a large task | Target is the block's remaining duration, not full task estimate | Partial allocation tests; 30-minute block / 120-minute task UI |
| Missed routine | Quiet skipped history, no automatic debt; active/explicit future/deadline-protected work stays available | Recurrence lifecycle tests |
| Pause/resume routine | Keep confirmed blocks or explicitly remove; no duplicate instances on resume | Habit reconciliation tests |
| Archive subject/goal | Preview affected work; optionally include children/rules; preserve sessions and stop related plans/reminders | Parent archive and Undo tests |
| Complete a goal | Shortcut when tasks done; otherwise choose archive remaining or detach as independent tasks | Goal transaction tests |
| Add task to goal | Context retained; saving under closed goal explicitly reopens it; restore alone does not reopen parent | Goal/restore tests; contextual UI |
| Subject/goal selection | Empty dropdown avoided; inline creation; searchable existing choices auto-return; goal fills empty subject, conflict asks once | Task draft tests; inline creation/goal-link UI |
| Paste URL or type last checklist step | Save includes pending inputs; inline validation and URL dedup | Resource tests and pending-link UI |
| Close/kill during editing | Separate persistent draft, visible restoration, Start fresh, fieldwise merge; Save consumes the draft | Sidecar/merge tests; close/relaunch UI |
| Understanding rating | Optional self-report; 5/5 alone never completes; 1–2 offers explicit once-per-session review, unscheduled | Rating/review tests |
| Checklist all checked | Suggest completion; preserve an explicit override across Back | Finish UI |
| Reflection saved / block started | Remove corresponding pending and stale delivered reminders | Notification generation tests |
| Notification tapped on cold launch | Buffer then navigate to relevant detail; preserve drafts, pause other work, never auto-start | Routing/buffering tests; hardware tap remains manual |
| Very large text | Full appearance value; choosing a mode saves and returns immediately; all-tab Dark layout checked | Small-device screenshot review and appearance UI |
| Existing installation | Additive optional SwiftData fields; old JSON accepted; no production reset | Real prior SQLite fixture and old-JSON tests |
| Availability/month calendar | Maximum follows raised availability; full Month/Week navigation | Domain and UI regression tests |

See TEST_PLAN.md for final executed counts, device details, retained logs and remaining hardware checks. Test-only records and migration fixtures are never seeded in production.
