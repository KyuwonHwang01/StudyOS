# Water Flow

Native SF typography, semantic Dynamic Type styles, 20–24 pt page/card spacing, 26 pt cards, capsule primary actions, 44 pt minimum interactive controls, and a native four-tab bar.

Adaptive colors: background #F5F5F1 / #131A1C, surface #FFFFFF / #253134, text #20292B / #F0F4F1, secondary #58676A / #AFBCB9, accent #476C70 / #B0CDCB, mist #A9C4C2 / #6C9291, sea glass #8BAEA6 / #9BC2B4, warning #976047 / #DBA28A. Secondary and warning tones are slightly darker than the reference palette for readable text. Charts supplement color with numeric values and labels. Light, Dark, and Follow System are persisted settings.

Components in DesignSystem/WaterDesign.swift: WaterCard, FlowButton, LiquidProgressBar, DropletBadge, DeadlineChip, PriorityChip, EmptyStateView, SectionHeading, RippleCompletionEffect, WaterSurfaceView, FocusSource and FocusPresentation.

Progress fills ease smoothly over 0.55 seconds. Completion has a small 0.3-second ripple. Today/Flow launch points use the native iOS 18 zoom transition into the shared Focus presentation. Reduce Motion disables the custom zoom, ripple, fill interpolation, and surface movement. The water surface is two bounded sine paths at at most 10 fps; it pauses offscreen, in the background, under Reduce Motion and in Low Power Mode. There is no full-screen particle or physics simulation. The app icon uses the same colors and geometry, with no external image assets.

Layouts scroll rather than force fixed phone dimensions. Week selection scrolls horizontally. Forms use native date pickers, sheets, keyboard handling, toggles and accessible actions. Timers have explicit spoken labels and do not announce every ticking second as a live region. Checklists expose completion state; completion buttons include task names. Larger text expands cards and form rows.

Real-device VoiceOver, battery profiling, and optical tuning remain manual acceptance checks. Simulator screenshots and automated UI flows provide initial layout verification.

Usability follows the same restraint: quiet folded completed/skipped history; contextual task actions; one Focus presentation with an inline Finish phase; native inline validation; and a short Undo notice. Important relationships (goal subject, affected archived work, saved time on switching) are explained at the decision point. No celebratory overlay blocks navigation, no modal tutorial interrupts normal work, and self-rating does not trigger hidden scheduling.

Month is the default calendar with Week available. Compact day numbers cap only their own font size; selected-day labels and timelines retain Dynamic Type. Forms include explicit keyboard Done and retain drafts on close. Long content scrolls. The smaller-device Dark/large-text check and normal Light screenshots are documented in TEST_PLAN.md.
