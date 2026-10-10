# Bounded-output reads

Prepared on `codex/bounded-read-api`, independently of Notebook versioning.
These are additive read-only extensions. Existing authorization, branch/root
configuration, companion selection, and error handling remain unchanged.
Both endpoints use form-encoded POST requests with `X-Requested-With: XMLHttpRequest`.

## Status: POST /sap/bc/zbpc_git/workbooks

Required: `environment`. Optional existing fields: `kind`, `model`, `dimension`,
`paths` (newline-separated, at most 1,000 paths), `user`, `token`.
Scope restrictions still apply (dimension members and security are environment scoped).
New optional `changedOnly`: omitted/empty or `false` retains the existing response;
`true` removes only rows with `status=UNCHANGED`, after comparison. Case-sensitive;
other values return HTTP 400. Other statuses, including conflicts and deletions,
remain present. Selected paths still include companion files before filtering;
a filtered response need not contain unchanged companions and is not a restore plan.

Response shape is unchanged:
`{branch, branchFound, commit, timings, workbooks:[{path,kind,memberDescription,model,team,status,inBpc,changedAt,changedBy,size}]}`.
An empty filtered result still contains head and timing metadata. This is not a
pagination or incremental-change cursor. Scope metadata/generated-object listing
still happens before selected-path filtering; changedOnly reduces output, not scanning.

## Diff: POST /sap/bc/zbpc_git/diff

Required: `environment`, `path` (maximum 255 characters). Optional existing fields:
`user`, `token`. Branch and root are taken from saved environment configuration.
New optional `mode`: omitted/empty or `full` retains existing behavior;
`summary` omits `bpcText` and `gitText` keys from every part. Case-sensitive;
other values return HTTP 400.

Summary response:
`{head,parts:[{path,inBpc,inGit,changed,textAvailable,message,bpcSize,gitSize}]}`.
Full responses additionally include `bpcText` and `gitText` strings.
Sizes are bytes; presence, comparison flags, decoding availability and errors are
identical between modes for the same inputs. Content is still read, compared and
validated for decoding in summary mode; no full source text is returned.
Existing supported types: logic scripts, transformations, conversions, packages,
and package links. Excel companions remain binary comparison only. This does not
add EPM workbook cell editing or diffs. Hunk pagination/cursors are deferred.

## Validation

Local UI5 read-only fixtures cover defaults, changed-only empty results retaining
head metadata, full versus summary keys, and invalid values. A harmless ABAP Unit
regression compares service full/summary results using injected data, without BPC
or Git writes. Native SAP execution requires deploying this test branch first.
No package execution, BPF deploy/edit, or workbook-edit endpoint is introduced.

Checks: 13 local Node regression files pass. ADT in-memory syntax check of the
updated service has no errors (existing ABAP Doc warnings). HTTP syntax check
against the currently installed service reports the new `iv_summary` parameter
as unknown until both updated classes are deployed together. No SAP source was
written through ADT; the branch remains undeployed.
