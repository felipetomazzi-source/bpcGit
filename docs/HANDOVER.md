# bpcGit: handover

## Current handover - 2026-10-07 (read this before the historical notes)

### Project and working rules

Workspace: `C:/Users/FelipeTomazzi/projects/bpcGit`. Code repository:
`https://github.com/felipetomazzi-source/bpcGit.git`, branch `main`.
Application version is **0.19.0**. This code repository
is distinct from the customer repositories holding serialized BPC content.

Read `AGENTS.md`, this section and `docs/SPEC.md` before implementing. Target
ABAP 7.52, UI5 1.52 and ES5 JavaScript. Run `python tools/abapgit_fmt.py`, then
`--check`, after changes under `src/`. Commit and push completed tasks to
`origin/main` without asking. Preserve unrelated work. `.dummy_bitbucket` is an
untracked local credential file: never commit, print or copy it.

SAP access: use the `npl-adt` MCP only for reading/checking SAP code and data
(do not use `npl-bpc` for that; do not write SAP source directly). Both MCP
servers read `NPL_URL` (`https://bpc.kwickast.co.nz/` from home,
`http://vhcalnplci:8000` at work). Same NPL system, client 001.

Deployment: after every push, pull into SAP with `npl-adt` gitPullRepo, repoId
`000000000006` (package ZBPC_GIT, `refs/heads/main`), transport `NPLK900106`
(without a transport the pull fails "Transport not found"). The pull may return
`{"status":"success","result":[]}` WITHOUT applying anything: always verify,
e.g. `/sap/bc/adt/filestore/ui5-bsp/objects/ZBPC_GIT%2fmanifest.json/content`
shows the pushed version, `DWINACTIV` has no `ZCL_BPC_GIT%` rows, and ABAP Unit
passes. Retry once; otherwise ask the user to pull manually. Activation of
anything left inactive and browser testing remain with the user.
Never echo `gitRepos` output: repository URLs there embed tokens.

### Open items, in order

1. **0.18.2 is in SAP (2026-10-07).** Two pulls of 0.18.1 returned success
   without applying anything; the pull of 0.18.2 (`8caed86`) applied. SAP
   serves 0.18.2, no ZCL_BPC_GIT* object is inactive, ABAP Unit passes for
   ZCL_BPC_GIT_TRANSPORT (4) and ZCL_BPC_GIT_HTTP (1); ZCL_BPC_GIT_SERVICE
   has no tests. 0.18.2 fixes logic scripts: BPC transports them per script
   (`ADMINAPP\<model>\<name>.LGF`, seen in the customer UJT_GUID), not per
   model folder. A folder entry `ADMINAPP\DEMREV` recorded by 0.18.x at the
   customer should be removed from its request.
   0.18.3: the "already in the request" check ignored nothing, so an object
   held by a released task and deleted from the request was skipped yet
   reported as recorded. Now only the request and open tasks (D/L) count.
2. **Cloudflare cache.** `bpc.kwickast.co.nz` is behind Cloudflare, which caches
   `/sap/bc/ui5_ui5/...` files for a year (SAP sends max-age=31536000). The
   user's browser ran a 2-day-old App.controller.js with a new view, so the
   root folder field showed empty and the header showed "Branch: undefined".
   Saving was never broken (ZBPC_GIT_REPO root_folder = `bpc`). The user was
   told to purge the cache and add a Cache Rule bypassing
   `/sap/bc/ui5_ui5/*`. Confirm it was done (Claude in Chrome: fetch
   `controller/App.controller.js` and check `cf-cache-status` / content). An
   app-side cache-buster was offered but not built.
3. **Transport features untested live.** Nobody has yet created a request,
   recorded objects, or released/imported one. Suggested first test: restore
   or "Add to transport" one EPM workbook with a new request, then check
   SE09/SE10 for `R3TR ABPC <GUID>` in the user's task (and the E071/UJT_GUID
   rows via ADT) before releasing.
4. Older pending validations still apply: Bitbucket history/diff/LFS routing
   live, live LFS upload/restore (now possible after the 0.17.7 fix), member
   restore processing on an authorized test dimension.

### Built in this session (2026-10-06/07)

| Commit | Version | Change |
| --- | --- | --- |
| `6355363` | 0.17.7 | LFS pointer parse fix |
| `cfdb0fd` | 0.17.8 | Repository setup panel at top, repo/branch in header |
| `edddffe` | 0.17.9 | "Change" link in the setup header |
| `698ca54` | 0.17.10 | Branches load when the branch dropdown opens |
| `8543551`, `3e5e603`, `c8dd869` | 0.18.0 | Customizing transport on restore |
| `605c738` | 0.18.1 | "Add to transport" without restoring |

Confirmed in SAP at the start: ZBPC_GIT_REPO URL is CHAR1024 and active; the
serializer alignment (`1538d14`) left no diff; ADT reads/unit tests work.

**0.17.7 LFS fix.** `ZCL_BPC_GIT_LFS=>PARSE` rejected every canonical pointer
(ABAP SPLIT creates no empty segment for a trailing newline), so LFS upload,
download and comparison could never work. Now: 3 lines + exact canonical text
match. ABAP Unit for LFS and remote classes all pass in SAP.

**0.17.8-0.17.10 UI.** The Repository setup Panel sits above the load
controls; its headerToolbar shows the saved repository (`repositoryLabel` strips
scheme, userinfo and `.git`) and saved branch (`/savedRepositoryLabel`,
`/savedBranch`, set in `_showConfig`). UI5 1.52 has no ValueState
"Information". "Change" (`onChangeRepository`) expands the panel and focuses
`branchInput` after the slideToggle (`$().children(".sapMPanelContent")
.promise()`). Opening the branch ComboBox calls `onBranchListOpen` via
`getPicker().attachBeforeOpen` in `onInit` (protected API; `loadItems` only
fires for empty lists): loads branches once per saved URL; "Load branches"
remains as refresh.

**0.18.0 customizing transports on restore.** Researched in SAP: BPC's own
transport (`CL_UJT_TRANS_MGR=>CREATE_REQUEST`) creates type W requests with Q
tasks and appends `R3TR <tlogo> <GUID>` via TR_APPEND_TO_COMM. GUIDs map BPC
entities in `UJT_GUID` (RSTLOGO `ABPC`); `UJT_ENTITY_CLASS-F_GENERIC_TLOGO = X`
means E071 object `ABPC`, otherwise the entity type itself. `CL_UJT_TLOGO_ABPC`
exports content at release; `UJT_TLOGO_AFTER_IMPORT` imports. The user
confirmed requests must be customizing and use the default layer.
`ZCL_BPC_GIT_TRANSPORT`: `open_requests` (W, status D, this client, user has an
open task), `create_request` (TR_INSERT_REQUEST_WITH_TASKS, no target),
`check_request`, `entity_for_path`/`package_entity`/`link_entity`, `record`
(reuses UJT_GUID mapping or generates via `CL_UJT_UTILITY=>GENERATE_GUID` and
inserts it; skips entries already in the request; all-or-nothing). Entity
formats, confirmed against CH_PLANNING UJT_GUID rows:
- EPM workbook `AFLE`, model, `COMPANY\EEXCEL\...` or `<team>\EEXCEL\...`
- Transformation/conversion `ADMF`, model, `COMPANY\DATAMANAGER\<folder>\<name>`
  without extension (definition + workbook are one entity)
