# TrustBridge Repo Instructions

These instructions are for any coding agent working inside this repository.

## Scope

- The git repository root is `parental_controls_app/`. Work from here, not from the parent `TrustBridge/` folder.
- Ignore sibling folders and loose files outside this repo unless the user explicitly asks for them.
- Never create screenshots, log dumps, XML dumps, temp databases, or scratch notes in the repo root.

## Product Guardrails

- This is an active Flutter/Firebase parental controls app, not a greenfield starter project.
- Parent and child screens are already established. Do not redesign, reorder, restyle, or rename screens unless the user explicitly asks for UI work.
- When fixing a bug on a screen, make the smallest viable change. Preserve navigation, copy, card order, toggles, and existing interaction patterns.
- Do not move a screen to a new route, merge screens, or split screens unless the task explicitly requires it.

## Architecture Guardrails

- Native Android VPN code is the owner of policy application. Flutter should fetch and hand off policy, not independently apply VPN rules.
- `children/{childId}/effective_policy/current` is the source of truth for effective policy.
- `children/{childId}/trigger/sync` is a wake/sync signal, not a second policy store.
- Avoid adding polling where an existing Firestore listener or native callback should be used.

## Workflow

- Start by reading `git status` and understanding in-progress changes before editing anything.
- If the tree is dirty, do not revert unrelated changes.
- For UI work, check `../app_design/` first if that sibling folder exists.
- If a matching design exists, implement against it. If no matching design exists, preserve the current UI instead of inventing a new one.
- Keep changes scoped. Do not mix cleanup, refactor, and UI restyling into a bug-fix task.

## Verification

- Before committing, run `flutter analyze`.
- Run targeted tests for changed areas when possible. Run `flutter test` for broad changes.
- If verification cannot be completed, say exactly what was not run and why.

## Git Hygiene

- Commit only from this repo.
- Use clear non-interactive git commands.
- Do not rewrite history unless the user explicitly asks.
- Do not commit generated files, local secrets, or device-specific artifacts.
