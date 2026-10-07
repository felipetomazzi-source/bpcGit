# Local OPA5 browser test

This harness runs the actual BSP Component, XML view and controller with
OpenUI5 **1.52.48**, QUnit and OPA5. It serves mock API responses on loopback;
it never connects to SAP or GitHub. Commit, restore and configuration writes
are disabled. This checks frontend behavior, not SAP backend acceptance.

From the repository root:

```powershell
npm ci --ignore-scripts --prefix tests/opa
node tests/opa/server.cjs
```

Open `http://127.0.0.1:4173` in a browser. The QUnit page reports success or
failure. Stop the server with Ctrl+C. Node.js 20 or newer is recommended.
Dependencies are pinned and installed only under `tests/opa/node_modules`.
The local server compiles the original 1.52 Belize theme through SAP's
`less-openui5`; it does not depend on a public UI5 CDN or change deployed files.

To drive the same page with the Playwright CLI:

```powershell
playwright-cli -s=bpcgit-opa open http://127.0.0.1:4173
playwright-cli -s=bpcgit-opa run-code 'async page => { await page.waitForFunction(() => window.opaResult); const result = await page.evaluate(() => window.opaResult); if (result.failed || result.total !== 8) { throw new Error(JSON.stringify(result)); } return result; }'
playwright-cli -s=bpcgit-opa close
```

The journey performs real OPA5 Press actions on the object dropdown and Load
button. Eight assertions cover startup without object comparison, the default
report scope, metadata-only member selection, the explicit All dimensions
option, disabled model selection, dimension-scoped loading, and a decoded
member name rendered in the table under its group row. The mock refuses an incorrectly scoped
member load. Native BPC save/restore and real authorization still require SAP
acceptance after abapGit activation.

Open `/embedded.html` on the same local server for the BPCIO embedding contract journey, including a host dark theme and standalone recreation. All API fixtures remain local and read-only.
