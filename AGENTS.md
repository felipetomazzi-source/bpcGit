# bpcGit working instructions

Read `docs/HANDOVER.md` and `docs/SPEC.md` before implementation work.

The user authorizes committing and pushing completed project tasks to `main`
without asking again. Run the checks appropriate to the change, commit the
task's changes, and push to `origin/main` before reporting completion. Preserve
unrelated work and never commit credentials or local MCP configuration. Report
any check or push failure clearly.

Read and check SAP code through the ADT MCP only. Do not write SAP source
directly through ADT or other tools. The user authorizes pulling this project's
pushed code into SAP through abapGit without asking again. Use the configured
project repository and branch; preserve unrelated SAP changes and report any
pull failure or conflict. Activation and browser testing remain with the user
unless separately authorized.
Run `python tools/abapgit_fmt.py` after changes under `src/`, then run it with
`--check`. Target ABAP 7.52, UI5 1.52, and ES5 JavaScript.

## Testing UI changes

Test frontend changes locally before asking the user to test in SAP. Do not
test the UI by hand in Chrome; use the harness, which runs the real Component,
view and controller on OpenUI5 1.52.48 with a read-only mock API (no SAP, Git
or logins).

1. `node --test tests/*.test.cjs` for controller logic. Add or extend a
   `tests/*.test.cjs` file for new logic; existing files show how to load the
   controller with `vm` and mock UI5 controls.
2. Once per checkout: `npm ci --ignore-scripts --prefix tests/opa`.
3. `node tests/opa/run.cjs` runs the OPA5 journey and the embedded-component
   suite headless in the installed Chrome or Edge (`BPCGIT_BROWSER` overrides)
   and exits non-zero on failure, printing the failed assertions. It starts
   and stops `tests/opa/server.cjs` itself, or reuses one on port 4173.
4. Update the fixtures in `tests/opa/server.cjs` and the journey when an API
   or the UI changes; keep the expected assertion count in
   `tests/opa/README.md` current. Never point the harness at SAP.
5. For a new dialog or control, extend `tests/opa/embedded.js` or the journey
   so the run covers it. UI5 1.52 ignores a plain `element.click()`; use OPA
   `Press` actions or dispatch pointer/mouse events.

Only after these pass: push, pull into SAP, and ask the user to check the real
system. Browser testing against SAP itself stays with the user.
