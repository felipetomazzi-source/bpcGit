/* global sap, QUnit */
sap.ui.getCore().attachInit(function () {
  sap.ui.require(['sap/ui/test/Opa5', 'sap/ui/test/opaQunit', 'sap/ui/test/actions/Press'],
    function (Opa5, opaTest, Press) {
      'use strict';
      var requests = [];
      jQuery(document).ajaxSend(function (event, xhr, settings) {
        if (settings.url.indexOf('/sap/bc/zbpc_git/') === 0) { requests.push(settings.url); }
      });
      Opa5.extendConfig({ autoWait: true, timeout: 20, viewName: 'bpc.git.view.App' });
      QUnit.done(function (result) { window.opaResult = result; });
      opaTest('Dimension selection is metadata only; Load renders a decoded member name', function (Given, When, Then) {
        Given.iStartMyUIComponent({ componentConfig: { name: 'bpc.git' } });
        Then.waitFor({ id: 'loadType', check: function (select) {
          return select.getModel('app').getProperty('/configured') && !select.getModel('app').getProperty('/modelsBusy');
        }, success: function (select) {
          Opa5.assert.strictEqual(select.getSelectedKey(), 'REPORT', 'Reports remain the default');
          Opa5.assert.ok(!requests.some(function (url) { return url.indexOf('/workbooks') !== -1; }), 'Startup does not compare objects');
        }});
        When.waitFor({ id: 'loadType', actions: new Press() });
        When.waitFor({ controlType: 'sap.ui.core.Item', searchOpenDialogs: true,
          matchers: function (item) { return item.getKey() === 'DIMMEMBER'; }, actions: new Press() });
        Then.waitFor({ id: 'loadDimension', check: function (select) { return select.getSelectedKey() === 'ACCOUNT'; },
          success: function (select) {
            Opa5.assert.strictEqual(select.getItems()[0].getText(), 'All supported dimensions', 'All dimensions is explicitly available');
            Opa5.assert.ok(!requests.some(function (url) { return url.indexOf('/workbooks') !== -1; }), 'Selecting members fetches metadata only');
          }});
        Then.waitFor({ id: 'loadModel', autoWait: false, success: function (select) {
          Opa5.assert.notOk(select.getEnabled(), 'Model selection is disabled for shared dimensions');
        }});
        When.waitFor({ controlType: 'sap.m.Button', matchers: function (button) { return button.getText() === 'Load'; }, actions: new Press() });
        Then.waitFor({ id: 'workbookTable', check: function (table) { return table.getItems().length === 1 && !table.getBusy(); },
          success: function (table) {
            Opa5.assert.strictEqual(table.getModel('app').getProperty('/loadedScope/dimension'), 'ACCOUNT', 'Selected dimension reaches the load');
            Opa5.assert.ok(table.getDomRef().textContent.indexOf('CASH TOTAL - Cash total') !== -1, 'Rendered member name uses a space');
          }});
        Then.iTeardownMyUIComponent();
      });
      QUnit.start();
    });
});
