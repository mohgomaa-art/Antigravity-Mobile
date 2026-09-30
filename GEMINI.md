# Antigravity Autonomous Execution & Project Rules

## CRITICAL RULE: Autonomous Execution (Auto-Proceed / Zero-Block)
- **NEVER pause or freeze execution by calling interactive question tools (`ask_question`) unless explicitly requested by the user.**
- **Auto-Proceed by Default**: When architectural decisions, design choices, library selections, or implementation trade-offs arise, **pick the best, most robust, industry-standard option autonomously and proceed immediately**.
- **Do not ask multiple-choice questions**: Interactive question modals block mobile clients, ADB streaming, and remote wireless stations. Calling `ask_question` leaves remote sessions waiting indefinitely on a blocking modal on the host PC.
- **Decision Transparency**:
  1. Select the recommended default.
  2. Implement the solution cleanly and completely.
  3. Briefly state the rationale in your final turn response so the user can steer or modify it in subsequent turns if desired.
- **Autonomous Error Resolution**: When tests, builds, or scripts fail, diagnose and fix them immediately without asking for permission.
- **Monochrome Design Integrity**: In all UI work, adhere strictly to `AgyTheme` monochrome dark/light styling (#000000, #0C0C0E, #141416, #18181B, #27272A, #A1A1AA, #FFFFFF). Never introduce saturated accent colors (blues, purples, greens, oranges).
