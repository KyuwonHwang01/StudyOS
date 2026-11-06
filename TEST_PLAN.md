# Verification and acceptance

Raw logs, screenshots, result bundles and validation-only harnesses referenced below are local evidence and are intentionally excluded from this public repository. The committed verification summary records their outcomes; the shared app test targets can be run from Xcode.

## Environment

Xcode 27.2 (27B52), Swift 6 strict concurrency, iOS 27.2 SDK; deployment target iOS 18.0. Main simulator: iPhone 17 Pro, runtime named iOS 26.4 (reports OS 26.4.1, build 23E254a). Small-device layout: iPhone 17e, Dark appearance and accessibility-extra-extra-large. Screenshot review caught a truncated appearance value; the final layout uses a wrapping current-value label and one-tap selection that returns immediately. The affected appearance/all-tab paths are rechecked after that visual correction. iPhone Release builds use the physical iOS target with signing disabled. No Apple Account or provisioning settings were changed.

UI automation uses a separate debug-only SwiftData store and separate draft sidecar. Reset flags are scoped to that test store. Test-only study names, screenshots and old database fixtures never populate production. Production records were not reset.

## Main regression

`StudyOSPolishFinalAcceptanceResults`: **94 passed, 0 failed, 0 skipped**: 82 Swift Testing domain/persistence cases plus 12 XCTest UI cases. Durable summary, full log and Light screenshots: `Verification/UsabilityPolish/`.

Domain coverage includes deterministic planning and capacity; partial actual/reserved accounting; collision/deadline/slot validation; direct move identity and missed/partially studied history; availability 214 → 300 and maximum bounds; month grid/week starts/leap years/DST; completion, archive, Undo and newer-change conflicts; routine expiration/protection/pause/resume/deduplication; parent/goal lifecycle; one active session, positive-time saving, pause/recovery/switching and block targets; optional rating/review deduplication; notification suppression/cold routing; draft leases/merges/corrupt-data recovery; atomic backups and old JSON; and actual old SQLite lightweight migration.

Main UI cases cover onboarding, task/focus/history/relaunch; every tab; availability and inline goal creation; Month/Week navigation and selected-day task; direct archive/Undo; checklist completion override across Back and Undo preserving saved time; draft close/relaunch/consumption, inline subject and pending URL Save; existing goal filling subject; Move opening the same reservation and a 30-minute target for a 120-minute task; and Finish/Back/Close retaining the session.

The final full run includes both directions of inline subject/goal conflict resolution and optional rating → explicit review creation. Those checks caught a presentation ordering problem: related choices are now applied after sheet dismissal, and conflicting links resolve inline on the task form. Save waits for resolution; no competing popups or arbitrary delays are used. All 12 UI cases passed together after this correction. Final Release compilation is also performed from the deployed Desktop project.

## Reproduce

Open StudyOS.xcodeproj, select the shared StudyOS scheme, and press Cmd-U. For CLI verification, choose installed simulator names from `xcrun simctl list devices available` and replace the example names below when necessary. Each result bundle path must be new. Boot the small-device simulator before changing its appearance.

```sh
xcodebuild -project StudyOS.xcodeproj -scheme StudyOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/StudyOSPolishDerived -parallel-testing-enabled NO \
  -resultBundlePath /tmp/StudyOSNewResults CODE_SIGNING_ALLOWED=NO test

xcrun simctl ui "iPhone 17e" appearance dark
xcrun simctl ui "iPhone 17e" content_size accessibility-extra-extra-large
xcodebuild -project StudyOS.xcodeproj -scheme StudyOS \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -derivedDataPath /tmp/StudyOSPolishDerived -parallel-testing-enabled NO \
  '-only-testing:StudyOSUITests/StudyOSUITests/testAllTabsAtCurrentAccessibilitySettings' \
  -resultBundlePath /tmp/StudyOSNewLargeTextResults CODE_SIGNING_ALLOWED=NO test

xcodebuild -project StudyOS.xcodeproj -scheme StudyOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/StudyOSDesktopReleaseDerived \
  CODE_SIGNING_ALLOWED=NO build
```

