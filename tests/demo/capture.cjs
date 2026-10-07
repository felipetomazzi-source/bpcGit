// Captures the screenshots in docs/guide-images from the demo server
// (node tests/demo/server.cjs). Needs puppeteer-core and Chrome:
//   node tests/demo/capture.cjs docs/guide-images
const puppeteer = require('puppeteer-core');
const path = require('path');
const OUT = process.argv[2];
const wait = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true, defaultViewport: { width: 1360, height: 820, deviceScaleFactor: 2 } });
  const page = await browser.newPage();
  page.on('pageerror', e => console.log('pageerror', e.message));
  await page.goto('http://127.0.0.1:4174/', { waitUntil: 'networkidle0' });
  await page.waitForFunction(() => window.sap && sap.ui.getCore().byId('__component0---app'), { timeout: 60000 });
  await wait(1500);
  const ctl = (fn, ...a) => page.evaluate(fn, ...a);
  const shot = async (name, selector) => {
    await wait(700);
    const file = path.join(OUT, name + '.png');
    if (selector) {
      const el = await page.$(selector);
      await el.screenshot({ path: file });
    } else {
      await page.screenshot({ path: file });
    }
    console.log('saved', name);
  };
  const closeDialogs = () => ctl(() => {
    sap.m.InstanceManager.getOpenDialogs().forEach(d => d.close());
  });
  const select = names => ctl(names => {
    const c = sap.ui.getCore().byId('__component0---app').getController();
    const m = c._model;
    m.getProperty('/workbooks').forEach(r => { r.selected = names.indexOf(r.name) >= 0; });
    m.refresh(true);
    c._updateSelection();
  }, names);

  // 1. Repository setup, expanded, and the collapsed header
  await ctl(() => sap.ui.getCore().byId('__component0---app--repositoryPanel').setExpanded(true));
  await wait(1200);
  await shot('01_setup', '#__component0---app--repositoryPanel');
  await ctl(() => sap.ui.getCore().byId('__component0---app--repositoryPanel').setExpanded(false));
  await wait(1200);
  await page.screenshot({ path: path.join(OUT, '00_header.png'), clip: { x: 0, y: 0, width: 1360, height: 110 } });
  // 2. Load logic scripts with the setup collapsed
  await ctl(() => {
    const c = sap.ui.getCore().byId('__component0---app').getController();
    sap.ui.getCore().byId('__component0---app--repositoryPanel').setExpanded(false);
    c._model.setProperty('/loadScope/kind', 'SCRIPT');
    c.onLoadWorkbooks();
  });
  await wait(2500);
  await shot('02_scripts');
  // 3. Diff
  await select(['CLEAR_FORECAST.LGF']);
  await shot('03_selected');
  await ctl(() => sap.ui.getCore().byId('__component0---app').getController().onDiff());
  await wait(1500);
  await shot('04_diff', '.sapMDialog');
  await closeDialogs();
  // 4. History
  await select(['COPY_ACTUAL_TO_FCST.LGF']);
  await ctl(() => sap.ui.getCore().byId('__component0---app').getController().onHistory());
  await wait(1500);
  await ctl(() => {
    const list = document.querySelector('.sapMDialog .sapMList');
    const first = list && sap.ui.getCore().byId(list.id).getItems()[1];
    if (first) { sap.ui.getCore().byId(list.id).setSelectedItem(first); sap.ui.getCore().byId(list.id).fireSelectionChange({ listItem: first }); }
  });
  await shot('05_history', '.sapMDialog');
  await closeDialogs();
  // 5. Commit
  await select(['CLEAR_FORECAST.LGF', 'INTERCO_ELIMINATION.LGF']);
  await ctl(() => sap.ui.getCore().byId('__component0---app').getController().onCommit());
  await wait(1200);
  await page.evaluate(() => {
    const ta = document.querySelector('.sapMDialog textarea');
    if (ta) { const c = sap.ui.getCore().byId(ta.id.replace(/-inner$/, '')); c.setValue('Clear forecast only for open periods; add intercompany elimination'); }
  });
  await shot('06_commit', '.sapMDialog');
  await closeDialogs();
  // 6. Restore
  await select(['CURRENCY_CONVERSION.LGF']);
  await ctl(() => sap.ui.getCore().byId('__component0---app').getController().onRestore());
  await wait(1500);
  await shot('07_restore', '.sapMDialog');
  await closeDialogs();
  // 7. Add to transport
  await select(['CLEAR_FORECAST.LGF', 'COPY_ACTUAL_TO_FCST.LGF']);
  await ctl(() => sap.ui.getCore().byId('__component0---app').getController().onAddToTransport());
  await wait(1500);
  await shot('08_transport', '.sapMDialog');
  await closeDialogs();
  await select([]);
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