- Logic scripts `ASPR`, model, `ADMINAPP\<model>\<name>.LGF` (per script;
  fixed in 0.18.2, before that the whole model folder was recorded)
- Package `ADMP`, `CL_UJD_ENTITY_ADMP=>CONCAT_ENTITY_ID(team, group, id)`
- Link `ADML`, model, link name; members `AMBR`, dimension (whole dimension)
- BPF `ABPF`, `UJB_TMPL_HDR-TMPL_GUID` by `TECH_NAME`; team `ATEM`, task
  profile `ATPF`, data access profile `ADAF`, by ID
Deletions are not recorded (BPC uses UJT_TRANS_DEL). HTTP: `GET /transports`,
`POST /transport` (text), restore field `transport` (checked before any BPC
change; response member `transport` {request,count,error,skipped}; only
successful results recorded). UI: `_createTransportPicker` in both restore
dialogs; UI5 1.52 Select needs a non-empty key for "No transport request"
(`__NONE__`).

**0.18.1 Add to transport.** Toolbar button "Add to transport (n)", enabled
when all selected rows are in BPC. `POST /transport/record` (environment,
transport, paths) maps paths with `ZCL_BPC_GIT_SERVICE=>TRANSPORT_ENTITIES`
from BPC only (files need the UJF_DOC document; packages/links use BPC's own
definitions via list_packages/list_links) and records them with the same
`record`. Picker required mode: no "No transport" option, last or first open
request preselected.

Checks: Node 9/9 suites (`tests/transport_ui.test.cjs`,
`tests/repository_summary_ui.test.cjs` added); OPA 7/7 and embedded 22/22 in
the actual UI5 1.52 harness (mock API); ABAP Unit for ZCL_BPC_GIT_TRANSPORT
(4 entity-format tests) passed in SAP for 0.18.0.

### Entry points and files

Standalone URL: `/sap/bc/ui5_ui5/sap/zbpc_git/index.html?sap-client=001`.
API: `/sap/bc/zbpc_git/`, handler ZCL_BPC_GIT_HTTP (POSTs need header
`X-Requested-With: XMLHttpRequest`). Component namespace `bpc.git`; BPCIO
embeds it; preserve standalone operation.

