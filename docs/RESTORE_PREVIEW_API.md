# Restore preview API (0.19.6)

`POST /sap/bc/zbpc_git/restore-preview` is a read-only BPC planning operation.
Use form encoding and `X-Requested-With: XMLHttpRequest`, with the same SAP
session/environment authorization and request-local Git authentication as restore.
It may populate read caches, but does not save BPC content, process dimensions,
change sync baselines, record transports, or push Git.

## Request

- `environment`: selected BPC environment, required.
- `paths`: newline-separated logical object paths relative to the configured BPC
  root folder; same validation/maximum 1000 selections as `/restore`.
- `commit`: required 40-character current branch SHA; compared with the freshly
  checked branch head. Uppercase hex is accepted.
- `version`: optional 40-character historical SHA. History restore allows one
  logical object and requires a complete version in the selected history range.
- `depth`: optional integer 1–1000, default 100, matching `/restore`.
- `user`, `token`: optional request-local Git credentials; never returned.
- `transport`: not accepted by preview. Supply it only to execution if desired.

## Response

HTTP 200 returns the planning result, including invalid/stale selections:

```json
{
  "branch": "main",
  "currentHead": "<current SHA>",
  "sourceCommit": "<version SHA or current SHA>",
  "canRestore": true,
  "validationError": "",
  "objects": [{
    "path": "<logical object path>",
    "files": [{
      "path": "<physical file path>",
      "currentStatus": "MODIFIED_BPC",
      "status": "MODIFIED_GIT",
      "action": "UPDATE",
      "inBpc": true,
      "overwritesBpc": true,
      "sourceSha1": "<source Git blob SHA>",
      "currentBpcSha1": "<current BPC blob SHA>",
      "validationError": ""
    }]
  }]
}
```

The logical selection is deduplicated and expanded using the actual restore
companion rules. `files` includes unchanged companions. Actions are `CREATE`,
`UPDATE`, `DELETE`, or `UNCHANGED`; `overwritesBpc` is true for update/delete of
existing BPC content. `currentStatus` describes the current-head comparison;
`status` describes the selected restore source. Historical restores may report
UPDATE even when bytes happen to be identical, matching execution behavior.
`currentBpcSha1` hashes the current uncompressed BPC content with Git blob hashing,
including freshly serialized generated objects; it is empty when absent.
`sourceSha1` is empty when the source file is absent. No content is returned.

A planning error sets `canRestore=false`, a top-level `validationError`, and no
objects. File lock/read errors retain the plan with per-file `validationError`
and `canRestore=false`. Malformed fields return HTTP 400. Authorization/Git
connection failures use the existing HTTP error response instead of a plan.

## Execution and MCP coordination

The backend shares restore scope, head/history completeness checks, companion
expansion and task checks with `/restore`. Preview also reads current BPC content
and checks current document locks. It does not run write-time payload/business
validation and does not reserve locks. `canRestore=true` is permission to review
a viable plan, not a guarantee of successful execution.

The BPC MCP agent binds environment, paths, commit, version and depth to a
short-lived one-use opaque preview ID. It re-fetches preview immediately before
execution, compares the complete normalized plan (including current BPC hashes),
and rejects changed/invalid plans. Only fresh optional credentials are accepted
with the preview ID. This narrows but does not eliminate a concurrent-edit race:
`/restore` still revalidates current head, selection and locks during execution.
There is no backend preview ID or atomic BPC-content precondition in this version.

`POST /restore` keeps its existing request and per-object results and now also
returns `branch`, `currentHead`, and `sourceCommit` on success. `currentHead` is the
head checked when planning, not a new post-write advertisement.
`POST /commit` now adds `branch` and deduplicated logical `results` with
`path`, `ok`, `message`, populated by the service only after aggregate Git push
and sync recording complete. All successful results belong to one commit;
failed/uncertain pushes remain HTTP errors, with no invented partial successes.
Existing response members remain unchanged.

## Validation

The local UI5 harness exercises a read-only mock response, companion overwrite/
delete information, fingerprints and stale heads. Service ABAP Unit tests cover
action mapping, preview returning without restore results/transport entities,
and stale-head refusal through test seams. Run those ABAP tests after installation;
the local mock does not execute the ABAP backend.
