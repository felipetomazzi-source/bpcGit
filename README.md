# bpcGit

Version control for SAP BPC 10.1 (NW) content in Git: EPM workbooks, logic
scripts, transformation and conversion files, Data Manager packages and
package links. The app is a UI5 BSP application, installed with abapGit into
package `ZBPC_GIT` on the development system.

- Specification: [docs/SPEC.md](docs/SPEC.md)
- abapGit objects: `src/`
- Byte-format helper: `python tools/abapgit_fmt.py` (run with `--check` before
  committing; it normalises BOM, CRLF and the 255-column WAPA padding)

After pulling with abapGit, the app runs at
`/sap/bc/ui5_ui5/sap/zbpc_git/index.html?sap-client=<client>`.
Use this UI5 path, not `/sap/bc/bsp/sap/...`: the BSP runtime rejects host
names without a domain (`CX_FQDN`), such as `vhcalnplci`.

## REST API

Base path: `/sap/bc/zbpc_git` (handler `ZCL_BPC_GIT_HTTP`)

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/ping` | Caller, system, client and the installed abapGit version |
| GET | `/environments` | BPC environments the user may access |
| GET | `/config?environment=<id>` | Repository setup of an environment |
| POST | `/config` | Save it (`environment`, `url`, `branch`) |
| POST | `/connection` | Test the connection (`environment`; optional `user`, `token`) |
| POST | `/workbooks` | Tracked files in BPC and Git with their status (`environment`; optional `user`, `token`) |
| POST | `/commit` | Commit selected files (`environment`, `message`, `commit` = head seen, `paths` one per line; `user`, `token`) |
| POST | `/restore` | Write a Git version into BPC (`environment`, `commit` = head seen, `paths`; optional `version`, `depth`, `user`, `token`) |
| POST | `/history` | Changes to one item (`environment`, `path`; optional `depth`, `user`, `token`) |

Git login works as in abapGit: requests go without credentials first. When the
Git host wants a login, the API answers 403 with `"authRequired": true` and the
app asks for user and personal access token, keeps the token in the browser tab's `sessionStorage`,
and retries. Only the user name persists in `localStorage`; credentials are
never stored on the server.

POST requests must carry `X-Requested-With: XMLHttpRequest` (jQuery sets it), so
a form on another website cannot change data with the user's session.

## Build steps

1. BSP app shell (done)
2. REST handler with `/ping`, shown on the start page (done)
3. Config table `ZBPC_GIT_REPO` and setup screen (done)
4. abapGit wrapper, Git login as in abapGit, "Test connection" (done)
5. Workbook list with Git status; sync table `ZBPC_GIT_STATE` (done)
6. Commit selected files (staging) (done)
7. Restore selected files from Git (implemented; latest discard-change cases
   await acceptance testing)
8. File history and restore of an older version (implemented; SAP acceptance pending)

## Data Manager content

Packages and links appear in their own Type filters. Packages are XML files
under `DATAMANAGER/PACKAGES/<group>/`; links are under `DATAMANAGER/PACKAGELINKS/`.
Team packages use the team path. Package scripts have one XML line per step;
link IDs are removed in Git and restored using the target system's ID.
Generated XML has no BPC last-change timestamp. Duplicate names or sanitized
path collisions are unsupported; resolve these names before tracking them.
The REST endpoints are unchanged. See specification section 3.4.

After deployment through abapGit, check package and link listing and Type
filters, commit representative XML, restore an edited script/link in BPC,
and confirm a second refresh shows Unchanged. Also test a team package and
a package using its chain's default script. SAP/browser acceptance is pending.

Transformation and conversion workbooks each appear once in the overview.
Their status, commit, and restore include the paired definition automatically.
A restore succeeds for the pair together; a failure rolls back the pair.

Select one item and choose History to inspect its earlier versions. Load older
history extends the recent branch range to at most 1,000 commits. Restoring an
older version changes BPC and leaves it ready to commit; it does not move Git.
Local UI regression checks: `node tests/history_ui.test.cjs`.
