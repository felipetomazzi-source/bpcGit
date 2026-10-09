# Notebook versioning — test branch, 0.20.0

Prepared on `codex/notebook-versioning`, separately from main. Requires the
matching Notebook repository branch, also `codex/notebook-versioning`.
The matching Notebook provider is pushed through `f04a099`. Neither branch has
been deployed by this integration task. Application backends
remain independently installable; bpcGit has no static reference to Notebook
classes/tables. Its optional adapter calls `ZCL_BN_GIT=>DISPATCH` dynamically and
refuses Notebook operations when the provider is unavailable or unauthorized.

## Scope and workflow

Choose **Notebooks**, then Load in the selected BPC environment. Saved definitions
appear as one logical object per Notebook, with a title and target-local revision.
Model context is carried by the manifest and validated by Notebook; load operates
at environment scope. Unsaved Notebook browser drafts are never exported.

Commit stages the saved manifest and changed cell sources together in the normal
Git commit. Diff shows the manifest and source files, including added/removed
cells. History compares the entire Notebook directory's Git tree hash, so
cell-only changes appear even when the manifest is unchanged. Notebook directory
history uses the Git pack path on Bitbucket too; it can be slower than the existing
single-file Bitbucket history API and is cached using the existing head-checked
history cache. There is no PR creation or merge automation in this phase.

Restore and historical restore assemble the complete source bundle, preview it
through Notebook validation, then import it as a new immutable Notebook revision.
Missing prior cells are removals within that new definition; whole-Notebook
restore deletion is refused. Existing saved history, execution snapshots and
revision-pinned handler bindings are preserved. Import does not execute cells,
repin a handler, or enable posting. Each complete Notebook and its bpcGit sync
records succeed/roll back together. Different selected logical objects retain
bpcGit's existing independent success/failure behavior.

No Notebook transport request recording is implemented. Restore/history dialogs
omit the transport picker for Notebooks, and backend restore/record endpoints
reject a transport request containing Notebook paths. Other BPC types keep their
existing transport behavior. Movement between systems is Git-backed import;
SAP CTS support can be designed separately.

## Files and provider boundary

Paths are relative to the configured BPC root folder:

```text
NOTEBOOKS/<stable-key>/notebook.json
NOTEBOOKS/<stable-key>/cells/<stable-cell-id>.abap
NOTEBOOKS/<stable-key>/cells/<stable-cell-id>.bns
NOTEBOOKS/<stable-key>/cells/<stable-cell-id>.generated.abap
```

Script generated source is an audit companion only. bpcGit preserves the provider's
exact bytes, including BOM, UTF-8 text, line endings, trailing spaces and blank
lines. It does not reserialize manifests or regenerate authored source. Git
checkout/editor settings must likewise avoid automatic source normalization.
Only these definition/source paths are tracked; outputs, run snapshots, private
fixtures, runtime selections and extra files are excluded. Stable key and cell
IDs are validated; traversal/cross-Notebook paths and duplicates are refused.

The agreed provider entry is static `ZCL_BN_GIT=>DISPATCH`, importing `operation`
and `request` as strings, returning `json` as a string. All requests contain
`contractVersion: 1` and `environment`. CAPABILITIES must authorize access and
confirm `contractVersion=1`, `callerTransaction=true`.

- LIST accepts optional model and returns `bundles` with `key`, `title`, `model`,
  saved `revision`, and sorted `files[{path,contentBase64}]`.
- PREVIEW / IMPORT accept `key`, `expectedRevision`, verified `sourceCommit`,
  and the complete set of present `files[{path,contentBase64}]`. Omitted cells
  are handled according to the source manifest, never as independent writes.
- Responses include `contractVersion`, `canImport`, `validationError`, `revision`
  and Notebook-owned `notebookId`. Successful IMPORT returns a larger revision.
  The adapter fails closed on malformed/negative responses and provider exceptions.

Notebook owns deterministic export, schema validation, native ABAP syntax checks,
BPC context/authorization, stable-key mappings, provenance and revision CAS.
The caller owns the transaction. The authoritative manifest/provider contract is
`docs/notebook-versioning.md` on the matching bpcNotebook branch. Its v1 manifest
contains contractVersion,key,title,environment,model,inputs,cells in canonical
serializer order. Reformatting or unknown fields are rejected in this first phase.

## Concurrency and API additions

`/workbooks` Notebook rows expose `notebookTitle` and `notebookRevision`; generated
source companions are grouped under `NOTEBOOKS/<key>/notebook.json`.

`POST /restore` requires `notebookRevisions`, a form field containing a JSON array:

```json
[{"path":"NOTEBOOKS/revenue/notebook.json","revision":3}]
```

The revision must match the saved revision exported during fresh planning. Use
zero only for a genuinely new target key. UI restore and history restore bind the
revision shown in the loaded row. Notebook independently rechecks CAS while
importing, protecting changes during planning/execution. A Notebook browser draft
is not observable by bpcGit; its subsequent save must use Notebook's existing CAS
and surface a conflict if the Git import created a newer saved revision.

`/restore-preview` additionally returns `currentNotebookRevision` per file so
MCP clients can bind metadata-only saves as well as byte fingerprints. The existing
MCP implementation must add Notebook revision binding before executing Notebook
restores; it cannot omit the required `notebookRevisions` field. Successful
restore results additionally contain `notebookRevision`, the new saved revision.
Other object request fields and responses remain compatible.

## Phase-one limits

ABAP cells can be validated/imported. Notebook Script author source and exact
saved generated envelopes can be exported, committed, diffed and reviewed.
**Script imports are blocked**, including attempts to disguise Script envelopes
as ordinary ABAP. The supported transpiler currently runs in the browser; a
supported server compilation boundary is required before Script import is enabled.

Runtime member/range choices are excluded and cleared during import. Matching
scalar definitions retain target-local values; new scalars get Notebook's safe
local defaults. Manifest v1 does not transport scalar defaults or custom provider
bindings: unsupported additional definitions fail instead of being dropped.
Required local inputs must be reviewed before execution in the target system.

## Checks and release gate

Local checks:

```powershell
python tools/abapgit_fmt.py --check
node --test tests/*.test.cjs
node tests/opa/run.cjs
npx --yes @abaplint/cli@2.120.71 tests/abaplint.notebook.json -f summary
```

The local UI5 harness runs against read-only mock data. New ABAP Unit tests cover
adapter paths, source-byte preservation, rejected imports, stale saved revisions
and directory history. Those tests are prepared but not run on SAP for this branch.
Local checks passed: 14 Node controller test files, 8 standalone + 47 embedded
UI5 assertions, formatter/check and static ABAP parser/type checks across 38
source files. The matching Notebook repository reports 31 of 32 existing local
tests passing; its unchanged SAP serialization gate remains unsatisfied until
actual SAP pull/round-trip validation. This is not a completed native acceptance.

Static lint has generic SAP dependencies and known BPC type-pool constant names;
it does not establish compatibility with installed native BPC APIs.

Before release, deploy both feature branches to a test system through abapGit,
activate/check the classes, run native ABAP Unit and actual Notebook round trips,
verify rollback after provider/sync failures and concurrent revision conflicts,
and compare SAP serialization. Keep both branches unmerged until these pass.
