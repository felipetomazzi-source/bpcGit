# bpcGit: functional specification (v0.1, draft)

## Request-local authentication diagnostics (2026-10-05)

Read-only POST `/diagnostics` uses the same authorized environment/configuration
lookup as `/connection`. It accepts optional request-form user/token, reports
whether both are present, their non-secret username, and independent smart-HTTP
upload-pack and receive-pack advertisements. It does not push, compare BPC
content or update configuration/sync state. HTTP 200 contains checks with
`check`, `method`, `url`, `authScheme`, `status`, `statusSource`, `elapsedMs`,
`ok`, `authRequired`, and sanitized `message`. Failed read does not skip push.
Status is recovered from an abapGit exception when available, otherwise 0 with
an explicit unknown source. Success requires HTTP 200 plus a valid advertisement.
REST target/scheme are descriptive only (`restChecked=false`). Do not infer an
actual intercepted Authorization header from the intended scheme.

Credentials are request-local, not stored under an environment ID in a table,
SSF or secure store. Git-host HTTP 401 and HTTP 403 are both authorization
failures for the existing login response; distinguish absent credentials from
present credentials with `credentialFound`. A present credential plus 403 can
mean invalid credentials or insufficient permission. No raw headers, token,
response bodies or persistent diagnostic logs are exposed.

Smart HTTP uses the installed abapGit HTTP factory, including its SSL identity,
proxy configuration and optional exits. Runtime SM59/STRUST/proxy inspection is
separate from this endpoint. Bitbucket REST history/diff use their existing
direct HTTP client path and must not be conflated with smart-HTTP preflight.

## Repository URL login import (0.15.3)

The setup URL field accepts pasted HTTPS URLs containing `user:token@host`.
On field change and again before Save, the UI removes the credentials from the
URL and imports them through the existing tab-session login mechanism. Only the
clean repository address is sent in the configuration request and saved in SAP.
Percent-encoded credentials are decoded; token colons and equals signs are
preserved. Missing or malformed credentials are removed and a message directs
the user to Log in. The input permits long tokens without truncating them;
the saved repository address remains subject to the existing backend limits.
This does not validate the token; Test connection still checks Git access.

## Text diff (0.15.0)

Select one logic script, transformation, conversion or Data Manager package and choose Diff. The
read-only POST `/diff` accepts environment, path and optional Git credentials,
and returns the current branch head and current BPC/Git content parts. It checks
environment/model access and membership in the current scoped overview before
reading content. No sync baseline, content or Git commit is changed.

The diff direction is Git to BPC: minus/red lines are Git content; plus/green
lines are BPC content. Each part reports presence and byte size on both sides.
New/deleted files compare against an absent side; empty present files remain
distinguishable from missing files. Transformation/conversion workbook selections
include their companion TDM/CDM using the same pairing rules as history/restore.
Excel content is compared as binary, with an explicit changed/identical summary;
cell/formula differences are not displayed. Missing companion definitions are
reported, never silently assumed equal to the workbook. Direct TDM/CDM rows are
also supported.

Version 0.15.1 extends Diff to Data Manager packages. BPC content comes from
the canonical generated package XML already used for commit and restore,
including settings and the package's custom/default script representation.
It is not read through UJF as a physical file. Git-only packages compare against
an absent BPC side. Existing text limits, access checks and escaping apply.

Version 0.15.2 enables the same Diff action for package links, comparing their
canonical generated XML from BPC against Git. Link order and stored package
references/parameters are shown as text changes. Diff remains read-only, with
the same model-access checks, missing-side behavior and rendering limits.

Text supports UTF-8 and BOM-marked UTF-16, rejecting undecodable/binary content.
The backend limits each text part to 1 MB; the UI limits combined text to 200,000
characters and displays at most 2,000 rows, with explicit limit messages. LCS
work is bounded to one million cells; larger changed blocks display remove/add
blocks. CRLF/LF/CR are normalized only for display, and trailing newline changes
remain visible. Byte comparison still reports line-ending-only differences.
All source text is HTML-escaped before rendering, including script-like text.

Regression checks cover edits, insertion/deletion, duplicate lines, missing/empty
sides, final newline, line-ending normalization, bounded fallback, safe escaping,
selection eligibility and stale responses after closing the dialog.

## 1. Goal

bpcGit is a web app on the BPC system that puts BPC content under Git version
control in a GitHub repository. It tracks EPM workbooks, logic scripts,
transformation and conversion files, Data Manager packages and package links,
security definitions, business process flow (BPF) template designs and dimension
member master data.

A user opens the app, connects it to a GitHub repository, picks the BPC
environment to track, and then commits workbooks to Git or restores them from Git.

## 2. Scope

### In scope (v1)

- Set up a GitHub repository connection: URL and branch. The Git login is
  asked only when the Git host needs it, as in abapGit (section 7.2).
- Bind that connection to one BPC environment (AppSet).
- List the environment's tracked content and show each one's Git status.
- Commit selected workbooks to GitHub with a commit message.
- Restore (pull) selected workbooks from GitHub back into BPC.
- Show the commit history of a workbook.

### Out of scope (v1)

- Data Manager transaction data files, dimension schema creation/deletion, BPF
  instances and other BPC content
  not listed in section 3.
