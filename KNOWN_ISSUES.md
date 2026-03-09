# Known Issues

## Tab status does not reliably reflect ongoing terminal activity

Terminal-backed AI tabs such as Claude and OpenCode do not yet show the expected "ongoing" status for the full duration of in-app activity. Surface updates and terminal output are detected, but the tab indicator still does not consistently match the user's expectation of when the underlying app is actively working versus waiting for input.

Current state:
- Tab activity tracking exists and reacts to command entry and surface updates.
- The status indicator still needs refinement to reflect real ongoing app activity more accurately.
- This is currently unresolved and should be revisited before relying on tab status as a precise execution signal.
