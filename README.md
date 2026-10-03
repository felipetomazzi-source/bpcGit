# bpcGit

Select one logic script, transformation or conversion and click **Diff** to
compare Git with current BPC text. Transformation/conversion workbooks include
their companion definitions; Excel files show a binary change summary.

Version control for SAP BPC 10.1 (NW) content in Git: EPM workbooks, logic
scripts, transformation and conversion files, Data Manager packages and
package links, security definitions, BPF template designs and dimension members. The app is a UI5
BSP application, installed with abapGit into
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
| GET | `/models?environment=<id>` | Authorized models; no Git pull or file comparison |
| GET | `/dimensions?environment=<id>` | Supported accessible dimensions; no member scan or Git comparison |
| GET | `/config?environment=<id>` | Repository setup of an environment |
| POST | `/config` | Save it (`environment`, `url`, `branch`) |
| POST | `/connection` | Test the connection (`environment`; optional `user`, `token`) |
| POST | `/workbooks` | Tracked files in BPC and Git with their status (`environment`; optional `kind`, `model`, `dimension`, `user`, `token`); returns stage timings |
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

Packages and links have their own object type choices before loading. Packages are XML files
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

## Scoped loading (0.11.0)

Opening an environment reads setup and authorized model names only. Choose one
object type and optionally a model, then press **Load**. SAP lists and compares
that scope, including Git-only files. Changing the choices clears the previous
list and selection; refresh and refresh after commit/restore retain the loaded
scope. Workbook subtype, status, location and search filters apply to loaded rows.

The first Git read pulls the branch snapshot. Subsequent reads may reuse its
path/hash metadata from SAP's shared buffer after checking current Git access
and the advertised branch head. Cache entries are isolated by SAP client/user,
Git username, repository and branch; no tokens or file content are cached.
Eviction or a moved branch triggers a fresh pull. Commit and restore always pull
fresh content. Git still needs repository-wide metadata; the BPC scan is scoped.

The overview shows elapsed seconds. Its tooltip reports SAP listing, Git and
comparison milliseconds (also available as `timings` in `/workbooks`). Use these
to compare one model with all models and first load with refresh before deciding
whether parallel SAP processing is worthwhile. Shared buffer reuse is local to
an application server and is a best-effort optimization.

Version 0.11.1 adds **All objects** to the type choices. EPM workbooks remains
the default; All objects loads every supported type in the selected model scope.

Version 0.11.2 replaces the combined EPM workbook load choice with EPM reports
(default), EPM input schedules and Other EPM workbooks. The API accepts REPORT,
SCHEDULE and OTHER scopes while retaining WORKBOOK for older clients. Company
reports/schedules list their specific library; team listings filter by the
library directly beneath EEXCEL before comparing content. Git-only files use
the same classification. Other covers books, distribution lists and remaining
workbook paths; All objects continues to include all supported objects.

## Security definitions (0.12.0)

The object type choices now include **Security: teams**, **Security: task
profiles**, and **Security: data access profiles**. These apply to the whole
environment; the model selector is disabled for them. Security administration
permission (BPC task P0011) is required to list, commit, inspect history or restore
these objects. All objects includes security only for authorized administrators
when All models is selected; other users continue to see their usual objects.

Each definition is a generated, readable XML file under `SECURITY/TEAMS/`,
`SECURITY/TASKPROFILES/` or `SECURITY/DATAACCESSPROFILES/`. Teams track their ID
and description; task profiles track description and task IDs; data access
profiles track standard, attribute and matrix access rules across their models.
Users, team leaders, profile assignments, emails and generated SAP role names
are excluded. Descriptions use the SAP session language; use the same logon
language when comparing across systems. This release does not transport other
language translations.

Restore creates missing definitions or updates existing ones using BPC APIs,
preserves local users/assignments and checks the resulting definition before
recording synchronization. New teams get BPC's normal folders; new teams and
profiles have no user assignments. Built-in default profiles cannot be restored.
Security deletion is deliberately refused: remove definitions in BPC, where the
effect on local assignments and folders is visible. Missing models and matrix
mode mismatches are rejected before a data access save. SAP validates remaining
references through its native APIs. Security XML is canonicalized for comparison;
matrix dimension/member column order is preserved.

After abapGit pull and activation, test one custom object of each type: commit,
edit the description/task/rule in BPC, restore, and refresh to Unchanged. Confirm
the original local memberships, leaders and assignments remain intact. Also test
creation of a new unassigned definition, History restore and a nonadministrator
session. The implementation has ADT syntax and local UI checks; SAP/browser
acceptance of security writes is still pending. Native security APIs update
roles/caches as well as database definitions, so ordinary document locks do not
apply and cross-system role side effects cannot be promised atomic rollback.

## Business process flows

Choose **Business process flows**, optionally select its controlling model, then
Load. Commit and History use one XML design per template under `<MODEL>/BPF/`.
Manage BPFs permission is required. Editable versions take precedence over deployed
versions. Restore updates an editable draft; validate and deploy it in BPC.
Running instances, deployed versions and local access assignments remain intact.

Activity workspace links resolve by local name/type; the workspace contents must
already exist in the target environment. Close the BPF editor before restoring.
Template deletion/archive stays in BPC. See the BPF section of the specification
for limitations and the SAP acceptance checklist.

## Dimension members

Choose **Dimension members**, select a dimension, then **Load**. Each member has
its own Git status, commit, history and restore under `DIMENSIONS/<dimension>/MEMBERS/`.
Dimensions are shared across models, so Model is disabled. Manage Dimensions or
Manage Members permission is required. This release supports regular dimensions;
time-dependent and reference dimensions are excluded.

Restore adds/updates selected members in the **BPC working copy**, preserving
other local members. Validate and process the dimension in BPC afterward.
Properties/hierarchies must already exist with a matching schema, and referenced
parents/members should be available first. Descriptions use the SAP session
language. Member deletion and transaction data remain outside Git restore.