- Private publications (`PRIVATEPUBLICATIONS\<user>\`) and temporary files.
- Branch management, merging and conflict resolution inside the app. These
  are done on GitHub.
- Testing against Git hosts other than GitHub. abapGit uses the plain Git
  protocol over HTTPS, so Bitbucket and GitLab should also work, but v1 is
  tested only against GitHub.

## 3. What is tracked

### 3.1 EPM workbooks

Workbooks live in the BPC file service (package `UJF`). Tables `UJF_DOCTREE`
(folders and documents) and `UJF_DOC` (attributes and content) hold them.
The standard folder for each model is set in `UJF_DOCMAP`
(module `WEBEXCEL`):

| Library | Path |
|---|---|
| Model root (template library) | `\ROOT\WEBFOLDERS\<ENV>\<MODEL>\EEXCEL\` |
| Reports | `...\EEXCEL\REPORTS\` |
| Input schedules | `...\EEXCEL\INPUT SCHEDULES\` |
| Books | `...\EEXCEL\BOOKS\` |
| Distribution lists | `...\EEXCEL\PDBOOKS\` |

**Rule v1:** a workbook is any document (`DIR_DOC = 'D'`) with extension
`.xlsx`, `.xlsm`, `.xltx`, `.xltm` or `.xls` under one of these folders
(subfolders included):

| Location | Folder below `\ROOT\WEBFOLDERS\<ENV>\` | EPM shows it as |
|---|---|---|
| Company (public) | `<MODEL>\EEXCEL\` | Company (Public) |
| Team | `<MODEL>\TEAM FILES\<TEAM>\EEXCEL\` | `<team>\WEBEXCEL\TEAMTEMPLATELIBRARY\` |

Team folders also hold Data Manager files (e.g. `TEAM FILES\ADMIN\DATAMANAGER\`,
with `.XLS` conversion files); only files below the team's `EEXCEL` folder count.
In both locations the libraries are `REPORTS`, `INPUT SCHEDULES`, `BOOKS` and
`PDBOOKS`. Checked on dev on 2026-10-03: `AGGR_OPEX` has 19 team folders, e.g.
`CAPITAL CONTRIBUTION\EEXCEL\INPUT SCHEDULES\BOOK1.XLSX`.

On the dev system, `CH_PLANNING\AGGR_OPEX\EEXCEL\` contains files of this kind,
together with many `BACKUP\` folders and `COPY OF ...` files. See open question Q3.

### 3.2 Logic scripts

Added on 2026-10-03, after the workbooks, following bpcIO (`c_script_folder`):

- Location: `\ROOT\WEBFOLDERS\<ENV>\ADMINAPP\<MODEL>\<NAME>.LGF`, flat (no
  subfolders). Repository path: `ADMINAPP/<MODEL>/<NAME>.LGF`.
- Only the `.LGF` source is tracked. The `.LGX` files in the same folders are
  compiled by BPC (generated names such as `0D5SGVJ..._DEFAULT.LGX`) and are
  ignored.
- Same statuses, commit and sync record as workbooks; the overview shows them
  with type "Logic script" and location "Admin". Being text, they get
  line-by-line diffs on GitHub.

### 3.3 Transformation and conversion files

Added on 2026-10-03, following bpcIO (`c_dm_folder`, `c_transformation_folder`,
`c_conversion_folder`):

| Kind | Folder below `\ROOT\WEBFOLDERS\<ENV>\` | Files |
|---|---|---|
| Transformation | `<MODEL>\DATAMANAGER\TRANSFORMATIONFILES\` | `<NAME>.TDM` + `<NAME>.XLS` |
| Conversion | `<MODEL>\DATAMANAGER\CONVERSIONFILES\` | `<NAME>.CDM` + `<NAME>.XLS` |

- Same below a team: `<MODEL>\TEAM FILES\<TEAM>\DATAMANAGER\...` (e.g. team
  `INSTALLATION` on dev). Subfolders such as `BACKUP` are included (the
  overview hides them by default, as for workbooks).
- The `.XLS` is the Excel file the definition is maintained in; the
  `.TDM`/`.CDM` is the processed definition Data Manager runs. Both remain
  separate files in Git, but the overview shows one workbook row.
  Its status considers both files, and commit/restore automatically handles
  both. A change in either member changes the row; changes on opposite sides
  are a conflict. Partial additions/deletions show as modifications.
  Restore checks affected locks before writing and rolls back both files and
  their sync records if either fails. It verifies the restored Data Manager
  content before reporting success. Definitions without a workbook on either
  side remain visible so they can still be managed. If both `.XLS` and `.XLSX`
  exist with the same stem, the definition belongs to `.XLS`.
- Files without an extension (one on dev,
  `AGGR_PROJECT\...\CONVERSIONFILES\CONV_RESTORE_AGGR_PROJECT`) are not
  tracked: Git paths are recognised by their extension.
- One rule decides what is tracked, for BPC and Git alike:
  `ZCL_BPC_GIT_SERVICE->GET_KIND` (path to kind).

### 3.4 Data Manager packages and package links

Packages and links are table entries rather than BPC documents. They are
represented by generated UTF-8 XML files and use the same overview, status,
commit and restore flows. Their last-change fields are empty; generated
content is hashed on each comparison because the tables have no timestamps.

- Packages: `<MODEL>/DATAMANAGER/PACKAGES/<GROUP>/<PACKAGE>.xml`, also below
  `<MODEL>/TEAM FILES/<TEAM>/` for team packages. Package-group rows are ignored.
  XML records group, id, team, description, type, userGroup and process chain.
  A custom script is stored as one `<line>` per step in `<script>`; BPC's literal
  `<BR>` separators are rebuilt on restore. A final separator terminates the
  last step; adjacent earlier separators preserve intentional empty steps.
  Without `<script>` the package uses
  its process chain's default script. Restoring this over an existing custom
  script is refused before changing data: BPC's save API cannot remove the
  instruction row. Reset the package to its default script in BPC first.
- Links: `<MODEL>/DATAMANAGER/PACKAGELINKS/<NAME>.xml`, at company level only.
  BPC's link XML is preserved, with its first ID property blanked for Git.
  Restore updates an existing link by name, preserving its target-system ID
  and references; a new link receives a new ID. Deleting a scheduled link is
  refused by BPC.
- Path segments replace `/ \ : * ? " < > |` with `_`. Identity is carried in
  the XML; paths must match that identity when restoring.
- Restore uses BPC's package and package-link APIs. Each file commits its data
  and sync record together; a failed file rolls back before the next file.
- Duplicate names or names that sanitize to the same Git path are unsupported;
  only one object can occupy a tracked path. Resolve these names before use.

## 4. User flows

### F1. Set up the repository

1. The user opens the app. If no repository is set up yet, the app opens the
   setup screen.
2. The user enters:
   - Repository URL (`https://github.com/<owner>/<repo>`)
   - Branch (default `main`)
3. **Save** stores the configuration. No credentials are stored.
4. **Test connection** calls `ZCL_ABAPGIT_GIT_TRANSPORT=>BRANCHES`. This checks
   the SSL setup and read access, and shows whether the branch exists. With a
   Git login (section 7.2) it also checks push access by asking for the
   `git-receive-pack` advertisement, which the host only sends to users who may
   push.

### F2. Select the environment

1. A dropdown lists the BPC environments on the system.
2. The user picks one. That binds the repository to the environment (1:1).
3. Optionally, the user restricts tracking to particular models in that
   environment (default: all).
4. The binding is saved, and the root of the repository gets a
   `.bpcgit.json` file that records the environment and the format version.

### F3. Overview of workbooks

The main screen is a table of workbooks grouped by model. It shows each
workbook's path, last change in BPC (user and timestamp), size and status:

| Status | Meaning |
|---|---|
| Unchanged | BPC content matches the last synced Git version |
| Modified in BPC | Changed in BPC since the last sync |
| Modified in Git | Changed in Git since the last sync |
| Conflict | Changed in BPC and in Git |
| New in BPC | Not in Git yet |
| New in Git | In Git, missing from BPC |
| Deleted in BPC | Synced before, now missing from BPC |
| Deleted in Git | Synced before, now missing from Git |
| Differs, never synced | In BPC and Git with different content, and no sync record yet |

The screen has filters by status and model, plus a search box.

### F4. Commit to Git

1. The user ticks workbooks in the overview, one by one or with **Select all
   changes** (every committable workbook in the current filter). Only these
   statuses can be ticked; other rows are unticked again with a message:

   | Status | Commit does |
   |---|---|
   | New in BPC | adds the file to Git |
   | Modified in BPC | updates it in Git |
   | Differs, never synced | replaces the Git version with the BPC version |
   | Deleted in BPC | deletes it from Git |

   Unchanged has nothing to commit; Modified in Git and New in Git are for
   restore (F5); Conflict and Deleted in Git are refused so that a change in
   Git the user has not seen is never overwritten.
2. **Commit (n)** opens a dialog listing what happens to each workbook, and
   asks for a commit message.
3. The backend recomputes the statuses from the current branch head and
   refuses if the head is not the one the user saw ("reload the list") or a
   workbook is no longer committable. It then reads the BPC content and makes
   **one commit** with all files through abapGit's porcelain push, which also
   fails if the branch moves in between.
4. Author and committer: the SAP user's name and e-mail from the user master
   (as abapGit reads them); without an e-mail, the GitHub no-reply address of
   the Git user.
5. After the push the app writes `ZBPC_GIT_STATE` (blob, commit, BPC
   timestamp) for added and updated workbooks, deletes the rows of deleted
   ones, and reloads the overview.
6. Pushing needs a Git login; the app asks for it as in section 7.2.

### F5. Restore from Git

1. The user ticks files, one by one or with **Select Git changes**. These
   statuses can be restored:

   | Status | Restore does |
   |---|---|
   | Modified in Git | writes the Git version into BPC |
   | New in Git | creates the file in BPC (missing folders are created) |
   | Differs, never synced | replaces the BPC version with the Git version |
   | Deleted in Git | deletes the file from BPC |

   Added 2026-10-03 at the user's request, to discard BPC changes (like
   `git checkout`): Modified in BPC ("Discard BPC changes"), Conflict ("Take
   Git version, discard BPC changes") and Deleted in BPC ("Recreate in BPC").
   The dialog warns in red that the BPC changes are lost. "Select Git changes"
   still selects only files whose newer version is in Git. "Differs" can be
   committed or restored: commit makes BPC win, restore makes Git win.
2. **Restore (n)** shows what will be overwritten or deleted and warns that
   bpcGit keeps no copy of a BPC version that was never committed.
3. The backend recomputes the statuses from the branch head and refuses if
   the head is not the one the user saw or a file is no longer restorable.
   The content comes from the same abapGit pull.
4. Each file then succeeds or fails on its own:
   - A file locked in BPC (`CHECK_DOCUMENT_LOCK`, e.g. open for editing) is
     skipped. Others are written with `PUT_DOCUMENT` (no compression, no zip
     splicing, as in bpcIO). bpcGit does not lock them itself: BPC's lock is
     only the flag `UJF_DOC-LOCK_IND`, `PUT_DOCUMENT` refuses any set flag
     (also the caller's own, reporting the caller as the locker), and
     `LOCK_DOCUMENT`/`UNLOCK_DOCUMENT` rewrite the last-change date, time and
     user (checked in `CL_UJF_FILE_SERVICE_MGR`/`_DAO` on 2026-10-03).
   - Logic scripts: line endings are normalized to CRLF (BPC splits scripts
     at CRLF; files edited elsewhere may use LF), then the script is validated
     with `CL_UJK_SCRIPT_LOGIC=>VALIDATE`, as BPC's script editor does. An
     invalid script is not written; the result carries BPC's message.
     Restoring scripts needs task P0008, like bpcIO's script import.
     No `.LGX` needs to be written: BPC compiles scripts when they run
     (checked on dev 2026-10-03: models have no `<NAME>.LGX`, only temporary
     ones with generated names).
5. `ZBPC_GIT_STATE` records the Git blob, the commit and the new BPC
   timestamp for restored files (rows of deleted files are removed), so they
   show as Unchanged. The overview reloads and failures are listed.

### F6. History

Select one item, including an Unchanged item, and choose **History**. The
list shows commits that changed its content, with author, UTC date, message
and commit SHA. Transformation and conversion history considers both the
workbook and its definition. Incomplete historical pairs are shown but cannot
be restored. Deletion commits are shown and warn that restoring that snapshot
deletes the item in BPC.

History follows the configured branch's first-parent chain (merge commits show
the changes introduced into that branch). It fetches the latest 20 branch
commits initially; **Load older history** increases the range by 20 up to
1,000. The UI says when older history remains or the limit has been reached.
Version 0.15.4 authorizes the selected tracked path directly (environment,
model and security/BPF/dimension read permissions), without a BPC status scan
or a preliminary Git branch-content pull. History uses abapGit's raw upload-pack
objects and traverses only the selected path(s); it does not materialize a full
branch file list. Authorized paths absent from Git return empty history, and
paths deleted at the current head can still show older changes.

Computed history results are cached in INDX shared buffer area BH, keyed by
SAP client/user, Git user, repository, branch, path set, depth and cache format.
Every request checks current remote authorization/head before cache reuse;
head changes and eviction force a fresh fetch. Only result metadata is cached,
not tokens, file contents or Git objects. A cold request still downloads the
Git pack for the requested branch depth, including blobs: this is not a
server-side single-file fetch. Restore continues to revalidate current BPC
status and expected head before applying a selected version.

File renames are treated as separate paths. The shallow boundary is not shown
as a file change unless its parent was fetched and compared, or it is the
repository's actual root commit.

Version 0.15.5 uses Bitbucket Cloud's metadata API for URLs on bitbucket.org.
After verifying current Git authorization/head, it batches recent commit headers
and follows first parents explicitly. Per-path diffstat compares each commit
to its first parent with rename detection disabled. File presence is read once
at the pinned head using `format=meta`, then propagated backwards from old/new
path metadata to determine deletion and paired completeness at each change.
Root commits are handled from presence without requesting a nonexistent parent.
Paths and API results are validated, and unexpected diffstat pagination is an
error rather than incomplete history. No workbook/file blobs are downloaded by
Bitbucket History; other hosts retain the generic abapGit history implementation.

This requires outbound SAP HTTPS/trust for api.bitbucket.org and API repository
read access. x-token-auth access tokens use Bearer; other users use Basic auth
(Atlassian API tokens require the Atlassian email as API user). HTTP errors are
reported explicitly; there is no slow automatic Git-pack fallback. Requests
have a 30-second timeout, disable redirects and limit each reply to 1 MB.
Pinned immutable metadata replies (including confirmed absent files) are cached
in shared buffer BI, scoped to client/SAP user/Git user/repository/request URL.
This complements the head-checked history result cache; each history call still
rechecks Git access before metadata reuse. Tokens and error replies are never
cached. Commit/restore content transfer continues through abapGit.

Choose a complete version and **Restore selected version**, then confirm.
The backend verifies that the version belongs to the displayed history and
that the branch head still matches the head seen when history was loaded.
It reads the selected commit through abapGit and uses the same lock checks,
script validation, package/link guards and transaction behavior as normal
restore. Paired files use one historical snapshot and roll back together.
Restoring an older version changes BPC; it does not change Git. Sync state
keeps the current Git head as the comparison baseline, so older restored
content appears as Modified in BPC (or New/Deleted in BPC) and can be committed.
Restoring the current version leaves matching content Unchanged.

API: `POST /history` accepts environment, path, optional depth, user and token.
`POST /restore` accepts optional version (historical commit) and depth as well
as the existing commit (expected current head) and paths. History restore is
limited to one logical item per request. All POST guards and Git login rules
apply. Git calls remain in `ZCL_BPC_GIT_REMOTE`.

## 5. Repository layout

```
.bpcgit.json                        environment, format version
<MODEL>/EEXCEL/REPORTS/<file>.xlsx
<MODEL>/EEXCEL/INPUT SCHEDULES/<file>.xlsm
...
```

- The BPC path below `\ROOT\WEBFOLDERS\<ENV>\` maps 1:1 to the repository
  path, with `\` changed to `/`.
- BPC stores file names in upper case. They are kept as they are.
- Workbooks are binary files. Git stores them as they are, with no unzipping
  and no text diff in v1 (see Q4).

## 6. Change detection

- For each tracked file, table `ZBPC_GIT_STATE` stores the BPC document name,
  the Git blob SHA of the last synced content, the commit SHA, the BPC
  last-change timestamp at sync time, and who synced it when. Commit (F4) and
  restore (F5) write it; the overview (F3) only reads it.
- If BPC and Git have the same content, the workbook is Unchanged, with or
  without a sync record. Without a record and with different content, it is
  "Differs, never synced", because the app cannot tell which side changed.
- BPC content is read and hashed only when needed: when the workbook is also
  in Git and its BPC timestamp differs from the sync record (or there is no
  record). An empty repository therefore costs no content reads.
- Files in Git are recognized by the shared `GET_KIND` rules in section 3;
  unrelated files (README.md, .bpcgit.json) are ignored.
- Modified in BPC: the BPC `LSTMOD_DATE`/`LSTMOD_TIME` has changed **and** the
  Git blob SHA-1 of the current content differs. The SHA comes from
  `ZCL_ABAPGIT_HASH`.
- Modified in Git: the file's blob SHA in the branch head differs from the
  stored SHA. The branch head is read with `ZCL_ABAPGIT_GIT_PORCELAIN=>PULL_BY_BRANCH`,
  which returns each file's path, content and SHA.

## 7. Architecture

The app follows the same architecture as bpcIO:

| Part | Object | Notes |
|---|---|---|
| UI | BSP app `ZBPC_GIT` | UI5 1.52, `/UI5/CL_UI5_BSP_APPLICATION` |
| REST handler | `ZCL_BPC_GIT_HTTP` at `/sap/bc/zbpc_git/` | JSON in and out |
| Service | `ZCL_BPC_GIT_SERVICE` | Orchestrates flows F1â€“F6 |
| BPC file access | `ZCL_BPC_GIT_BPC_FILES` | Wraps `CL_UJF_FILE_SERVICE_MGR` (`FACTORY`, `LIST_DIRECTORY`, `GET_DOCUMENT`, `PUT_DOCUMENT`, `LOCK_DOCUMENT`/`UNLOCK_DOCUMENT`) |
| Git client | `ZCL_BPC_GIT_REMOTE` | Thin wrapper over abapGit (section 7.1). It is the only class that calls abapGit |
| Config table | `ZBPC_GIT_REPO` | Environment, URL, branch, last changed by/at |
| Sync state table | `ZBPC_GIT_STATE` | One row per tracked file (section 6) |
| Package | `ZBPC_GIT` | Already linked to this repository in abapGit (key 000000000006) |

### 7.1 Dependency on abapGit

bpcGit reuses abapGit's Git implementation instead of writing its own. These
objects were checked on the dev system on 2026-10-03:

| Need | abapGit object |
|---|---|
| Read the branch head (files, content, SHAs) | `ZCL_ABAPGIT_GIT_PORCELAIN=>PULL_BY_BRANCH` / `PULL_BY_COMMIT` |
| Commit and push several files | `ZCL_ABAPGIT_STAGE->ADD` (binary `xstring` content) + `ZCL_ABAPGIT_GIT_PORCELAIN=>PUSH` |
| List branches / test the connection | `ZCL_ABAPGIT_GIT_TRANSPORT=>BRANCHES` |
| History | `ZCL_ABAPGIT_GIT_TRANSPORT=>UPLOAD_PACK_BY_BRANCH` (`iv_deepen_level`) + `ZCL_ABAPGIT_GIT_PACK` |
| Blob SHA-1 | `ZCL_ABAPGIT_HASH` |
| HTTP, SSL, proxy, Bitbucket user-agent | `ZCL_ABAPGIT_HTTP` (used internally by the above) |
| Session credentials | `ZCL_ABAPGIT_LOGIN_MANAGER=>SET_BASIC` |

Rules:

- **Requirement:** bpcGit runs only on the development system (Q7). That
  system needs the abapGit **developer version** installed as global classes,
  which is already the case: it is in `$ABAPGIT`. The standalone `ZABAPGIT`
  report doesn't work, because its classes are local to the report and other
  programs can't call them.
- abapGit doesn't promise a stable API ("future changes are a possibility",
  docs.abapgit.org, API page). For that reason only `ZCL_BPC_GIT_REMOTE` calls
  abapGit, and upgrading abapGit means re-testing that one class.
- **No popup:** when the Git host answers 401 and no SAP GUI is available,
  `ZCL_ABAPGIT_HTTP->ACQUIRE_LOGIN_DETAILS` does not show a popup; it raises
  "Unauthorized access. Check your credentials" (checked on dev, 2026-10-03).
  `ZCL_BPC_GIT_REMOTE=>IS_AUTH_ERROR` recognizes that and the API answers with
  `authRequired`, so the app can ask for the login (section 7.2).
- The login manager caches credentials in static data, which lives only for
  the ABAP session. Stateless REST calls therefore set them again on every
  request.

### 7.2 Git login, as in abapGit

Decision (2026-10-03): no SM59 destination and no user exit. bpcGit does what
abapGit does in SAP GUI: it never stores the login and asks for it only when
the Git host wants it.

- abapGit sends Git requests without credentials. A public repository can be
  read that way (GitHub answers 200 to `git-upload-pack`), so pulls need no
  login. Pushing always needs one (GitHub answers 401 to `git-receive-pack`),
  and so does reading a private repository. On 401 abapGit asks once and keeps
  the login in `ZCL_ABAPGIT_LOGIN_MANAGER` for the rest of the session.
- In bpcGit the API answers a 401 from the Git host with HTTP 403 and
  `"authRequired": true`. (Not 401, so the browser does not show its own
  logon popup.) The app then shows a login dialog (user and personal access
  token) and retries the request.
- The app keeps the login in the browser tab's `sessionStorage` (revised
  2026-10-03 at the user's request, so it survives page reloads): it is gone
  when the tab or browser closes, or on "Log out". Only the user name is kept
  longer, in `localStorage`, to pre-fill the dialog. The token is never in a
  URL or the UI model. It is sent in the POST body of each request that talks
  to the Git host.
- Trade-off: browser storage is plain text, readable by any page of the same
  origin (the whole SAP host and port). `sessionStorage` limits that to the
  open tab; `localStorage` for the token was considered and not chosen.
  Encryption in the browser (WebCrypto) is not available over plain HTTP.
- The server puts it in the login manager for that one request
  (`ZCL_BPC_GIT_REMOTE` constructor) and never stores or logs it.
- GitHub needs a personal access token, not the account password.
- **Caveat:** the dev system is reached over plain HTTP (port 8000), so the
  token crosses the network unencrypted between browser and SAP. Use the HTTPS
  port if the network is not trusted.

### Constraints

- NetWeaver 7.52 / BPC 10.1: no ABAP syntax newer than 7.52.
- UI5 1.52 APIs only.
- abapGit serialization byte rules as in bpcIO (BOM in the metadata XML,
  CRLF line endings in `.abap` files, `.wapa` lines padded to 255 characters).
- The system needs outbound HTTPS to `github.com`. The GitHub certificate
  chain has to be imported in STRUST (SSL client PSE). abapGit's normal setup
  already covers this, and it works on the dev system.

## 8. Security

- **Token storage.** Never on the server; in the browser only in the tab's
  `sessionStorage` (section 7.2).
- **Authorization.** Only BPC admins of the environment can set up the
  repository and restore files. Committing needs at least read access to the
  files. The service checks this through the BPC user context.
- **Logging.** Never log the token or send it back to the UI. The login dialog
  shows it masked.
- **Cross-site requests.** Every POST must carry `X-Requested-With:
  XMLHttpRequest`, which a form on another website cannot set.

## 9. Open questions

- **Q1. Where is the token kept?** (a) encrypted in a Z table with SSF/`SECSTORE`,
  (b) in an SM59 HTTP destination maintained by Basis, with the app
  storing only the destination name, or (c) entered per session and never
  stored. **Decision (2026-10-03, revised): (c) only, as abapGit does it
  (section 7.2).** (b) was chosen first and then dropped: it needed an SM59
  destination per repository and an injected abapGit exit.
  - How abapGit handles it (checked on the dev system through ADT on 2026-10-03):
    - Interactive use keeps credentials only in memory, in a static table in
      `ZCL_ABAPGIT_LOGIN_MANAGER`, and never stores them.
    - The documented way to store them permanently is the user exit
      `CREATE_HTTP_CLIENT`, which uses `cl_http_client=>create_by_destination`
      with an SM59 destination (abapGit issue #1841).
    - Background mode is the exception: it stores the username and password in
      plain text as XML in table `ZABAPGIT` (`ZIF_ABAPGIT_PERSIST_BACKGROUND`).
      bpcGit should not copy that.
- **Q2. One shared connection or one per user?** Proposal: one per
  environment, shared, with the BPC user recorded as the commit author.
- **Q3. Should BACKUP folders and `COPY OF ...` files be excluded?** Resolved
  (2026-10-03, step 5): they are listed, but the overview hides them by default
  ("Hide backups and copies", on). No configuration needed for now.
- **Q4. Should workbooks be unzipped for readable diffs?** `.xlsx` is a zip of
  XML. Storing the unzipped parts gives readable diffs on GitHub, but the
  restore has to rebuild the file byte for byte. Proposal: not in v1.
- **Q5. How is the commit author identified?** Proposal: the BPC user ID plus an
  email taken from the user master, with the configured GitHub user as a fallback.
- **Q6. Is an outbound proxy needed?** If the system reaches the internet
  through a proxy, abapGit's proxy settings apply. To check with Basis.
- **Q7. Where does abapGit need to be installed? Resolved (2026-10-03):**
  only on dev. bpcGit runs only in the development system, so QA and
  production need neither bpcGit nor abapGit.
- **Q8. How does bpcGit hook into abapGit's user exit? Resolved (2026-10-03):**
  it doesn't. Without SM59 (Q1) no exit is needed, so a customer's own
  `ZCL_ABAPGIT_USER_EXIT` is never touched.

## Scoped startup and overview performance (0.11.0)

Startup does not enumerate BPC documents or pull Git. It reads repository setup
and `/models` metadata, then offers WORKBOOK, SCRIPT, TRANSFORMATION, CONVERSION,
PACKAGE or LINK and an optional authorized model. Load sends `kind` and `model`
to `/workbooks`; omitted fields retain the legacy API all-content behavior.
Model authorization is checked before listing. Only the selected folder types
and generated object providers run; Git-only rows are filtered by the same scope.
Pairs stay grouped. Commit/restore status checks and History derive scope from
selected paths; mixed selections fall back to the relevant broader scope.

Changing the choices invalidates pending overview responses and clears selection.
Refresh and action completion reload the loaded scope. Config/environment changes
clear the overview, and stale configuration responses cannot initiate a scan.

The remote adapter caches only branch path/hash metadata in the existing INDX
shared buffer area BG, keyed by hashed SAP client/user, Git user, URL and branch.
Every read checks Git authorization and current head before using cached metadata.
A miss, eviction or head change causes a fresh pull. Binaries, tokens and Git
objects are never placed in the cache. Mutations bypass cache input and fetch full
content; existing optimistic head checks and paired restore transactions remain.
Reuse is best effort on one application server. No new DDIC objects are required.

`timings` reports `bpcMs`, `gitMs`, `compareMs`; the page shows total client elapsed
seconds with the server stages in a tooltip. This first step reduces work and
measures it. Parallel processing remains deferred until SAP measurements justify it.

Version 0.11.1 offers All objects (`ALL` in the UI, empty API `kind`) alongside
the six types. EPM workbooks remains the default. The optional model still
restricts the scan; All models plus All objects performs the full comparison.

Version 0.11.2 replaces the combined EPM workbook load choice with EPM reports
(default), EPM input schedules and Other EPM workbooks. The API accepts REPORT,
SCHEDULE and OTHER scopes while retaining WORKBOOK for older clients. Company
reports/schedules list their specific library; team listings filter by the
library directly beneath EEXCEL before comparing content. Git-only files use
the same classification. Other covers books, distribution lists and remaining
workbook paths; All objects continues to include all supported objects.

## Security objects (0.12.0)

User decisions: task profiles (not "test" profiles); transport definitions only,
keep all users and assignments local. bpcIO has no security export provider.
ADT inspection found native CL_UJE_TEAM, CL_UJE_PROFILE_TASK and
CL_UJE_PROFILE_MEMACCESS APIs. Their mutations enforce
CL_UJE_COMMON=>ENSURE_HAS_MANAGE_AUTHORITY, which checks BPC task P0011.

ZCL_BPC_GIT_SECURITY exports one schema-version-1 native ABAP XML definition per
logical ID. Paths: SECURITY/TEAMS/<escaped-id>.xml, SECURITY/TASKPROFILES/
<escaped-id>.xml, SECURITY/DATAACCESSPROFILES/<escaped-id>.xml. Kind values are
TEAM, TASKPROFILE, DATAPROFILE. These are environment-wide, with no model/team
location. The model selector resets to All models and is disabled. API requests
that combine a security kind with a model return 400. All objects plus a selected
model excludes security; All objects/All models includes it for administrators.
Nonadministrators cannot list security or Git-only security rows; explicit
security requests fail authorization. Context is established for the environment
before checking authority. Commit/History/restore recheck through scoped listing.

Team payload: ID and description. Task profile payload: ID, description and task
IDs. Data profile payload: logical ID plus UJE_S_MBR_PROF_DET, containing standard
cube/dimension/member rules, attribute filters and matrix rules. PROFILE_AGR_NAME
in that DTO is a logical caption, not an SAP-generated role; it is normalized to
the logical ID. Users, leaders, team/profile assignments and user attributes are
not exported or restored. Descriptions are in the current SAP session language;
multilingual description transport is outside this release.

Canonicalization sorts set-valued tables by their serialized deep rows and clears
derived MEMBERDESC fields. Positional matrix DIMENSIONS and outer MEMBERS tables
retain their order; member sets inside columns are sorted. No cell GUIDs, roles or
timestamps are present in the API definition DTO. XML is indented for Git review.
Generated rows are hashed on each overview comparison; sync remains per object.

Restore validates schema version, kind, XML ID versus path, ID length and fields
belonging to another kind. Teams use CREATE_TEAMS/UPDATE_TEAMS without assignment
parameters. Task profiles use the user-manager factory (private task constructor)
and CREATE/UPDATE with an explicit full task list. Data profiles use
CREATE_MBR_PROFILES/UPDATE_MBR_PROFILES with complete rule sets. No profile owner
update API is called. Models and standard/matrix mode are validated before saving
data rules. Native APIs validate tasks and remaining references. Default task/data
profiles are read-only for restore. Security deletion is refused to preserve
local assignments and team folders. History reuses the same guards.

The provider reads the definition back after mutation, canonicalizes and compares
it with the requested version before marking synchronization. Failure triggers
the existing restore rollback and no success baseline. Native role/cache side
effects may extend beyond the database transaction; no broader atomicity is
claimed. The new security provider was syntax-checked through ADT using an existing
class context (name substitution only). Service integration used signature
stand-ins for the new, not-yet-installed provider; HTTP checked directly. UI
scope/location tests and existing history regressions pass. Full SAP activation
and functional acceptance of native writes remain manual through abapGit/browser.

Version 0.12.1 decodes percent-encoded security filenames for display and name
search (spaces and UTF-8 characters). Repository paths and action identities
remain encoded. Other file names are literal; malformed encodings fall back
to their original text instead of breaking the overview.

## Business process flows (0.13.0)

BPF tracks BPC 10 template designs, not process execution. Kind BPF appears as
Business process flows in the load selector, with an optional controlling-model
scope. All objects includes BPF when the user has Manage BPFs (task P0043).
The environment context and this permission are checked for listing, commit,
history and restore; explicit unauthorized BPF loads fail. Names are decoded
for display/search while encoded repository identities are retained.

ZCL_BPC_GIT_BPF uses CL_UJB_10_TMPL_MGR and CL_UJB_10_TMPL_HDR. One generated,
indented schema-version-1 ABAP XML file represents each technical template name:
<MODEL>/BPF/<escaped-technical-name>.xml. It reads the edit version first, then
the active version, then the latest remaining version. Each overview hashes the
canonical definition, using the existing per-object sync state and Git history.
BPF XML is a generated object, never written into the UJF document service.

The design includes controlling model, instruction, classification, identity
dimensions, ordered activities, driving dimensions/member selectors, owner and
reviewer properties, reopening/review rules and deadline settings. Activities
are sorted by order and member selectors by their portable fields. Technical
template names identify objects; local version labels, physical IDs/GUIDs,
environment IDs, logical systems, activation/editing/validation state, timestamps,
localized dimension/member captions, owners/subscribers and instance metadata
are excluded. Text is read in the SAP session language; multilingual template
captions/version-label transport is outside this release.

Performer/reviewer workspace links are exported separately by activity order,
role, workspace name and resource type. Workspace contents are not versioned.
Restore prefers the matching workspace already attached to that local activity;
otherwise its name/type must resolve uniquely in the target environment. Missing
or ambiguous dependencies fail before saving. An existing target model is
required; restoring into a different controlling model under the same technical
name is refused. Native edit-version creation can copy local activity workspaces;
unchanged links reuse those copies. This avoids exporting source-system GUIDs
and avoids ambiguity between deployed and editable workspace copies.

Restore validates schema/path/identity, rejects runtime IDs and assignments,
checks unique activity orders and rejects legacy actions/substeps unsupported
by the BPC 10 save API. It holds the template header write lock, rechecks editing
state and refuses open templates (even one's own), deployed/nonlocal edit
versions or edit versions with instances. A new template is created as Git draft;
an existing template gets or updates its native editable version. Nested
environment IDs are reconstructed locally, and existing local access assignments
and version labels are preserved. Native APIs generate the remaining IDs.
No activation, instance modification, archive or template deletion API is called.
Git deletion restores are refused; delete/archive templates deliberately in BPC.

After saving, the provider reads and canonicalizes the draft and requires an
exact match to the requested Git definition; it also verifies the existing active
version is unchanged. Errors use the existing restore rollback and do not record
success. Editing locks are released. Native audit/resource side effects may extend
beyond the database transaction; no broader atomicity is claimed. The UI explains
that a restored draft must be validated and deployed in BPC. History restore uses
the same draft/dependency/permission guards and preserves the current Git baseline.

Validation: provider syntax through ADT in an existing class context (class-name
substitution only); service through ADT with signature stand-ins for this new,
not-yet-installed provider; HTTP directly. Scoped UI tests cover BPF model scope,
labels, decoded names and encoded identities; history tests cover BPF restore
payload and draft warning. Formatting, JS/JSON/XML checks pass. Full activation
and BPC write acceptance require the user's abapGit pull and browser test:

1. Select Business process flows, a model and Load. Confirm edit versions take
   precedence, template names/statuses display correctly, and All objects works.
2. Commit a representative BPF. Refresh and confirm Unchanged. Make an activity
   instruction/rule change in BPC, save and close the editor, then refresh.
3. Restore it from Git, inspect the editable BPC version, and confirm the design
   was restored and the overview is Unchanged. Validate/deploy manually if wanted.
4. Confirm active versions, running instances and local access assignments stay
   intact. Test a deployed-only template and a template already containing a draft.
5. Restore a historical version; confirm its design appears as a draft and can
   be committed back. Test new-template restore in another environment with the
   model/workspaces available, plus missing workspace, open editor and Git deletion
   failures. Failed restores must not record a synchronized baseline.

## Dimension members (0.14.0)

The user approved versioning member IDs, descriptions, property values and
hierarchy parents, with add/update restore and no automatic member deletion.
ZCL_BPC_GIT_MEMBERS uses the BPC member editor API CL_UJAM_MEMBER /
IF_UJA_MEMBER_MANAGER. This tracks the current working copy, including saved
unprocessed changes; restore saves to that working copy. It never calls Process,
Refresh, Clear, Import, activation or transaction-data write APIs. The user
validates/processes the dimension deliberately in BPC afterward.

Kind DIMMEMBER appears as Dimension members. Dimensions belong to the environment
and can be shared across models; paths therefore have no model component:
DIMENSIONS/<escaped-dimension>/MEMBERS/<escaped-uppercase-member-id>.xml.
Each member has independent status, selection, commit, history and sync baseline.
Encoded path identities remain unchanged while member names are decoded for
presentation/search. Generated XML never uses the UJF document restore route.

Selecting Dimension members disables the Model selector and obtains lightweight
supported dimension metadata through GET /dimensions?environment=<id>. The first
accessible dimension is selected; no member scan/Git comparison starts until
Load. All supported dimensions is an explicit alternative. POST /workbooks accepts
optional dimension only with DIMMEMBER and rejects a model with that kind.
Backend comparison and mutation/history scope include the chosen/common dimension.
All objects/All models also includes supported members for administrators;
All objects restricted to a model excludes environment-scoped members.

Manage Dimensions (P0012) or Manage Members (P0133) is required for this provider,
in addition to native per-dimension access checks. Context is set for the requested
environment. Explicit member requests fail without authority; All objects omits
them. Inaccessible dimensions are omitted from metadata. This version supports
non-time-dependent, non-reference dimensions with BPC parent hierarchies; dimensions
with time-dependent properties/hierarchies or reference dimensions are excluded.
Supplementary BW hierarchies, multi-language/version transport and dimension schema
creation/modification are outside this release.

The schema-version-1 XML contains dimension, uppercase ID, original-case member
name, description and SAP language, plus properties and parents keyed/sorted by
logical property/hierarchy name. Empty values are included so restore can clear
previous values. Generated properties, row flags, OBJVERS, physical BW names,
SIDs, timestamps and processing state are omitted. Member descriptions use the
SAP session language; restores require that same language. Native dynamic
working-copy columns are mapped to logical XML names using dimension metadata,
preserving long property values beyond the older fixed 255-character DTO limit.

Restore validates XML schema, path, member ID/name/language, editable target
properties and existing target hierarchies. The set of editable properties and
parent hierarchies must match before saving; schemas are not created by restoring
a member. Dynamic native fields are checked for lossless value conversion, so
oversized or incompatible values fail instead of truncating silently. Native Save
is called with computed insert/update flags and update mode, preserving other
members and generated/local fields. Native validation and dimension locks remain
enabled. Missing member/property/parent references are reported by BPC; when
creating members in another environment, restore/create referenced parents and
property-reference members first. Bulk restore remains per member, so individual
results may succeed/fail independently.

Save updates the editable member store, with no dimension processing. Readback
requires the selected member's canonical XML to match before synchronization is
recorded. A failed save/readback uses the existing restore rollback. No broader
atomicity beyond the native database operation is claimed. Git deletion and
historical deletion restore are disabled in the UI and refused in the backend;
remove members deliberately in BPC where transaction-data references can be
checked. A deliberate BPC deletion can still be committed to Git. Restoring older
member content retains the current-head baseline so it can be committed again.

Validation: provider ADT syntax check in an existing class context (name substitution
only); complete service/HTTP checks through ADT using signature stand-ins for the
new provider and new service arguments not yet installed in SAP. UI regressions
exercise metadata-only selection, stale-environment responses, error handling,
scoped refresh, explicit All dimensions, decoding, history payloads and deletion
restrictions. JS/JSON/XML and abapGit formatting checks pass. No SAP writes were
made through ADT. Activation and native write acceptance remain the user's steps:

1. Pull/activate with abapGit. Choose Dimension members and a regular dimension;
   confirm shared dimensions appear once and selecting one does not auto-load.
2. Load, commit a few representative members (including description, blank
   properties, formula/property references and multiple hierarchy parents), then
   refresh and confirm Unchanged. Save an edit in BPC without processing and
   confirm Modified in BPC appears for just that member.
3. Restore it, open the BPC member editor, and verify the description/properties/
   parents returned to Git while other local members stayed intact. Validate and
   process the dimension manually; confirm status remains stable after processing.
4. Restore an older history version and confirm it is a committable working-copy
   change. Test adding a missing member with its references already available.
5. Test schema/path/language mismatch, invalid references, locked dimension,
   oversized property and deletion snapshots. Failures must not record success or
   remove members. Transaction data must remain unchanged.

## Bitbucket transport diagnostics (0.15.6)

History shows SAP's HTTP last-error code and message on transport failures,
retrieved before closing the client. The current token is redacted from the
message. A transport failure alone does not establish a certificate issue.

## Targeted Diff loading (0.15.7)

Diff reads BPC's selected type/model listing without comparing every row or
loading sync state. Bitbucket reads only the selected file and companion paths
through raw source GETs pinned to the freshly authorized branch head. Presence
comes from HTTP status, preserving empty present files. Raw bytes bypass the
metadata cache; redirects are refused and each Git file is limited to 16 MB.
Existing text decoding/rendering limits and binary summaries apply. Other hosts
retain abapGit branch reads. Generated BPC providers still serialize their
scoped listing, so this change does not eliminate all BPC-side listing cost.

## Selected-object commit validation (0.15.8)

Commit's fresh overview is limited to selected paths and same-stem transformation/
conversion companions before status comparison. All companion eligibility and
expected-head checks still apply. Other overview/restore callers retain their
existing scope. After a successful abapGit push, the updated path/hash index and
returned head are exported to the existing user/repository scoped shared buffer;
refresh still verifies remote authorization and current head before reuse.
No binary contents or credentials are cached. A changed head or eviction falls
back to a fresh pull. The initial commit Git pull and BPC provider listing remain.


## Opt-in Git LFS for large EPM workbooks (0.16.0)

Repository setup offers **Use Git LFS (Bitbucket Cloud)** and a whole-number
threshold of 1–100 MB (default 5 MB; 1 MB = 1,048,576 bytes). The option defaults
to off, including existing configurations. It applies only to nonempty EPM
Excel files below company/team EEXCEL folders, including reports, input schedules,
books and distribution lists. Data Manager transformation/conversion workbooks,
text and generated definitions continue using regular Git. Maximum LFS transfer
size is 128 MB. GitHub, GitLab and Bitbucket Data Center LFS are not supported in
this first implementation; regular Git for these hosts is unchanged.

On a future selected commit, a qualifying workbook is uploaded through the
Bitbucket Git LFS basic batch/upload/optional verification protocol **before**
abapGit pushes its canonical SHA-256 pointer. The same Git commit adds exact,
quoted root `.gitattributes` rules. Existing root attributes are preserved;
nested `.gitattributes` that could override the selected workbook are refused.
Rules escape filename glob characters, spaces, quotes and backslashes. Existing
LFS workbooks keep using LFS when edited, even if they shrink below the threshold.
Disabling the option refuses writes to existing nonempty LFS files rather than
silently replacing their pointers with binaries. Deletion remains possible.
Empty files use regular zero-byte Git blobs as Git LFS specifies.

This does not migrate earlier commits or rewrite history. Previously committed
binary workbooks switch to LFS only when subsequently changed and committed.
Existing ordinary Git objects still contribute to pack downloads and repository
size. Upload failure prevents Git push and sync-state updates. A later Git push
failure may leave an unreferenced LFS object on the host, with no successful
BPC sync recorded; Git LFS objects are immutable and retry-safe by hash.

Overview status comparison hashes BPC content into the canonical pointer form
for paths already using LFS. The metadata cache retains pointer identity, so
status comparison does not download LFS workbook bytes. Commit sync baselines
record the pointer blob hash. Current/historical restores resolve pointers to
workbook bytes, checking declared size and SHA-256 before writing to BPC. Mixed
ordinary Git and LFS histories are supported. Canonical v1 pointers only;
malformed, extended and oversized pointers produce explicit errors.

The Bitbucket raw-source API redirects LFS files to media storage. Selected-file
reads encountering that redirect fall back to the actual pointer in the pinned
Git head, rejecting a changed head or a redirect without an LFS pointer. They
then use the same verified LFS download. History metadata continues using the
Bitbucket API. EPM cell diffs remain outside scope.

Batch requests use the existing request-local Basic Git credentials against
Bitbucket's repository LFS endpoint. Storage actions use only server-supplied
headers; repository credentials are never forwarded to storage URLs. HTTPS is
required; redirects are disabled. Tokens, action URLs, response bodies and file
bytes are not persisted by bpcGit. Transfers are synchronous, bounded
after receiving the response, with a 60-second HTTP timeout. SAP must trust and
reach the LFS/storage hosts as well as bitbucket.org and api.bitbucket.org.
Bitbucket token LFS permissions and storage quota also apply.

References: [Git LFS batch protocol](https://github.com/git-lfs/git-lfs/blob/main/docs/api/batch.md),
[pointer format](https://github.com/git-lfs/git-lfs/blob/main/docs/spec.md),
[Bitbucket source API](https://developer.atlassian.com/cloud/bitbucket/rest/api-group-source/).

## BPCIO embedded component (0.16.1)

Contract agreed with the BPCIO integration: namespace `bpc.git`, component URL
`/sap/bc/ui5_ui5/sap/zbpc_git/`, settings `embedded` (boolean, false default) and
`environment` (string, empty default). UI5 1.52 host uses `sap.ui.component` and
`ComponentContainer`; no additional bootstrap or componentData. Embedded hides
its page header, leaves navigation/header ownership with the hub, and shares
the host UI5 theme. `setEnvironment(string)` clears old scope and selects only
an authorized host environment. Empty/unauthorized selections never fall back.
The host may invoke `requestNavigateBack()`; `navigateBack` carries `environment`.
Host may retain component state on back, and owns container/component destruction.
Outstanding client requests and theme listeners are cleaned up on destruction;
server writes already underway are not canceled. Standalone behavior is preserved.
See README for the integration example. No changes to backend or BPCIO repository.

## Branch selection (0.16.2)

Repository setup uses an editable ComboBox for branches. Load branches reuses the connection endpoint and existing authentication, after saving the repository URL. Connection results populate the dropdown without changing the selected branch. Manual entry supports new or empty repositories. URL changes, saved configuration and environment changes clear old branch results. No automatic network requests are added.

## Configurable BPC root folder (0.17.0)

ZBPC_GIT_REPO gains ROOT_FOLDER (CHAR255); configuration API uses rootFolder.
Default empty preserves the original layout. Normalized folder segments contain
letters/digits/underscore/hyphen. Remote maps logical BPC paths to the prefix
for reads, writes, history and Bitbucket source requests. Public file/hash/LFS
metadata is scoped and unprefixed; full Git objects/files are retained for push
so unrelated ABAP files survive. Metadata cache keys include root folder.
LFS pointer hashes use physical paths internally and root attributes receive
physical workbook paths. URL/branch/root changes clear old sync state. No file
migration or rename-following history is implemented; README describes the move.
Activate the expanded DDIC table before updated classes through abapGit.

## Root folder Save fix (0.17.1)

Form field presence detection is case-insensitive to handle SAP HTTP field-name normalization. Explicit blank rootFolder still clears the setting, while an omitted field preserves the saved setting. ABAP Unit covers uppercase, camel case, mixed case empty and omitted fields. SAP execution remains pending.

## Dimension member labels (0.17.2)

The overview carries memberDescription from BPC member metadata. UI displays decoded ID without .xml, followed by the description when available. Git-only members fall back to ID; no extra Git downloads are added. Git paths and serialized XML are unchanged. SAP backend compilation remains pending.