- `src/zbpc_git.wapa.controller_-app.controller.js`, `..._view_-app.view.xml`
- `src/zcl_bpc_git_http.clas.abap`, `src/zcl_bpc_git_service.clas.abap`
- `src/zcl_bpc_git_transport.clas.abap` (+ testclasses)
- `src/zcl_bpc_git_lfs.clas.abap`, `src/zcl_bpc_git_remote.clas.abap`
- `tests/*.test.cjs`, `tests/opa/` (harness, `node tests/opa/server.cjs`,
  http://127.0.0.1:4173 and /embedded.html)

Useful commands:

```text
python tools/abapgit_fmt.py
python tools/abapgit_fmt.py --check
git -c core.whitespace=-blank-at-eol diff --check
node --test tests/*.test.cjs
node tests/opa/server.cjs
```

This file is cp1252; README/SPEC are UTF-8. WAPA lines are padded to 255
characters by the formatter.

## Historical implementation notes (may describe superseded behavior)


Written on 2026-10-03 at the end of the first build session, for the agent
that continues the work. Read this first, then `docs/SPEC.md`, the
functional spec. The spec is kept up to date and records every decision with
its reason.

## Embedded integration update (2026-10-05)

Authentication investigation (2026-10-05): refreshed Windows User MCP Git
credentials resolved CH_PLANNING access to chorus_bpc_workspace/chorus_bpc.git.
SAP connection/read/push advertisement and scoped DEMREV comparison succeeded
(29 scripts); workstation REST and both advertisements returned 200. Prior
User credentials failed the same workstation smart-HTTP checks, so the failing
credential did not demonstrate a SAP-only transport fault. No BPC/Git writes.
New `/diagnostics` separates read/push checks and reports presence/source/scheme,
non-secret username, URLs/statuses/timings without secrets. Fixes 403 authRequired
classification. Remote class ADT syntax checked; HTTP handler depends on the
new remote public method. Pull/activation and ABAP Unit execution remain required.

0.16.1 prepares the independent `bpc.git` component for the BPCIO hub. Contract
was coordinated with the BPCIO chat "Read project documentation" before coding.
See README for URL, settings, setter, navigation event and ownership details.
Host changes are not part of this repository. Browser harness `embedded.html`
uses the actual UI5 1.52 component factory to test settings timing, authorization,
environment switching, navigation, theme inheritance and standalone recreation.
The lifecycle regression test also checks stale A->B->A replies and destruction.
SAP deployment is through the user's abapGit pull and activation.

## Current update (2026-10-03)

0.16.0 adds opt-in Bitbucket Cloud Git LFS for large EPM workbooks. Repository
setup defaults off with a 5 MB threshold (1–100 MB). ZBPC_GIT_REPO gains
LFS_ENABLED/LFS_MB; ZCL_BPC_GIT_LFS implements basic batch/upload/verify/download,
canonical pointer parsing, SHA-256 verification and exact root attributes.
Status/hash cache and sync baselines understand pointers without large-object
downloads. Current/historical restore resolves pointers before BPC writes.
Only future changed workbook commits convert; old Git history is retained.
Nested attributes, malformed/extended pointers and transfers over 128 MB are
refused. Existing LFS writes require opt-in; reads work with it off. No workbook
or BPC content has been changed during implementation. Formatter, LFS setup UI, Diff/history/scope/login regressions and real Git/LFS
pointer/quoted filename compatibility checks pass. ABAP Unit fixtures cover
upload/verify, existing objects, corrupt downloads, headers, thresholds and
local pointer hash comparisons; execution in SAP is pending. ADT source and
syntax calls still fail HTTP 400. Playwright pulled/activated all changes via abapGit. Running app shows
0.16.0, API Connected, LFS unchecked/5 MB, and toggling it enables the threshold
control. No setup Save or BPC content write/commit was performed. SAP Unit run
also fails ADT HTTP 400; live Bitbucket LFS upload/restore remains unverified
without a current Git login. Follow-up normalizes XFELD table serialization
and uses SAP's SHA256 algorithm identifier.

0.15.8 limits commit status comparison to selected paths and transformation/
conversion companions, preserving grouping/conflict checks. After successful
abapGit push, the fresh branch path/hash index is published to the existing BG
metadata cache so the subsequent refresh can avoid another full Git download.
Commit still pulls fresh Git content; generated BPC listing/serialization and
post-action BPC refresh remain scoped but may be expensive. No custom Git writer,
REST push or history rewrite is introduced. Formatter and Diff/history/scope/
login UI checks pass. ADT is still failing HTTP 400; SAP validation/deployment
results: Playwright pulled/activated the remote/service/BSP changes through
abapGit and repository reported zero local/remote changes. Running app shows
0.15.8 and API Connected; configured CH_PLANNING Bitbucket repo is unchanged.
No BPC content was committed for testing; the new browser has no Git login,
so actual commit timings remain unmeasured. ADT checks are still blocked by
HTTP 400. A follow-up makes post-push cache export best effort so cache errors
cannot prevent recording successful push sync state.

0.15.7 removes Diff's full status comparison. BPC listing still covers the
selected kind/model (generated providers still serialize that scope). Bitbucket
Diff now reads only selected path(s) at a freshly authorized, pinned Git head;
other hosts retain full abapGit branch content. Raw binary GETs bypass metadata
cache, distinguish empty/missing files and refuse redirects (including LFS),
with a 16 MB selected-Git-file limit. No state/content mutation is performed.
Formatter and Diff/history/scope/login UI regressions pass. ADT source read and
syntax-check calls both fail HTTP 400, so SAP syntax validation is outstanding.
User pull/activation and selected-file API/binary/latency verification pending.

0.15.6 exposes SAP's HTTP connection error code/message before closing the
client. The current token is redacted. Formatter, History UI regression and
ADT main-source syntax checks pass. User pull/activation and a retry are needed
to identify the actual TLS/network failure.

0.15.5 addresses continued Bitbucket History latency in deployed 0.15.4:
Bitbucket Cloud URLs now use GET metadata APIs (commit headers, path-filtered
first-parent diffstat, and pinned-head file presence), avoiding Git pack/blob
downloads for history. Other hosts retain abapGit history. Existing Git head,
SAP authorization, paired completeness and restore validations remain.
Bitbucket REST uses bearer auth for x-token-auth, otherwise Basic auth; API
tokens require the Atlassian email user. SAP must trust/reach api.bitbucket.org.
API errors are explicit, with no silent fallback to a slow pack download.
Immutable API metadata also uses a user/repository/URL scoped BI shared buffer,
so extending history does not repeat cached requests; branch Git access is
checked first. Redirects are disabled, replies bounded to 1 MB, HTTP timeout
30 seconds. Response bodies containing credentials/errors are never cached.
Formatter and history/diff/scope/login regressions pass; ADT main-source syntax
passed with no errors/warnings. Public atlassian/aui commit-header and filtered
diffstat endpoint smoke checks passed. New ABAP fixture tests cover incomplete
and deleted pairs, root/first-parent semantics, depth and partial-page refusal;
they await activation and execution in SAP. Private-repository API permission,
SAP TLS and performance verification remain for the user's pull/browser test.

0.15.4 reduces History overhead: direct scope authorization replaces the BPC
status overview; raw abapGit upload-pack avoids materializing all branch files.
History results use a head-checked, user/repository/path/depth scoped shared
buffer cache (BH). UI opens 20 branch commits and expands by 20 up to 1,000.
Cold pack downloads still contain blobs; no measured live speedup is claimed.
Restore status validation is unchanged. Formatter and history/diff/scope/login
regressions pass, including history restore depth and the 1,000-commit limit.
ADT syntax passed for remote (no warnings) and service (30 existing ABAP Doc
warnings), with no errors. Awaiting user pull/activation and browser timing.

0.15.3 imports credentials from pasted HTTPS repository URLs into the existing
tab-session login, clearing credentials from the URL before configuration Save.
URL input change also performs the import; long pasted tokens are not truncated.
Login-import tests cover encoding, long tokens, token punctuation, clean URLs,
and malformed/missing credentials. Formatter and Diff/scope/history checks pass.
Frontend-only change; awaiting user abapGit pull/activation and browser check.

0.15.2 extends Diff to Data Manager package links using the existing generated
link XML, model access checks and escaped line-by-line renderer.
Formatter and Diff/scope/history regressions pass. ADT syntax check reports no
errors (30 existing ABAP Doc warnings). Awaiting user abapGit pull/activation
and browser verification.

0.15.1 extends Diff to Data Manager packages, comparing generated canonical
package XML (settings and script representation) against Git without UJF reads
for generated objects. Package selection enables the existing Diff dialog.
Deployment and browser acceptance passed: abapGit pull/activation reported zero
changes; Playwright loaded 416 packages and opened AGGR_OPEX_CALC.xml Diff.
The new-in-BPC package displayed its 782-byte definition as additions, including
group, description, process chain, user group and individual script lines.
Diff/scope/history regressions and ADT syntax passed (existing ABAP Doc warnings
only). No package was modified or committed to the BPC content repository.

Version 0.15.0 adds Diff for one logic script, transformation or conversion.
POST /diff reads the current Git head and BPC file(s), with environment/model
access checks. Paired workbooks include their TDM/CDM text definitions; Excel
bytes have a binary summary, not a cell diff. UI shows line numbers and escaped
red/minus Git versus green/plus BPC text, with explicit large-content limits.
Diff is read-only. Diff/scope/history regressions and ADT service syntax pass;
HTTP syntax passes with a signature stand-in for the new service method before
deployment. SAP browser validation is recorded below when completed.

0.15.0 deployed acceptance (2026-10-04): pulled main through abapGit and activated
the changed BSP pages; repository reported zero changes. Playwright opened Diff
for AGGR_OPEX_CALC.LGF and verified the existing comment edit appears as Git-minus
and BPC-plus with correct line numbers. IMPORT.XLS shows differing workbook bytes
but identical IMPORT.TDM, including the comma delimiter. CONVERSION.XLS is new
in BPC; its companion CONVERSION.CDM renders all conversion rules as additions
against missing Git content. Source-like XML/JavaScript appears as literal text.
No BPC content or content-repository commit/restore was performed. Full HTTP
syntax also passes against the installed service API after deployment.

2026-10-04: `tests/opa` adds a local OPA5/QUnit browser harness against the real
BSP frontend and pinned OpenUI5 1.52.48, with read-only mock responses. The first
dimension-selection/load journey passes all seven assertions in Chromium driven
by Playwright. It checks actual controls, bindings and rendered member names;
it does not replace deployed SAP backend acceptance. See tests/opa/README.md.

2026-10-04 deployed smoke test: the user explicitly authorized browser access
and abapGit pull/activation. Playwright used SAP GUI for HTML transaction
ZABAPGIT to pull main into ZBPC_GIT and activate the BSP pages; abapGit then
reported zero local/remote changes. The deployed application reports 0.14.0
on SAP UI5 1.52.18. Dimension-member metadata loads, defaults to ACCOUNT and
disables model selection. ACCOUNT loaded 958 members in 4.8 seconds (SAP listing
239 ms, Git 4110 ms, comparison 337 ms), all New in BPC. Selecting one enables
Commit and History while Restore stays disabled. History opens successfully
and reports no changes for the uncommitted member. No BPC member save/restore,
processing or content-repository commit was performed during this smoke test;
those acceptance cases remain pending. Browser SAP/abapGit access was expressly
authorized by the user; ADT source writes remain outside the approved workflow.

2026-10-04 new-member acceptance: at the user's explicit request, the BPC MCP
created ACCOUNT member BPCGIT_TEST_20261004 in CH_PLANNING, description
"bpcGit new-member detection test", ACCTYPE=AST, LOCKED_FOR_PLANNING=N.
The native Save succeeded with processing disabled. Reloading ACCOUNT through
Playwright increased the total from 958 to 959; searching the ID showed exactly
one row, BPCGIT_TEST_20261004.xml, status New in BPC, location Dimension ACCOUNT.
Load took 0.8 seconds (listing 226 ms, Git 378 ms, comparison 78 ms). This proves
saved unprocessed additions are visible. The test member remains in the working
copy and has not been processed or committed to the BPC content repository.

Packages and links are implemented; SAP acceptance is pending. Version 0.9.3
groups transformation/conversion workbooks with their definitions into one
overview row and one commit/restore selection. Pair restore is transactional
and verifies the written Data Manager content. History was the next step.
Version 0.10.0 adds History for one selected item and restore of complete
historical versions, including workbook/definition pairs. History follows up to
1,000 first-parent branch commits. Historical restores preserve the current
head comparison baseline so restored older content can be committed. Local UI
regressions pass; remote class syntax and service/handler syntax with stand-ins
for new cross-class APIs were checked through ADT. Full activation and SAP
acceptance remain the user's abapGit/browser steps.
Version 0.11.0 adds explicit type/model Load at startup, backend scoped listing,
head-validated Git metadata reuse and stage timings. Scoped loading and history
UI regression tests pass. ADT checked the complete remote source; service/HTTP
checks use stand-ins only for cross-class APIs not yet installed in SAP.
User confirmed the prior restore/history workflow works. This release still
needs abapGit pull/activation and browser acceptance, including scoped pairs,
Git-only files, model switching, and first-load versus refresh timing.
Version 0.11.1 adds optional All objects loading; EPM workbooks stays the default.
Version 0.12.0 adds environment-wide security team, task profile and data access
profile definitions through ZCL_BPC_GIT_SECURITY. Users/assignments stay local
(explicit user choice). P0011 is required. XML is canonical and uses native BPC
read/create/update APIs; deletion and default-profile restore are refused. ADT
checked the provider in an existing class context, HTTP directly and service with
new-provider signature stand-ins. UI/history checks pass. Security write acceptance
must be tested after user pull/activation; no SAP objects/data were written by ADT.
Version 0.13.0 adds BPF template design version control through ZCL_BPC_GIT_BPF.
BPF is scoped by controlling model and requires Manage BPFs (P0043). Native XML
excludes runtime IDs, local access assignments and version labels. Workspace
links use local names/types; their contents remain outside Git. Restore creates
or updates an editable draft, verifies it against Git and preserves the deployed
version. Native edit-version workspace copies are reused for unchanged links.
Open/nonlocal/instance-bearing drafts, missing/ambiguous dependencies and Git
restore deletion are refused. UI scope/name/history regressions and syntax checks
pass (provider in existing class context, service with provider signature stand-ins,
HTTP directly). User must pull/activate via abapGit and test draft restore, instance
preservation and cross-environment dependencies. No SAP writes were made via ADT.
Version 0.14.0 adds per-member dimension master-data version control through
ZCL_BPC_GIT_MEMBERS. Select Dimension members then a dimension (metadata only),
and Load. Shared dimensions have environment-level DIMENSIONS/.../MEMBERS paths.
P0012 or P0133 plus native dimension access is required. XML names logical
properties/parents and excludes generated/runtime metadata. Native Save adds or
updates the working copy, verifies readback and leaves processing to the user;
other members and transaction data are preserved. Deletion restore is refused;
properties/hierarchies must already match the target schema, and referenced
members should exist first. Time-dependent and reference dimensions are excluded.
ADT syntax (provider context/name substitution, integration signature stand-ins),
UI scope/history regressions and format/JS/JSON/XML checks pass. User acceptance
must cover saved unprocessed edits, restore/readback, process stability, parents,
references and preservation of unrelated members/data after abapGit activation.
The sections below preserve the earlier session handover; use SPEC.md and
AGENTS.md for current behavior and the authorized commit/push workflow.

## 1. What bpcGit is

bpcGit is a web app on an SAP BPC 10.1 (NetWeaver 7.52) system. It keeps BPC
content under Git version control in a GitHub repository. You open the app,
set up a repository for a BPC environment, and see every tracked BPC object
with a Git status. From there you can **commit** BPC changes to Git, or
**restore** Git versions into BPC. This is staging, like abapGit's.

The app is built the same way as the user's earlier project **bpcIO**, at
`C:\Users\FelipeTomazzi\projects\bpcIO`. That is an abapGit repo with a UI5
BSP app, an ICF REST handler and a service class. Reuse bpcIO's patterns,
and look there first for how to read or write BPC objects.

## 2. Environment and ground rules

| | |
|---|---|
| Repo | `C:\Users\FelipeTomazzi\projects\bpcGit`, GitHub `felipetomazzi-source/bpcGit`, branch `main` |
| SAP dev system | `http://vhcalnplci:8000`, client 001, BPC environment `CH_PLANNING` (models such as `AGGR_OPEX`, `AGGR_PROJECT`, `ALLOC_OPEX`) |
| abapGit link | repo key `000000000006`, package **`ZBPC_GIT`**. abapGit 1.134.0 developer version is installed in `$ABAPGIT`. |
| App URL | `http://vhcalnplci:8000/sap/bc/ui5_ui5/sap/zbpc_git/index.html?sap-client=001`. Use the `/ui5_ui5/` path: `/sap/bc/bsp/sap/...` fails with `CX_FQDN` because the host name has no domain. |
| API | `/sap/bc/zbpc_git/` (handler `ZCL_BPC_GIT_HTTP`) |
| Targets | ABAP syntax no newer than 7.52, UI5 **1.52** APIs only, ES5-style JS (as in bpcIO) |
| Runs on | the development system only (decision Q7), never in QA or production |

Ground rules:

- **Read and check SAP only through the `adt` MCP server.** Never use the `bpc`
  MCP tools; the user asked for this. Useful ADT calls: `getObjectSource`,
  `searchObject`, `tableContents` (with `sqlQuery`), `ddicElement` (tables only),
  `syntaxCheckCode`. Data elements and structures are read from DD04L/DD03L
  through `tableContents`.
- **Never write to SAP directly.** The workflow is: you change files in
  `src/`, commit and push to `main`, then the **user pulls in abapGit**,
  activates, and tests in the browser. The user reports back with
  screenshots. Ask the user to pull and say exactly what to check.
- **Commit messages** end with the attribution lines the harness gives you.
  Push to `main`; the user pulls from `main`.
- **Communication:** the user is not a Git expert, so explain Git concepts
  briefly. They like short status tables and a numbered "Please:" test
  list at the end.

## 3. Build workflow and pitfalls (important)

### abapGit byte format
- Run `python tools/abapgit_fmt.py` after **every** change under `src/`, then
  `python tools/abapgit_fmt.py --check`. The script:
  - writes metadata XML (`*.clas.xml`, `*.tabl.xml`, `*.sicf.xml`,
    `*.wapa.xml`, `package.devc.xml`) with a BOM, CRLF and one trailing CRLF;
  - writes `.abap` files without a BOM, with CRLF and one trailing CRLF;
  - pads every line of WAPA content files (`*.wapa.*` except `*.wapa.xml`) to
    **255 characters** and joins them with CRLF. A line longer than 255
    characters makes the script stop; shorten it, for example by moving
    long binding expressions into the controller.
- The script reproduces bpcIO's files byte for byte, so trust it.
- Git stores LF: the system Git config has `core.autocrlf=true`, which is
  also what abapGit pushes. Leave it that way.
- After the formatter has run, WAPA files on disk are padded. To edit them
  with Python, read them, `rstrip(" ")` each line, edit, write, then run the
  formatter again. The Edit/Write tools need the file read again after
  formatting.
- Bash heredocs with `'EOF'` sometimes fail on long Python scripts. Use
  `<<'PYEOF'`, or write the script to the scratchpad and run it.

### Hand-written DDIC (`.tabl.xml`): `SHLPORIGIN`
- If a field's data element has a search help (`DD04L-SHLPNAME`, for
  example `RFCDEST`), add `<SHLPORIGIN>D</SHLPORIGIN>` between `ADMINFIELD`
  and `COMPTYPE`.
