# bpcGit

Version control for SAP BPC 10.1 (NW) content in Git: EPM workbooks, logic
scripts, transformation and conversion files, Data Manager packages and
package links, security definitions, BPF template designs and dimension members.
The app is a UI5 BSP application, installed with abapGit into package `ZBPC_GIT`.
Current version: **0.17.6**. Target runtime: ABAP 7.52 and UI5 1.52.

Choose an object type and optional model, then **Load**. Select objects to
commit, restore or inspect their history. EPM reports and input schedules have
separate load choices; **All objects** is available when you need the full scope.

Select one logic script, transformation, conversion, Data Manager package or
package link and choose **Diff** to compare Git with current BPC text/XML.
Transformation/conversion workbooks include their companion definitions;
their Excel content shows a binary change summary, rather than a cell diff.

- Development handover and outstanding checks: [docs/HANDOVER.md](docs/HANDOVER.md)
- Specification: [docs/SPEC.md](docs/SPEC.md)
- abapGit objects: `src/`
- Byte-format helper: `python tools/abapgit_fmt.py` (run with `--check` before
  committing; it normalises BOM, CRLF and the 255-column WAPA padding)

After pulling with abapGit, the app runs at
`/sap/bc/ui5_ui5/sap/zbpc_git/index.html?sap-client=<client>`.
Use this UI5 path, not `/sap/bc/bsp/sap/...`: the BSP runtime rejects host
names without a domain (`CX_FQDN`), such as `vhcalnplci`.

## Latest updates (0.17.6)

- Credential-bearing repository URLs remain intact on Save and reload. The
  transport extracts credentials without rewriting the configured address.
- Credential-bearing URL examples (placeholders only):

```text
https://x-token-auth:YOUR_BITBUCKET_TOKEN@bitbucket.org/WORKSPACE/REPOSITORY.git
https://YOUR_GITHUB_USERNAME:YOUR_GITHUB_PAT@github.com/OWNER/REPOSITORY.git
```

The colon between username and token is required. For example, `x-token-TOKEN`
without a colon produces **Repository URL credentials must contain user:token**.
Percent-encode reserved characters inside the username/token, such as `@` as
`%40`. The credential portion uses HTTP userinfo syntax; do not add `Bearer `.

The saved branch remains visible after refresh and loading branch choices.
- Repository URL storage is now **CHAR1024**. The initial CHAR2048 definition
  failed activation on the tested SAP system and has been corrected.
- The table XML now matches SAP's serialization of the built-in CHAR field
  (`ADMINFIELD` ordering, `MASK`, no `COMPTYPE`), fixing the repeated table diff.
  This last correction does not change the field's type or length.
- Dimension member labels show **ID - description**. Restores retrieve members
  and BPF templates by path; restored members are saved and processed once per
  affected dimension. Processing may activate other pending edits in that
  dimension; other object types do not trigger dimension processing.

Seven local regression suites and 22 UI5 1.52 browser assertions passed for the
URL/branch changes. Subsequent table corrections passed formatter and XML
checks. ADT returned HTTP 400 for the latest backend syntax checks. Latest SAP
activation, clean abapGit status and live URL/branch behavior need confirmation;
local checks do not establish SAP deployment success.

## Repository setup and login

Expand **Repository setup**, select a BPC environment, enter the HTTPS repository
URL and branch, then **Save** and **Test connection**. Regular Git access uses
abapGit; Bitbucket Cloud also has dedicated History and Diff API reads. Other
Git hosts retain the abapGit read path.

Use **Log in** for request-local Git credentials, or intentionally include
`user:token@host` in the repository URL. bpcGit preserves that URL when editing,
saving and reloading setup, including the credentials. The saved URL is stored
in `ZBPC_GIT_REPO` and returned to authorized environment users; it supports up
to 1,024 characters. The backend extracts credentials for Git, Bitbucket API and
LFS requests without changing the saved URL. An explicit Log in overrides the
URL credentials for that request; Log out clears the tab login, not the saved
URL credentials. To remove those, edit the URL and Save.

