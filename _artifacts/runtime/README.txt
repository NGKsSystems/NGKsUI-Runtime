ExecLedger Activity Monitor
===========================

This directory contains runtime activity logs generated while VS Code is open.

Files:
  activity_log.txt - Timestamped activity events (WINDOW_OPEN, IDLE_ENTER, etc.)

Event Types:
  WINDOW_OPEN  - VS Code activated/opened
  WINDOW_CLOSE - VS Code deactivated/closed (best effort)
  IDLE_ENTER   - No activity for 30 minutes
  IDLE_EXIT    - Activity resumed after idle period
  CMD          - ExecLedger command executed
  FILE_SAVE    - File saved within workspace

Manual Verification Checklist:
1. Open VS Code on any workspace
2. Verify WINDOW_OPEN event is logged immediately
3. Wait 31+ minutes with no activity - verify IDLE_ENTER
4. Run any ExecLedger command - verify IDLE_EXIT + CMD events
5. Save a file in workspace - verify FILE_SAVE event
6. Close VS Code - verify WINDOW_CLOSE event (best effort)

Log Format: [ISO_UTC_TIMESTAMP] EVENT_TYPE detail
Example: [2026-02-16T10:30:15.123Z] CMD execLedger.runMilestoneGates
