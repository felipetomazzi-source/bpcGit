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
