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