- Every `DATS`/`TIMS` field needs `<SHLPORIGIN>T</SHLPORIGIN>`.
- Without these lines abapGit shows a permanent diff after every pull. The
  user reported this twice, and both times it was this, not the BOM.
- Use only standard data elements, so the XML stays minimal.
- SICF file names are the service name padded to 15 characters plus the
  first 25 hex characters of `sha1(url)`.

### Syntax checking through ADT
- `syntaxCheckCode` (with `url` and `mainUrl`) **only compiles objects that
  already exist in SAP**. For a new object it accepts anything, even
  deliberate errors.
- It also stops at the first error.
- **Technique used throughout:** check a trimmed copy of the class under the
  existing class's URL. Keep only the changed methods and their declarations.
  Replace anything not yet in SAP (a new table, a new method of another
  class) with local stand-ins. This catches real errors, for example 7.52
  rejecting `IS INITIAL` on a function result. Prefer `xsdbool` over `boolc`
  for inline booleans.

## 4. Architecture (current `main`)

| Object | Role |
|---|---|
| BSP `ZBPC_GIT` (`src/zbpc_git.wapa.*`) | UI5 app: one view (`App.view.xml`), controller (`App.controller.js`), `Component.js` (JSON model `app`), manifest version 0.9.1 |
| SICF `/sap/bc/ui5_ui5/sap/zbpc_git/` and `/sap/bc/zbpc_git/` | App URL and REST API |
| `ZCL_BPC_GIT_HTTP` | REST handler: routing, input checks, JSON (built by hand like bpcIO, `quote( )`), error mapping |
| `ZCL_BPC_GIT_SERVICE` | Business logic: environments, config, listing, status, commit, restore |
| `ZCL_BPC_GIT_REMOTE` | **The only class that calls abapGit.** Login, branches, `read_branch` (pull), `get_content`, `commit` (push), hashing, author |
| Table `ZBPC_GIT_REPO` | One row per environment: URL, branch, changed by/at |
| Table `ZBPC_GIT_STATE` | Sync record per BPC document: blob SHA, commit SHA, BPC LSTMOD date/time, synced by/at |