For a Bitbucket repository access token, use `x-token-auth` as the username;
for a Bitbucket API token, use your Atlassian account email. For GitHub, use your
GitHub username and personal access token. Enter tokens without a `Bearer`
prefix. Fine-grained GitHub tokens need **Contents: Read-only** for pulls or
**Contents: Read and write** for pulls and pushes. See
[GitHub's token setup guide](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

The saved branch remains visible after refreshing setup, even before loading
branches or when the branch is absent from the advertised list. You can select
an existing branch or type a new name.

SAP HTTPS configuration must support SNI and trust the Git/API hosts. Bitbucket
History and Diff require access to `api.bitbucket.org` in addition to
`bitbucket.org`. Connection failures display SAP's HTTP/TLS diagnostic details.

## Large EPM workbooks with Git LFS

Git LFS is optional and currently supports **Bitbucket Cloud** only:

1. Expand **Repository setup** in bpcGit.
2. Check **Use Git LFS (Bitbucket Cloud)**.
3. Set the threshold in MB (default **5**, allowed range **1–100**).
4. Click **Save**, then commit a changed qualifying EPM workbook.

The option defaults to off, including existing repository configurations.
It applies to company/team EPM reports, input schedules and other Excel workbooks
under `EEXCEL`. Data Manager transformation/conversion workbooks and generated
definitions remain in regular Git. The maximum LFS transfer size is **128 MB**;
1 MB means 1,048,576 bytes.

bpcGit uploads the workbook before pushing its SHA-256 pointer and adds exact
root `.gitattributes` rules in the same Git commit. Overview comparison uses
pointer hashes without downloading LFS workbook bytes. Current and historical
restores download the actual workbook and verify its size and SHA-256 before
writing it to BPC. Nested `.gitattributes` affecting the workbook must be
consolidated at the repository root first.

Existing history is retained: previously committed binaries switch to LFS only
on a future changed, qualifying commit. Enabling the setting does not upload
existing files automatically or remove older binaries from Git. Bitbucket's
LFS page may therefore show **No Git LFS files** until that first commit.
Existing nonempty LFS workbooks continue using LFS when they shrink below the
threshold; turning the option off prevents further writes to them. Reading,
restoring and deleting existing LFS files remain available.

Bitbucket LFS permissions/storage quota and SAP HTTPS trust/connectivity to the
LFS storage hosts are required. A failed upload prevents Git push; a later
failed push can leave an unreferenced LFS upload without recording a successful
BPC sync. See [the LFS specification](docs/SPEC.md#opt-in-git-lfs-for-large-epm-workbooks-0160)
for transfer and pointer-format limits.

Local UI/Git compatibility checks and SAP activation passed. Live Bitbucket LFS
upload/restore acceptance remains pending; SAP Unit execution is currently
blocked by an ADT HTTP 400 error.

## REST API

Base path: `/sap/bc/zbpc_git` (handler `ZCL_BPC_GIT_HTTP`)

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/ping` | Caller, system, client and the installed abapGit version |
| GET | `/environments` | BPC environments the user may access |
| GET | `/models?environment=<id>` | Authorized models; no Git pull or file comparison |
| GET | `/dimensions?environment=<id>` | Supported accessible dimensions; no member scan or Git comparison |
| GET | `/config?environment=<id>` | Repository setup of an environment |
| POST | `/config` | Save it (`environment`, `url`, `branch`; optional `rootFolder`, `lfsEnabled`, `lfsThresholdMb`) |
| POST | `/connection` | Test the connection (`environment`; optional `user`, `token`) |
| POST | `/diagnostics` | Independent smart-HTTP read/push-advertisement checks (`environment`; optional `user`, `token`); no Git/BPC write |
| POST | `/workbooks` | Tracked files in BPC and Git with their status (`environment`; optional `kind`, `model`, `dimension`, `user`, `token`); returns stage timings |
| POST | `/commit` | Commit selected files (`environment`, `message`, `commit` = head seen, `paths` one per line; `user`, `token`) |
| POST | `/restore` | Write a Git version into BPC (`environment`, `commit` = head seen, `paths`; optional `version`, `depth`, `user`, `token`) |
| POST | `/history` | Changes to one item (`environment`, `path`; optional `depth`, `user`, `token`) |
| POST | `/diff` | Current Git/BPC content for one supported item (`environment`, `path`; optional `user`, `token`) |

With no saved URL credentials or explicit tab login, Git requests first run
without credentials. When the
Git host wants a login, the API answers 403 with `"authRequired": true` and the
app asks for user and personal access token, keeps the token in the browser tab's `sessionStorage`,
and retries. Only the explicit login user name persists in `localStorage`; tab credentials are
never stored on the server.

`/diagnostics` reports credential presence, request-local source and non-secret
username, then checks `GET <repo>/info/refs?service=git-upload-pack` and
`GET <repo>/info/refs?service=git-receive-pack` separately. Each check includes
the intended auth scheme, URL, status, status source, elapsed milliseconds,
outcome and sanitized error. Tokens, Basic headers and response bodies are
excluded. Failure of the read check does not suppress the push check. A status
of 0 means abapGit did not expose a numeric status; this is not an HTTP response
code. Successful push advertisement is a permission preflight, not a test push.
REST URL/auth metadata are also returned, with `restChecked=false`.

Smart HTTP uses abapGit's request-local Basic login; Bitbucket REST reads use
Bearer for `x-token-auth`, Basic for other usernames. `ZBPC_GIT_REPO` stores
repository settings, including intentionally embedded URL credentials. There is
no environment-keyed secure store, SSF lookup or shared browser abapGit login in this service. The constructor
clears the login manager before setting the supplied request credentials.
Both Git-host 401 and 403 now produce `authRequired=true`; a 403 can also mean
insufficient repository permission, so it does not prove a bad password.
Pull/activate the new ABAP classes through abapGit to expose this endpoint.

POST requests must carry `X-Requested-With: XMLHttpRequest` (jQuery sets it), so
a form on another website cannot change data with the user's session.

## Data Manager content

Packages and links have their own object type choices before loading. Packages are XML files
under `DATAMANAGER/PACKAGES/<group>/`; links are under `DATAMANAGER/PACKAGELINKS/`.
Team packages use the team path. Package scripts have one XML line per step;
link IDs are removed in Git and restored using the target system's ID.
Generated XML has no BPC last-change timestamp. Duplicate names or sanitized
path collisions are unsupported; resolve these names before tracking them.
The REST endpoints are unchanged. See specification section 3.4.

Package listing and Diff have been checked in the SAP browser. Commit/restore
acceptance still needs representative package/link XML, an edited script/link,
a team package and a package using its chain's default script. Confirm a second
refresh shows Unchanged after each successful action.

Transformation and conversion workbooks each appear once in the overview.
Their status, commit, and restore include the paired definition automatically.
A restore succeeds for the pair together; a failure rolls back the pair.

Select one item and choose History to inspect its earlier versions. Load older
history extends the recent branch range to at most 1,000 commits. Restoring an
older version changes BPC and leaves it ready to commit; it does not move Git.
Local UI regression checks: `node tests/history_ui.test.cjs`.

History initially examines 20 first-parent branch commits; **Load older history**
extends that range by 20 up to 1,000. Bitbucket Cloud uses commit/path metadata
APIs instead of downloading Git file content for History, with authorized,
head-checked metadata caching. Other hosts retain the abapGit history path.

## Scoped loading and performance

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

The load choices are EPM reports (default), EPM input schedules and Other EPM
workbooks, alongside the other supported object types. The API accepts REPORT,
SCHEDULE and OTHER scopes while retaining WORKBOOK for older clients. Company
reports/schedules list their specific library; team listings filter by the
library directly beneath EEXCEL before comparing content. Git-only files use
the same classification. Other covers books, distribution lists and remaining
workbook paths; All objects continues to include all supported objects.

Diff skips the full status comparison. For Bitbucket Cloud it normally fetches
only the selected Git paths at a freshly authorized, pinned head (a raw-source
LFS redirect falls back to reading its pointer through Git). A regular selected
Git file has a 16 MB Diff read limit. Text rendering also has bounded size/row
limits; large content reports its limit explicitly.

Single-object commits validate only selected paths and required companions.
After a successful push, the Git metadata cache is updated so the following
refresh can avoid downloading the same repository content again. Commit still
requires a fresh Git snapshot, and BPC listing/serialization plus the refresh
remain scoped operations. These changes do not guarantee constant-time commits;
older large binaries in Git history can still affect transfer time.

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
other local members. Restore then validates and processes each affected dimension
once, including other pending member edits. If a member save fails, processing
is skipped for that dimension. Processing failures report that the working copy
was saved but activation was not confirmed; correct the errors in BPC and process
the dimension. Other object types do not use this processing step.
Properties/hierarchies must already exist with a matching schema, and referenced
parents/members should be available first. Descriptions use the SAP session
language. Member deletion and transaction data remain outside Git restore.

## Embed in the BPCIO hub

The integration contract was agreed with the BPCIO integration before implementation.
The namespace remains `bpc.git`; its separate BSP component URL is
`/sap/bc/ui5_ui5/sap/zbpc_git/`. The repository and `/sap/bc/zbpc_git/` backend
remain independent. Use the existing host UI5 core (1.52+) and load the component,
without loading its standalone `index.html` or bootstrapping UI5 again:

```javascript
var git = sap.ui.component({
  name: "bpc.git",
  url: "/sap/bc/ui5_ui5/sap/zbpc_git/",
  settings: { embedded: true, environment: selectedEnvironment }
});
git.attachNavigateBack(function (event) {
  showHub(event.getParameter("environment"));
});
var container = new sap.ui.core.ComponentContainer({
  component: git, height: "100%", width: "100%"
});
```

The host loads `sap/ui/core/ComponentContainer` before creating the container.
No `componentData` is required. The embedded component hides its page header,
disables its environment selector, and inherits the host theme, including later
theme changes. The hub owns its header and Back button. The host can call
`git.requestNavigateBack()` to raise `navigateBack({ environment: string })`.
The component does not change the host route itself.

Call `git.setEnvironment(selectedEnvironment)` when the hub selection changes.
This clears the previous overview, closes dialogs, and loads configuration and
model metadata for the authorized environment; object comparison remains explicit.
An empty or unauthorized environment shows a message, with no fallback to a
remembered standalone environment. Old environment responses are ignored.
Embedded selections do not change the standalone saved environment.

Keep the same component when navigating back if the hub should retain Git state.
When disposing it, destroy both its container and component; pending client
requests and theme listeners are cleaned up. Avoid switching or disposing during
a commit or restore: discarding a client response cannot cancel a server write
already in progress. Git credentials retain the existing tab-session behavior.

Standalone `index.html` remains supported, with its own header, selectable
remembered environment and Belize bootstrap theme. The BPCIO host implementation
is maintained separately; this change prepares the bpcGit side of the contract.

Repository setup offers a branch dropdown. Save the repository URL, then choose **Load branches** (or **Test connection**) to populate it. Private repositories use the existing Git login prompt. Select an existing branch or type a new branch name, then Save. Branch discovery is explicit and does not add startup requests.

## Share a repository with ABAP objects

Set **BPC root folder** in Repository setup to `bpc` (or a nested folder such as
`content/bpc`). Empty keeps the existing repository-root layout. Leading/trailing
slashes are removed; folder segments allow letters, digits, underscores and
hyphens. Comparison, commit, restore, diff, history and LFS all use this folder.
UI and API object paths remain relative to the BPC root. `GET/POST /config`
exposes `rootFolder`; clients should include it when saving configuration. Older
clients omitting the field preserve the saved folder; an explicit empty value
selects the repository root.

For example, keep ABAP files in `src/` and BPC files in `bpc/`. Configure abapGit
separately to serialize only its intended ABAP area. bpcGit preserves the full
Git tree and stages only selected BPC paths. LFS may also update root
`.gitattributes`, adding rules for the prefixed workbook paths while preserving
existing entries. Existing nested-attribute restrictions still apply.

For an existing repository, first move its BPC model/security/dimension folders
into the chosen folder in a separate Git commit, preserving other files and
updating any LFS rules. Then save the matching BPC root folder in SAP and reload.
No automatic migration is performed: changing the setting alone makes the old
root-level files appear absent. Earlier history before the move uses old paths
and is not automatically followed across the rename. Back up and plan this move
before changing a populated repository. Changing URL, branch or root folder
clears the environment's old sync baselines, so a subsequent comparison can
report differences without an old three-way baseline. Existing single-environment
per repository restriction remains in place.

Dimension members display `ID - description`, using the current BPC working-copy description. Members without a description, including Git-only members, display the ID without `.xml`. Stored Git paths remain unchanged and no extra Git content downloads are needed for labels.
