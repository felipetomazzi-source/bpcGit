# bpcGit

Version control for SAP BPC 10.1 (NW) content in Git, starting with EPM
workbooks. The app is a UI5 BSP application, installed with abapGit into
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
| POST | `/workbooks` | Workbooks in BPC and Git with their status (`environment`; optional `user`, `token`) |

Git login works as in abapGit: requests go without credentials first. When the
Git host wants a login, the API answers 403 with `"authRequired": true` and the
app asks for user and personal access token, keeps them in page memory only,
and retries. Nothing is stored.

POST requests must carry `X-Requested-With: XMLHttpRequest` (jQuery sets it), so
a form on another website cannot change data with the user's session.

## Build steps

1. BSP app shell (done)
2. REST handler with `/ping`, shown on the start page (done)
3. Config table `ZBPC_GIT_REPO` and setup screen (done)
4. abapGit wrapper, Git login as in abapGit, "Test connection" (done)
5. Workbook list with Git status; sync table `ZBPC_GIT_STATE`
6. Commit, 7. Restore, 8. History