### REST API (all POSTs need the header `X-Requested-With: XMLHttpRequest`, as a CSRF guard)
| | | |
|---|---|---|
| GET | `/ping` | User, system, client, abapGit version |
| GET | `/environments` | Environments the user may access |
| GET/POST | `/config` | Repository setup of an environment |
| POST | `/connection` | Test the connection: branches, plus push access if logged in |
| POST | `/workbooks` | Overview: every tracked object with its status (the name is historical; it covers all kinds) |
| POST | `/commit` | `environment`, `message`, `commit` (the head the user saw), `paths` (one per line) |
| POST | `/restore` | `environment`, `commit`, `paths`; returns a result per file |

### Git login (decision Q1, revised twice)
- There is no SM59 destination and no user exit; this is the abapGit
  approach.
- A request goes out without credentials first. Public repos can be read
  anonymously; a push always needs a login.
- When the Git host answers 401, the API returns **403 with
  `"authRequired": true`**. It doesn't return 401, so the browser shows no
  login popup of its own.
- The UI then asks for a user and personal access token and retries.
- The token is kept in **`sessionStorage`** (the browser tab) and the user name
  in `localStorage`. Nothing is stored on the server.
- The server puts the credentials into `ZCL_ABAPGIT_LOGIN_MANAGER=>SET_BASIC`
  for that request only.
- Without SAP GUI, abapGit raises "Unauthorized..." instead of showing a
  popup; `is_auth_error` checks for it.