## Evidence and limitations

`Regression-summary.json` retains Xcode's counts, devices, warnings and result without removing warnings. `Regression.log` and Light screenshot manifest identify the main run. Dark/large-text captures and their summary/log are retained alongside it. Interrupted/failed diagnostic runs are not represented as passing evidence. The real prior-version SQLite fixture is included only in StudyOSTests; its expected record counts/names are asserted after migration.

The simulator reports intermittent `Invalid frame dimension (negative or non-finite)` runtime warnings during keyboard/presentation transitions without a source location. App-calculated progress widths are bounded and the tested screens/actions pass; the warning has not been attributed conclusively. The raw result/log is preserved. Xcode also emits an AppIntents metadata message because this app has no AppIntents dependency. These are not concealed as a warning-free run.

Still manual: physical iPhone signing/install and performance/battery/motion profiling; VoiceOver reading order and interaction; real notification permissions, delivery, banner taps and revocation; third-party Files providers; Reduce Motion and Low Power behavior measured on hardware; very large multi-year datasets and large manual clock jumps. No iOS 18 simulator runtime is installed, so minimum-target compilation is verified with the current SDK while execution is on the installed newer runtime. No real-phone execution is claimed.

Manual acceptance: create subjects/goals/tasks/steps/resources; close and restore drafts; change a linked subject and resolve its goal; move/lock a block; preview and approve a plan; focus/pause/finish/back/switch/save; complete early and undo; archive a parent with its related work and undo; pause/resume a habit; optionally add a low-rating review; save a reflection; inspect history/Ocean; export/import twice; and verify denied notifications or invalid backups never erase records. Repeat the essential flow with the intended phone's largest text size, VoiceOver and Reduce Motion.

Prior baseline and availability/calendar/goal revision evidence remains in its original Verification folders. This document describes the current usability revision.

Final small-device result: **2 passed, 0 failed** in `StudyOSPolishLargeTextFinalResults`: all-tab Dark/large-text navigation and appearance selection/save/automatic return. The final Settings screenshot shows the complete Follow system value. Across the main run and the post-visual-fix check there are **95 distinct scenarios: 82 domain/persistence and 13 UI**; the all-tab scenario is executed on both devices. Both final unsigned iPhone Release builds (staging and deployed Desktop) are recorded in this revision's verification folder.

## Durable recovery / overnight carry-over correction

The previously failing unanswered-recovery reopen and active previous-day carry-over cases now pass. The full domain suite is **103 passed, 0 failed**, including injected acceptance/decline save failures, successful retry without double credit, SQLite migration with the new optional fields, old JSON decoding/import, preservation of original history/timer across carry-over and Undo, and delivered reminder cleanup for paused/finished/discarded/disabled states.

Acceptance result: `StudyOSRecoveryFixAcceptanceResults`, **107 passed, 0 failed** (103 domain + 4 UI). The new RecoveryUITests performs actual termination intervals of 62 seconds, reopens without answering and terminates/reopens again, accepts once, verifies no duplicate recovery after relaunch, then repeats for decline. Existing Focus Back/resume, completion/Undo and block-target UI cases also pass.

Boundary UI result: `StudyOSRecoveryBoundaryFinalResults`, **2 passed, 0 failed**. A separate validation copy seeds an active prior-day block and simulates one storage failure. Screens verify Today includes the carried task, Undo retains its timer/history, failed recovery offers a visible retry, and retry persists exactly once. The validation-only fixture/writer hook is excluded from the app; its reproduction files are stored as text under Verification/RecoveryCarryOver/BoundaryHarness.

Portable logs, result summaries, manually inspected screenshots and source hashes are in `Verification/RecoveryCarryOver/`. `Desktop-Release.log` records the final unsigned iPhone Release build from the actual Desktop project. Signing settings and the production database are not reset. Existing simulator keyboard/presentation warnings remain in the unmodified raw logs, as documented above.
