# bpcGit: functional specification (v0.1, draft)

## 1. Goal

bpcGit is a web app on the BPC system that puts BPC content under Git version
control in a GitHub repository. The first release covers **EPM workbooks only**.

A user opens the app, connects it to a GitHub repository, picks the BPC
environment to track, and then commits workbooks to Git or restores them from Git.

## 2. Scope

### In scope (v1)

- Set up a GitHub repository connection: URL, branch, username and token.
- Bind that connection to one BPC environment (AppSet).
- List the environment's EPM workbooks and show each one's Git status.
- Commit selected workbooks to GitHub with a commit message.
- Restore (pull) selected workbooks from GitHub back into BPC.
- Show the commit history of a workbook.

### Out of scope (v1)

- Logic scripts, Data Manager files (transformation, conversion, package),
  dimensions, BPF templates and the rest of the BPC content.
- Private publications (`PRIVATEPUBLICATIONS\<user>\`) and temporary files.
- Branch management, merging and conflict resolution inside the app. These
  are done on GitHub.
- Testing against Git hosts other than GitHub. abapGit uses the plain Git
  protocol over HTTPS, so Bitbucket and GitLab should also work, but v1 is
  tested only against GitHub.

## 3. What counts as an EPM workbook

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

**Rule v1:** a workbook is any document (`DIR_DOC = 'D'`) under
`\ROOT\WEBFOLDERS\<ENV>\<MODEL>\EEXCEL\` (subfolders included) with extension
`.xlsx`, `.xlsm`, `.xltx`, `.xltm` or `.xls`.

On the dev system, `CH_PLANNING\AGGR_OPEX\EEXCEL\` contains files of this kind,
together with many `BACKUP\` folders and `COPY OF ...` files. See open question Q3.

## 4. User flows

### F1. Set up the repository

1. The user opens the app. If no repository is set up yet, the app opens the
   setup screen.
2. The user enters:
   - Repository URL (`https://github.com/<owner>/<repo>`)
   - Branch (default `main`)
   - GitHub username
   - GitHub personal access token (labelled as "password/token"). GitHub stopped
     accepting account passwords for Git and its API in 2021, so this must be a
     token.
3. **Test connection** calls `ZCL_ABAPGIT_GIT_TRANSPORT=>BRANCHES`. This checks
   the SSL setup and the credentials, then confirms that the branch exists.
4. **Save** stores the configuration.

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

The screen has filters by status and model, plus a search box.

### F4. Commit to Git

1. The user selects workbooks (usually "Modified in BPC" or "New in BPC") and
   enters a commit message.
2. The app reads each file's content from BPC and creates **one commit** on the
   configured branch containing all of the files.
3. The commit author is the BPC user, using a name and email kept in the
   configuration (see Q5).
4. The app updates the stored sync state and refreshes the overview.
5. The app refuses the commit if the branch has moved on since the overview
   loaded and any selected file is "Modified in Git" or "Conflict".

### F5. Restore from Git

1. The user selects workbooks (usually "Modified in Git" or "New in Git").
   Optionally, they pick a commit; the default is the branch head.
2. The app asks for confirmation, because restoring overwrites the content in BPC.
3. For each file, the app locks the BPC document, writes the content, and unlocks it.
4. The app refuses to overwrite a document that someone else has locked in BPC.

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

- For each tracked file, a Z table stores the BPC path, the Git blob SHA of the
  last synced content, the commit SHA, and the BPC last-change timestamp at
  sync time.
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
| Credential exit | `ZCL_BPC_GIT_ABAPGIT_EXIT` | Implements `ZIF_ABAPGIT_EXIT`. It is put in place at runtime and only for bpcGit's own requests (section 7.2). bpcGit does **not** ship `ZCL_ABAPGIT_USER_EXIT` |
| Config table | `ZBPC_GIT_REPO` | URL, branch, SM59 destination, environment, models, author |
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
- **Login without a popup:** when a request gets a 401 and no SAP GUI is
  available, `ZCL_ABAPGIT_HTTP->ACQUIRE_LOGIN_DETAILS` falls back to a password
  popup. That popup must never be reached from the web app, so credentials are
  always supplied before abapGit is called. They come either from the SM59
  destination (through the user exit) or from `LOGIN_MANAGER=>SET_BASIC` for a
  token entered in the session. A 401 is turned into a clean error for the UI.
- The login manager caches credentials in static data, which lives only for
  the ABAP session. Stateless REST calls therefore set them again on every
  request.

### 7.2 Credentials without a global user exit

abapGit looks for an exit class named exactly `ZCL_ABAPGIT_USER_EXIT`. A system
can have only one, and a customer may already have their own. If bpcGit
shipped that class, installing bpcGit would collide with the customer's class
or overwrite it. So bpcGit doesn't ship it, and it leaves an existing exit
untouched.

Instead, at the start of every request that calls abapGit, `ZCL_BPC_GIT_REMOTE`
does the following:

1. It calls `ZCL_ABAPGIT_EXIT=>GET_INSTANCE( )`. This returns abapGit's normal
   exit, which already passes calls on to the customer's
   `ZCL_ABAPGIT_USER_EXIT` if one exists. bpcGit keeps it as the *inner* exit.
2. It creates `ZCL_BPC_GIT_ABAPGIT_EXIT` around that inner exit.
3. It calls `ZCL_ABAPGIT_INJECTOR=>SET_EXIT( )` with the new object. This is a
   public method (checked on dev on 2026-10-03), and the injection only lasts
   for the current internal session.

`ZCL_BPC_GIT_ABAPGIT_EXIT` behaves like this:

- **`CREATE_HTTP_CLIENT`:** if the URL belongs to a repository set up in
  bpcGit, it returns a client from `cl_http_client=>create_by_destination`
  using the SM59 destination configured for that repository. For any other
  URL it passes the call to the inner exit.
- **All other methods:** passed straight to the inner exit, so the customer's
  exit logic still applies inside bpcGit requests.

What this achieves:

- **No naming conflict.** The class name is in bpcGit's own namespace.
- **No effect outside bpcGit.** The abapGit UI, background jobs and other users
  never see the injected exit, because it exists only in bpcGit's own sessions.
- **Upgrade risk stays inside bpcGit.** If abapGit adds a method to
  `ZIF_ABAPGIT_EXIT`, only `ZCL_BPC_GIT_ABAPGIT_EXIT` stops compiling, and only
  bpcGit is affected. abapGit itself keeps working. The fix is still to add the
  new method as a call to the inner exit.
- **Caveat:** `ZCL_ABAPGIT_INJECTOR` isn't part of abapGit's documented API.
  The same rule applies as for the other abapGit calls: only
  `ZCL_BPC_GIT_REMOTE` uses it.

### Constraints

- NetWeaver 7.52 / BPC 10.1: no ABAP syntax newer than 7.52.
- UI5 1.52 APIs only.
- abapGit serialization byte rules as in bpcIO (BOM in the metadata XML,
  CRLF line endings in `.abap` files, `.wapa` lines padded to 255 characters).
- The system needs outbound HTTPS to `github.com`. The GitHub certificate
  chain has to be imported in STRUST (SSL client PSE). abapGit's normal setup
  already covers this, and it works on the dev system.

## 8. Security

- **Token storage.** Do not store the token in plain text in a Z table. See Q1.
- **Authorization.** Only BPC admins of the environment can set up the
  repository and restore files. Committing needs at least read access to the
  files. The service checks this through the BPC user context.
- **Logging.** Never log the token or send it back to the UI. The setup screen
  shows it masked.

## 9. Open questions

- **Q1. Where is the token kept?** (a) encrypted in a Z table with SSF/`SECSTORE`,
  (b) in an SM59 HTTP destination maintained by Basis, with the app
  storing only the destination name, or (c) entered per session and never
  stored. **Decision (2026-10-03): (b) as the main option, with (c) as an
  optional extra.** Option (b) works through the user exit described in
  section 7.2. Option (c) holds the token only for the session, through
  `ZCL_ABAPGIT_LOGIN_MANAGER`.
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
- **Q3. Should BACKUP folders and `COPY OF ...` files be excluded?** Proposal:
  apply a default exclusion pattern that the configuration can change.
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
  it doesn't ship `ZCL_ABAPGIT_USER_EXIT`, because a customer may already
  have one. Instead it injects its own wrapper exit at runtime (section 7.2).