### What is tracked
Paths are below `\ROOT\WEBFOLDERS\<ENV>\` in BPC, and the same path is used in
Git with `/` separators. One classifier, `ZCL_BPC_GIT_SERVICE->GET_KIND`
(path â†’ kind), decides what is tracked for BPC and Git alike.

| Kind | BPC location | Notes |
|---|---|---|
| WORKBOOK | `<MODEL>\EEXCEL\...` and `<MODEL>\TEAM FILES\<TEAM>\EEXCEL\...` | .xlsx/.xlsm/.xls/.xltx/.xltm; type in the UI = Report / Input schedule / Other, taken from the library folder |
| SCRIPT | `ADMINAPP\<MODEL>\*.LGF` | `.LGX` files are compiled by BPC and ignored |
| TRANSFORMATION | `<MODEL>[\TEAM FILES\<T>]\DATAMANAGER\TRANSFORMATIONFILES\...` | `.TDM` and its `.XLS` are separate rows |
| CONVERSION | `...\DATAMANAGER\CONVERSIONFILES\...` | `.CDM` and `.XLS` |

Listing goes through `CL_UJF_FILE_SERVICE_MGR=>LIST_DIRECTORY`, one document
type at a time, driven by a table of folders and types for each model.

### Statuses (spec section 6)
- The statuses are UNCHANGED, MODIFIED_BPC, MODIFIED_GIT, CONFLICT, NEW_BPC,
  NEW_GIT, DELETED_BPC, DELETED_GIT, and DIFFERS (both sides exist, contents
  differ, no sync record).
- BPC content is only read and hashed when needed: when Git has the file and
  the LSTMOD time differs from the sync record.
- **Commit** works on NEW_BPC, MODIFIED_BPC, DIFFERS and DELETED_BPC, as one
  commit through abapGit's porcelain push.
  - It is refused if the branch head is not the one the user saw.
  - The author comes from the user master, through abapGit's user record.
- **Restore** works on MODIFIED_GIT, NEW_GIT, DIFFERS and DELETED_GIT. It also
  works on MODIFIED_BPC, CONFLICT and DELETED_BPC, which discards the BPC
  changes; the UI marks these in red.
  - "Select Git changes" picks only files whose newer version is in Git.

### BPC behaviour learned the hard way (also in user memory)
- **The file service lock** is only the flag `UJF_DOC-LOCK_IND`.
  - `PUT_DOCUMENT` refuses whenever the flag is set, even by the caller, and
    reports the *caller* as the locker.
  - `LOCK_DOCUMENT` and `UNLOCK_DOCUMENT` rewrite `LSTMOD_*`.
  - So: check `CHECK_DOCUMENT_LOCK`, then write directly; never lock first.
- **Writing documents:** `PUT_DOCUMENT(... i_compression = abap_false
  i_splice_zip = abap_false)`, as bpcIO does. Missing folders are created
  level by level (`ensure_folder`).
- **Logic scripts** are compiled when they run, so writing the `.LGF` is
  enough.
  - Restore validates them first with `CL_UJK_SCRIPT_LOGIC=>VALIDATE`, which
    is what BPC's script editor uses.
  - Line endings are normalised to CRLF, because BPC splits scripts at CRLF.
  - Restoring scripts requires BPC task P0008.

## 5. Status of the steps

| Step | Status |
|---|---|
| 1 BSP shell, 2 `/ping`, 3 config table and setup, 4 login and Test connection | Done and tested by the user |
| 5 Overview with status, filters (model, location, type, status, search, hide backups) | Done and tested |
| 6 Commit (staging, Select BPC changes) | Done and tested |
| 7 Restore, including discarding BPC changes | Done and tested, apart from the last change (commit `714cf8e`, restore over MODIFIED_BPC/CONFLICT/DELETED_BPC); the user hasn't confirmed that one yet |
| Team workbooks, logic scripts, transformation and conversion files | Done and tested |
| **Data Manager packages and package links** | **In progress, uncommitted (see section 6)** |
| 8 History (commits of a file, restore an older version) | Not started |

## 6. Work in progress: Data Manager packages and package links

### State
- `src/zcl_bpc_git_service.clas.abap` has **uncommitted** changes. The
  backend for both kinds is written.
- **All the new methods passed an ADT syntax check** as a trimmed copy.
- **The full class has not been syntax-checked as a whole yet.** That was
  the next action. `ZCL_BPC_GIT_REMOTE` in SAP is current, so the full
  service source can be checked directly against
  `/sap/bc/adt/oo/classes/zcl_bpc_git_service`.
- The **UI is not done yet**, and neither are the spec section 3.4 and the
  README.
- Nothing about packages or links has been pushed. `main` matches what the
  user has in SAP.

### Design (implemented in the service)
- **Packages and links are table entries, not documents.** bpcGit writes
  them as XML files: `ty_bpc_workbook`/`ty_workbook` have `generated = 'X'`
  and `content` (the file), the LSTMOD fields are empty, and `docname` is a
  pseudo name from `to_docname( path )`.
- **Status:** `compare` always hashes generated content, because there is no
  timestamp to rely on.
- **Commit:** uses `content` instead of `GET_DOCUMENT`.
- **Restore:** `restore_file` sends generated kinds to `restore_package` or
  `restore_link`. `restore_files` now runs COMMIT WORK after each file and
  ROLLBACK WORK after each failed one, because BPC's package APIs don't
  commit. It doesn't read document attributes for these kinds.
- **Package files:**
  - Path: `<MODEL>/DATAMANAGER/PACKAGES/<GROUP>/<PACKAGE>.xml`; a team
    package goes below `<MODEL>/TEAM FILES/<TEAM_ID>/`.
  - The file is hand-built XML: `<package>` with `group`, `id`, `team`,
    `description`, `type`, `userGroup` and `chain`, then
    `<script><line>â€¦</line></script>`, one `<line>` per script step.
  - The script is stored in `UJD_INSTRUCTION2-CONTENT` with the literal
    **`<BR>`** as line separator; it is split on `<BR>` and joined back with
    `<BR>` plus a trailing `<BR>`.
  - A package **without** a `UJD_INSTRUCTION2` row uses its process chain's
    default script, so its file has no `<script>` element and restore doesn't
    call `SAVE_PACKAGE_INFO`.
  - Rows with an empty `PACKAGE_ID` are package groups and are skipped.
  - The file is parsed with sXML (`cl_sxml_string_reader`).
- **Restoring a package:** `NEW cl_ujd_package( )`, then `CHECK_PACKAGE_EXIST`,
  then `MODIFY_PACKAGE` (with `i_original_group`/`i_original_package`) or
  `ADD_PACKAGE`, then `SAVE_PACKAGE_INFO( i_script )`. Delete uses
  `DELETE_PACKAGE`.
- **Link files:**
  - Path: `<MODEL>/DATAMANAGER/PACKAGELINKS/<NAME>.xml`. Links belong to a
    model, never to a team.
  - The content is `UJD_LINK-CONTENT`, found through `UJD_PACKAGE_LINK`
    (`SERVICE_LINK_ID` if filled, else `LINK_ID`).
  - The first `<PROPERTY NAME="ID">` holds a system-specific ID that doesn't
    always match. It is **blanked in Git** (`set_link_id`) and set to the
    target link ID on restore.
- **Restoring a link:** `CL_UJD_PACKAGE_LINK=>GET_LINK_WITH_NAME`.
  - If the link exists, `UPDATE_PLINK` keeps its ID, so schedules and BPF
    references stay valid.
  - Otherwise `SAVE_PLINK`, then `UPDATE_PLINK` to put the new ID into the
    XML.
  - Delete uses `DELETE_PLINK`, which refuses when a schedule uses the link.
  - **The `UJD4` function modules (`UJD_ADD_PACKAGE_LINK` etc.) are empty
    shells; don't use them.**
  - `SAVE_PLINK` never overwrites and doesn't check names, which is why the
    lookup by name comes first.
  - `UPDATE_PLINK` writes before it validates; the per-file ROLLBACK covers
    that.
- `get_kind` additions: `.../DATAMANAGER/PACKAGES/<group>/<file>.xml` is a
  PACKAGE (part count = area + 3). `<model>/DATAMANAGER/PACKAGELINKS/<file>.xml`
  is a LINK (company level only, part count = 4).
- `to_file_name` replaces `/ \ : * ? " < > |` with `_` in path segments. On
  restore, the identity comes from the XML content, not from the path.

### Remaining to do
1. **Syntax-check the full service class against SAP.** Optionally pass the
   source without the `"!` comment lines to keep the call small.
2. **UI** (`zbpc_git.wapa.controller_-app.controller.js` and the view):
   - In `TYPE_BY_KIND` add `PACKAGE: "Data Manager package"` and
     `LINK: "Package link"`.
   - Add both to the Type filter `Select` in the view.
   - The Location and folder logic already works for these paths.
   - "Last change in BPC" stays empty for these rows, which is fine.
3. Bump the version in `zbpc_git.wapa.manifest.json` (currently 0.9.1), run
   the formatter, and parse-check the view and JS. The Node test patterns
   used so far are in the Bash history; in short, `eval` the controller with
   a stub `sap.ui.define` and call `_toRow`/`_applyFilter`.
4. Add spec section **3.4** with the design above, and update the README
   (kinds, API is unchanged).
5. Commit, push, and ask the user to pull. Test plan for the user:
   - Type filter "Data Manager packages" shows `AGGR_OPEX` packages, e.g.
     `Calculations/ROLLING_FORECAST`, as New in BPC.
   - Commit a few and look at the XML on GitHub.
   - Edit a package's script on GitHub and restore it, then check it in BPC's
     Data Manager.
   - The same for a package link, e.g. `AGGR_OPEX` `LOAD_ACTUALS`.
6. Possible follow-ups:
   - Two links with the same name in one model collide in Git, because they
     get the same path and only the first is listed. Consider detecting and
     reporting this.
   - Team IDs in package paths are used as-is (mixed case, e.g.
     "Interface BPC to ERP"), unlike the upper-case team folders of
     workbooks.

