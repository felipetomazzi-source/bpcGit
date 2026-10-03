# bpcGit: functional specification (v0.1, draft)

## 1. Goal

bpcGit is a web app on the BPC system that puts BPC content under Git version
control in a GitHub repository. The first release covers **EPM workbooks only**.

A user opens the app, connects it to a GitHub repository, picks the BPC
environment to track, and then commits workbooks to Git or restores them from Git.

## 2. Scope

### In scope (v1)

- Set up a GitHub repository connection: URL and branch. The Git login is
  asked only when the Git host needs it, as in abapGit (section 7.2).
- Bind that connection to one BPC environment (AppSet).
- List the environment's EPM workbooks and show each one's Git status.
- Commit selected workbooks to GitHub with a commit message.
- Restore (pull) selected workbooks from GitHub back into BPC.
- Show the commit history of a workbook.

### Out of scope (v1)

- Data Manager packages and data files,
  dimensions, BPF templates and the rest of the BPC content.
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
  `.TDM`/`.CDM` is the processed definition Data Manager runs. Both are
  tracked as separate files with the same statuses, commit and restore, so
  they should be committed and restored together.
- Files without an extension (one on dev,
  `AGGR_PROJECT\...\CONVERSIONFILES\CONV_RESTORE_AGGR_PROJECT`) are not
  tracked: Git paths are recognised by their extension.
- One rule decides what is tracked, for BPC and Git alike:
  `ZCL_BPC_GIT_SERVICE->GET_KIND` (path to kind).

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

   Conflicts are refused, as in F4. "Differs" can be committed or restored:
   commit makes BPC win, restore makes Git win.
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

For a selected workbook, the app lists its commits (SHA, author, date and
message). It gets them by fetching the branch with a deeper history through
abapGit's `UPLOAD_PACK_BY_BRANCH` (with `iv_deepen_level`), then decoding the
commits and keeping those where the file's blob changed. Each commit can be
restored with F5.

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
- Files in Git count as workbooks only below `<MODEL>/EEXCEL/` with a workbook
  extension; anything else (README.md, .bpcgit.json) is ignored.
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
| Service | `ZCL_BPC_GIT_SERVICE` | Orchestrates flows F1–F6 |
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
