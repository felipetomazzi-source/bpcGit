# bpcGit working instructions

Read `docs/HANDOVER.md` and `docs/SPEC.md` before implementation work.

The user authorizes committing and pushing completed project tasks to `main`
without asking again. Run the checks appropriate to the change, commit the
task's changes, and push to `origin/main` before reporting completion. Preserve
unrelated work and never commit credentials or local MCP configuration. Report
any check or push failure clearly.

Read and check SAP through the ADT MCP only. Never write SAP directly: the user
pulls pushed changes through abapGit, activates them, and tests in the browser.
Run `python tools/abapgit_fmt.py` after changes under `src/`, then run it with
`--check`. Target ABAP 7.52, UI5 1.52, and ES5 JavaScript.