### Reference data on dev (from research)
- About 190 rows in `UJD_PACKAGES2` for CH_PLANNING. `PACKAGE_TYPE` is
  always "Process Chain", `USER_GROUP` is 1, 10 or 11, and `TEAM_ID` is
  mostly empty.
- 66 package links across the models.
- `UJD_PACKAGES2` key: MANDT, GUID; logical key: appset, app, team, group,
  package.
- No created or changed timestamps in the package tables.

## 7. Next after packages and links: step 8, History
Per the spec, step 8 is: for a selected file, list its commits (SHA, author,
date, message) and restore any older version. abapGit tools:
`ZCL_ABAPGIT_GIT_TRANSPORT=>UPLOAD_PACK_BY_BRANCH` with `iv_deepen_level`,
plus `ZCL_ABAPGIT_GIT_PACK` (decode commits). The other route is
`ZCL_ABAPGIT_GIT_PORCELAIN=>PULL_BY_COMMIT`. Keep all abapGit calls in
`ZCL_BPC_GIT_REMOTE`.

## 8. Key files
- `docs/SPEC.md`: the functional spec, with decisions Q1â€“Q8 and the
  sections on what is tracked, change detection, architecture and security.
- `README.md`: the API table and build steps.
- `tools/abapgit_fmt.py`: the byte-format helper.
- `src/`: all abapGit objects (`.abapgit.xml` has `STARTING_FOLDER /src/`).

Version 0.11.2 replaces the combined EPM workbook load choice with EPM reports
(default), EPM input schedules and Other EPM workbooks. The API accepts REPORT,
SCHEDULE and OTHER scopes while retaining WORKBOOK for older clients. Company
reports/schedules list their specific library; team listings filter by the
library directly beneath EEXCEL before comparing content. Git-only files use
the same classification. Other covers books, distribution lists and remaining
workbook paths; All objects continues to include all supported objects.

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

Validation: seven Node suites and the UI5 1.52 embedded browser journey pass; the new folder input binds correctly. Formatter/check and JavaScript syntax pass. ADT remote-class syntax check failed HTTP 400, so SAP compilation and added ABAP Unit fixtures remain pending after pull/activation. No SAP source or BPC repository content was changed.

## Root folder Save fix (0.17.1)

Form field presence detection is case-insensitive to handle SAP HTTP field-name normalization. Explicit blank rootFolder still clears the setting, while an omitted field preserves the saved setting. ABAP Unit covers uppercase, camel case, mixed case empty and omitted fields. SAP execution remains pending.

## Dimension member labels (0.17.2)

The overview carries memberDescription from BPC member metadata. UI displays decoded ID without .xml, followed by the description when available. Git-only members fall back to ID; no extra Git downloads are added. Git paths and serialized XML are unchanged. SAP backend compilation remains pending.

## Member and BPF restore path fix (0.17.3)

Member/BPF restore now requests Git content by logical file path, as required by the remote interface, instead of passing a blob SHA-1. The wrong argument produced hash-is-not-in-repository errors before invoking BPC restoration. Applies to current and historical restore and configured root folders. Existing deletion branches are unchanged. Local regressions pass; live SAP restore validation remains pending.

## Process restored members (0.17.4)

ADT confirmed IF_UJA_MEMBER_MANAGER~PROCESS parameters and CL_UJAM_MEMBER implementation. Member restore now calls processing once per affected dimension after saves, with validation enabled and without requesting the environment offline. Failed member saves skip processing for their dimension. Processing failure changes saved-member outcomes to unsuccessful with an explicit saved-but-not-active message and clears sync records; already saved changes are not claimed rolled back. Processing covers the entire dimension including other pending member edits; UI warns accordingly. Current/historical restores share the path. Other object types unchanged. Live activation validation remains pending.

Validation: ADT syntax check of the complete updated service class passed with no errors (existing ABAP Doc warnings only). Seven Node regression suites and formatter/check passed. No SAP source or member data was written; actual dimension processing is pending user abapGit activation and restore testing.

## Repository setup persistence (0.17.5, 2026-10-06)

User requested preserving credential-bearing URLs instead of importing them
into the tab login and stripping them. Configuration now stores/returns the
complete URL (CHAR2048). Request-local transport extracts credentials and uses
a clean address so Bitbucket history/diff/LFS detection remains available.
Explicit tab credentials override embedded credentials. Repository exclusivity
compares clean addresses. Branch choices now live separately from connection
results and include the saved/typed branch after config reload and branch reads.

Verification: all seven Node regression suites pass. Playwright's actual UI5
1.52 component harness passes 22 assertions, including saved branch display,
branch advertisements, manual entry, connection clearing and config refresh.
Formatter and diff checks pass. Added ABAP Unit cases for URL decoding, literal
plus/colon/equals preservation, clean Bitbucket API detection, request credential
precedence and empty-token rejection. ADT source read and syntax check both
returned HTTP 400, so SAP syntax/ABAP Unit execution and activation remain
unverified. Pull/activate the DDIC URL expansion, remote class, dependent HTTP/
service classes and BSP together before testing URL Save/reload in SAP.

## URL DDIC activation correction (0.17.6, 2026-10-06)

SAP rejected the 0.17.5 CHAR2048 URL field: the installed database/DDIC allows
at most 1,333 characters. URL is now CHAR1024 (2,048 internal Unicode bytes).
The configuration endpoint derives its input limit from DDIC, so overlong
addresses are rejected before assignment. No data migration or configuration
write is performed by this correction. Pull the corrected table definition and
activate it; the previous failed activation is not evidence of deleted data.
Formatter and local XML length consistency checks pass. SAP activation remains
for the user to confirm after pulling the correction.

## URL serializer alignment (2026-10-06)

User's abapGit diff showed SAP's canonical built-in CHAR field serialization:
ADMINFIELD precedes INTTYPE, MASK contains two spaces followed by CHAR, and
COMPTYPE is absent. Aligned only the URL DD03P XML with that observed output.
Field type and length stay CHAR1024; this corrects a persistent serialization
diff rather than changing the table layout. Formatter and XML assertions pass.
Confirmation that refresh clears the diff remains with the user in SAP.

## LFS pointer parse fix (0.17.7, 2026-10-06)

SAP state confirmed via ADT: ZBPC_GIT_REPO is active with URL CHAR1024 and no
ZBPC_GIT objects are inactive. abapGit pull of main (transport NPLK900106,
which already held the table) succeeded with no changes after `1538d14`.
ADT source reads, syntax checks and ABAP Unit work again.

ABAP Unit on SAP exposed a real defect: `ZCL_BPC_GIT_LFS=>parse` expected four
SPLIT segments with an empty last one, but ABAP SPLIT creates no segment for a
trailing separator. Every canonical pointer, including our own `pointer( )`
output, was rejected, so LFS upload/download/comparison could never work.
Parse now requires three lines and an exact canonical text match (rejecting
extension lines and a missing final newline). Regression tests added.

## Repository summary at top (0.17.8, 2026-10-06)

User request: long object lists pushed Repository setup out of reach and the
current branch was not visible. The setup Panel moved above the load controls
(Installation check stays at the bottom). Its headerToolbar shows the saved
repository label (scheme, userinfo and ".git" stripped by `repositoryLabel`)
and saved branch (`/savedRepositoryLabel`, `/savedBranch`, set in
`_showConfig`, cleared on environment change), not the unsaved edit values.
UI5 1.52 has no ValueState "Information"; use None. Node 8/8, OPA 7/7 and
embedded 22/22 pass on actual UI5 1.52 with mock API data.

## Change link (0.17.9, 2026-10-06)

The Repository setup header has a "Change" Link (visible when configured).
`onChangeRepository` expands the panel and focuses `branchInput` after the
1.52 slideToggle animation via `$().children(".sapMPanelContent").promise()`
(1.52 Panel content has no DOM id). Verified on UI5 1.52 harness: expands,
focus lands on the branch input; OPA 7/7, embedded 22/22, Node 8/8.

## Branches load on dropdown open (0.17.10, 2026-10-06)

`onInit` attaches `onBranchListOpen` to the branch ComboBox picker's
beforeOpen (via protected `getPicker()`, guarded; `loadItems` cannot be used
because it fires only for an empty list and the saved branch is always
listed). It calls `_testConnection` only when configured, `/connection` is
null (not loaded yet; reset by URL/environment change and `_showConfig`), no
request is running and the URL equals the saved URL. A login dialog may
appear for private repositories without URL credentials, as with Load
branches. Verified on UI5 1.52 harness with a stubbed connection response:
one request on first open, list updates while open, no refetch on reopen,
none for an unsaved URL. Node 8/8, OPA 7/7, embedded 22/22.

## Customizing transports for restores (0.18.0, 2026-10-06)

User request: record restored objects in a transport request, customizing type
("that's how BPC handles it"), default transport layer. Researched via ADT:
CL_UJT_TRANS_MGR=>CREATE_REQUEST creates type W with task Q; objects are
R3TR <tlogo> <GUID> appended with TR_APPEND_TO_COMM; GUIDs map entities in
UJT_GUID (RSTLOGO ABPC); UJT_ENTITY_CLASS-F_GENERIC_TLOGO = X means object
ABPC, otherwise the entity type is the object type. CL_UJT_TLOGO_ABPC exports
at release; UJT_TLOGO_AFTER_IMPORT imports.

ZCL_BPC_GIT_TRANSPORT: open_requests (W, status D, this client, user has an
open task), create_request (TR_INSERT_REQUEST_WITH_TASKS, no target = default
layer), check_request, entity mapping, record (reuses UJT_GUID mapping or
generates via CL_UJT_UTILITY=>GENERATE_GUID and inserts it; skips entries
already in the request/tasks; all-or-nothing with rollback). Entity formats,
confirmed against CH_PLANNING UJT_GUID rows:
- EPM workbook AFLE, model, COMPANY\EEXCEL\... or <team>\EEXCEL\...
- Transformation/conversion ADMF, model, COMPANY\DATAMANAGER\<folder>\<name>
  without extension (definition and workbook are one entity)
- Logic scripts ASPR, model, ADMINAPP\<model> (whole model folder)
- Package ADMP via CL_UJD_ENTITY_ADMP=>CONCAT_ENTITY_ID(team, group, id)
- Package link ADML, model, link name; Members AMBR, dimension
- BPF ABPF, UJB_TMPL_HDR-TMPL_GUID by TECH_NAME; Team ATEM, task profile
  ATPF, data access profile ADAF by ID
Deletions are reported as not transported (BPC uses UJT_TRANS_DEL for those).

HTTP: GET /transports, POST /transport (text), restore field transport
(checked before restore; response member transport {request,count,error,
skipped}). Only objects whose restore result is ok are recorded. UI: picker in
bulk and history restore dialogs; UI5 1.52 Select needs a non-empty key for
"no request" (__NONE__). Unit tests (4) pass in SAP; Node 9/9; OPA 7/7;
embedded 22/22. NOT yet verified live: creating a request, recording entries,
and releasing/importing one. Test with a throwaway request first and check
E071 entries (and UJT_GUID rows for new GUIDs) before releasing.

## Add to transport without restoring (0.18.1, 2026-10-07)

Toolbar button "Add to transport (n)" for selected rows that exist in BPC.
POST /transport/record (environment, transport, paths) checks the request,
maps paths with ZCL_BPC_GIT_SERVICE=>TRANSPORT_ENTITIES from BPC only (no Git
access): file kinds require the UJF_DOC document; packages/links take their
identity from BPC's own definitions (list_packages/list_links); others use
entity_for_path. Recording reuses ZCL_BPC_GIT_TRANSPORT=>RECORD; response
member transport as for restores. Picker has a required mode (no "No
transport" option; last or first open request preselected). Node 9/9 incl.
new add-to-transport checks; harness dialog renders. Live SAP test pending.

## Grouped file list (0.19.0, 2026-10-08)

User request: selecting everything in large lists (e.g. 50 logic scripts) was
tedious. `/workbooksView` now holds group rows (`isGroup`, `kind`, `expanded`,
`name` "Text (n)", `folder` "n selected", `selected` = all members selected)
followed by their rows when expanded. `_applyFilter` stores the filtered rows
in `this._shownRows` and calls `_buildView`; `GROUPS` gives labels and order.
Group rows are `type="Active"`; `onGroupPress` (table itemPress) toggles
`this._expanded[kind]`. A single group or a search is always expanded.
`onSelectionChange`: selectAll selects all shown rows; a changed group item
sets all its shown rows; object-only changes call `_refreshGroups` (updates
group rows in place, keeps scroll). `_selectWhere` uses `_shownRows`.
Verified with real UI5 1.52 pointer events in the harness: group checkbox
selects 50, row click expands/collapses, member uncheck shows "49 selected",
header select/deselect all. Node 10/10 (new tests/group_ui.test.cjs), OPA 8/8
(journey expects the group row).

## Commit message placement (2026-10-08)

Moved the commit message label/editor and error strip above the selected-object
list. Commit validation and payload are unchanged. Added a UI5 1.52 harness
case with 60 objects verifying editor placement and blank-message rejection.
All 10 controller regression suites pass; headless OPA journey passes 8/8 and
embedded suite 25/25 assertions. Formatter/check passed. SAP pull/activation
of this UI change has not been performed in this task.

## Single-object commit refresh (0.19.1, 2026-10-08)

Removed the full loaded-scope refresh after commit. Optional /workbooks paths
reuse read_paths validation and get_overview selected-path/companion filtering.
UI merges current selected rows, preserves unrelated rows, removes selected
objects absent on both sides, and advances head only if it matches the push.
Concurrent head changes and refresh failure report push success separately;
scope sequence/environment guards prevent stale merges. Full abapGit branch
pull in commit and scope metadata/generated-object listing remain potential
costs. This is not evidence of a measured SAP latency improvement.

New controller suite covers selected path payload, unrelated selection/status,
deleted rows, concurrent head and stale replies. The UI5 1.52 harness exercises
selected-path read-only mock refresh. ADT tools are not exposed in this session,
so backend compilation and SAP pull/activation remain unverified.
