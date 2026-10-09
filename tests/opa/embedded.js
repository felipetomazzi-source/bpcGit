sap.ui.getCore().attachInit(function () {
  sap.ui.require(['sap/ui/core/ComponentContainer'], function (ComponentContainer) {
    QUnit.test('Embedded contract and standalone compatibility on UI5 1.52', function (assert) {
      var done = assert.async();
      var component, container;
      var saved = localStorage.getItem('bpcGit.environment');
      localStorage.setItem('bpcGit.environment', 'TEST');
      function waitFor(predicate, next, attempts) {
        attempts = attempts || 0;
        if (predicate()) { next(); }
        else if (attempts > 100) { assert.ok(false, 'Timed out'); cleanup(); done(); }
        else { setTimeout(function () { waitFor(predicate, next, attempts + 1); }, 50); }
      }
      function cleanup() {
        container.destroy(); component.destroy();
        if (saved === null) { localStorage.removeItem('bpcGit.environment'); }
        else { localStorage.setItem('bpcGit.environment', saved); }
      }
      component = sap.ui.component({ name: 'bpc.git', url: '/app/', settings: { embedded: true, environment: 'HOST_A' } });
      container = new ComponentContainer({ component: component, height: '100%' });
      container.placeAt('qunit-fixture');
      waitFor(function () { return component.getModel('app').getProperty('/configured'); }, function () {
        var model = component.getModel('app');
        assert.strictEqual(model.getProperty('/environment'), 'HOST_A', 'Host overrides remembered standalone environment');
        assert.strictEqual(component.getRootControl().byId('page').getShowHeader(), false, 'Embedded header hidden');
        assert.strictEqual(component.getRootControl().byId('environmentSelect').getEnabled(), false, 'Host owns environment');
        assert.strictEqual(model.getProperty('/theme'), sap.ui.getCore().getConfiguration().getTheme(), 'Shared host theme');
        assert.strictEqual(sap.ui.getCore().getConfiguration().getTheme(), 'sap_belize_plus', 'Component preserves host dark theme');
        var back;
        component.attachNavigateBack(function (event) { back = event.getParameter('environment'); });
        component.requestNavigateBack();
        assert.strictEqual(back, 'HOST_A', 'Navigation event includes current environment');
        model.setProperty('/workbooks', [{ path: 'OLD' }]);
        component.setEnvironment('HOST_B');
        assert.strictEqual(model.getProperty('/workbooks').length, 0, 'Switch clears old rows immediately');
        waitFor(function () { return model.getProperty('/configured'); }, function () {
          assert.strictEqual(model.getProperty('/environment'), 'HOST_B', 'Runtime host environment accepted');
          assert.strictEqual(model.getProperty('/overviewLoaded'), false, 'No automatic comparison');
          assert.strictEqual(localStorage.getItem('bpcGit.environment'), 'TEST', 'Embedded selection does not overwrite standalone preference');
          component.setEnvironment('INVALID');
          assert.strictEqual(model.getProperty('/configured'), false, 'Unauthorized environment cannot load repository');
          assert.ok(model.getProperty('/setupError').indexOf('no access') >= 0, 'Unauthorized environment shown explicitly');
          component.setEnvironment('');
          assert.strictEqual(model.getProperty('/setupError'), 'Select an environment in the hub.', 'Empty environment waits for host');
          container.destroy(); component.destroy();
          component = sap.ui.component({ name: 'bpc.git', url: '/app/' });
          container = new ComponentContainer({ component: component }); container.placeAt('qunit-fixture');
          waitFor(function () { return component.getModel('app').getProperty('/configured'); }, function () {
            assert.strictEqual(component.getRootControl().byId('page').getShowHeader(), true, 'Standalone header preserved');
            assert.strictEqual(component.getRootControl().byId('environmentSelect').getEnabled(), true, 'Standalone environment selector preserved');
            assert.strictEqual(component.getModel('app').getProperty('/environment'), 'TEST', 'Standalone remembered environment preserved');
            function themeChanged() {
              sap.ui.getCore().detachThemeChanged(themeChanged);
              assert.strictEqual(component.getModel('app').getProperty('/theme'), 'sap_belize', 'Later host theme changes update component');
              cleanup(); done();
            }
            sap.ui.getCore().attachThemeChanged(themeChanged);
            sap.ui.getCore().applyTheme('sap_belize');
          });
        });
      });
    });
    QUnit.test('Saved branch survives UI5 1.52 item changes', function (assert) {
      var done = assert.async();
      var component = sap.ui.component({ name: 'bpc.git', url: '/app/', settings: { embedded: true, environment: 'HOST_A' } });
      var container = new ComponentContainer({ component: component });
      container.placeAt('qunit-fixture');
      var attempts = 0;
      function check() {
        var model = component.getModel('app');
        if (!model.getProperty('/configured')) {
          if (++attempts < 100) { setTimeout(check, 50); return; }
          assert.ok(false, 'Configuration loaded'); container.destroy(); component.destroy(); done(); return;
        }
        var controller = component.getRootControl().getController();
        var branch = component.getRootControl().byId('branchInput');
        controller._showConfig({ configured: true, url: 'https://example.invalid/repo.git', branch: 'release/test' });
        sap.ui.getCore().applyChanges();
        setTimeout(function () {
          assert.strictEqual(branch.getValue(), 'release/test', 'Saved branch displayed before loading branches');
          model.setProperty('/connection', null);
          model.setProperty('/branches', ['release/test', 'main', 'feature/new']);
          sap.ui.getCore().applyChanges();
          setTimeout(function () {
            assert.strictEqual(branch.getValue(), 'release/test', 'Advertisements preserve branch');
            assert.strictEqual(model.getProperty('/config/branch'), 'release/test', 'Saved branch remains in model');
            branch.setValue('feature/typed');
            branch.fireChange({ value: 'feature/typed' });
            model.setProperty('/connection', null);
            sap.ui.getCore().applyChanges();
            assert.strictEqual(branch.getValue(), 'feature/typed', 'Clearing connection preserves manual branch entry');
            controller._showConfig({ configured: true, url: 'https://example.invalid/repo.git', branch: 'release/test' });
            sap.ui.getCore().applyChanges();
            setTimeout(function () {
              assert.strictEqual(branch.getValue(), 'release/test', 'Configuration refresh restores saved branch');
              container.destroy(); component.destroy(); done();
            }, 0);
          }, 0);
        }, 0);
      }
      check();
    });
    QUnit.test('Commit message precedes a long object list', function (assert) {
      var done = assert.async();
      var component = sap.ui.component({ name: 'bpc.git', url: '/app/', settings: { embedded: true, environment: 'HOST_A' } });
      var container = new ComponentContainer({ component: component });
      container.placeAt('qunit-fixture');
      var attempts = 0;
      function check() {
        if (!component.getModel('app').getProperty('/configured')) {
          if (++attempts < 100) { setTimeout(check, 50); return; }
          assert.ok(false, 'Configuration loaded'); container.destroy(); component.destroy(); done(); return;
        }
        var view = component.getRootControl();
        var rows = [];
        for (var i = 0; i < 60; i++) { rows.push({ name: 'Object ' + i, model: 'PLAN', folder: 'SCRIPTS', path: 'file' + i, status: 'NEW_BPC' }); }
        view.getController()._openCommitDialog(rows);
        var dialog = view.getDependents().filter(function (control) { return control.getMetadata().getName() === 'sap.m.Dialog'; }).pop();
        sap.ui.getCore().applyChanges();
        var content = dialog.getContent();
        assert.ok(content[1].getMetadata().getName() === 'sap.m.Label' && content[2].getMetadata().getName() === 'sap.m.TextArea', 'Message label and editor come first');
        assert.ok(content[4].getMetadata().getName() === 'sap.m.List' && content[4].getItems().length === 60, 'All selected objects follow the message');
        dialog.getBeginButton().firePress();
        assert.strictEqual(content[2].getValueState(), 'Error', 'Blank message still blocks commit');
        dialog.close();
        var model = component.getModel('app');
        var chosen = { path: 'DIMENSIONS/ACCOUNT/MEMBERS/CASH%20TOTAL.xml' };
        var other = { path: 'DIMENSIONS/ACCOUNT/MEMBERS/OTHER.xml', status: 'MODIFIED_BPC' };
        model.setProperty('/loadedScope', { kind: 'DIMMEMBER', model: 'ALL', dimension: 'ACCOUNT' });
        model.setProperty('/overview', { commit: 'a'.repeat(40) });
        model.setProperty('/workbooks', [chosen, other]);
        view.getController()._refreshCommittedRows([chosen], 'b'.repeat(40)).then(function () {
          var refreshed = model.getProperty('/workbooks');
          assert.strictEqual(refreshed.length, 2, 'Targeted refresh retains unrelated objects');
          assert.strictEqual(refreshed.filter(function (row) { return row.path === chosen.path; })[0].status, 'UNCHANGED', 'Committed row refreshed through mocked API');
          assert.strictEqual(model.getProperty('/overview/commit'), 'b'.repeat(40), 'Head updated after selected-path refresh');
          view.getController().onPerformanceLog();
          sap.ui.getCore().applyChanges();
          var logDialog = view.getDependents().filter(function (control) { return control.getTitle && control.getTitle() === 'Performance log'; }).pop();
          var entries = JSON.parse(logDialog.getContent()[1].getValue());
          assert.strictEqual(entries[entries.length - 1].operation, 'commit-refresh', 'Performance dialog includes refresh event');
          assert.strictEqual(entries[entries.length - 1].state, 'completed', 'Performance dialog shows completed state');
          logDialog.close();
          model.setProperty('/loadScope', { kind: 'DIMMEMBER', model: 'ALL', dimension: 'ACCOUNT' });
          view.getController()._loadWorkbooks(true);
          var tries = 0;
          function checkLoad() {
            if (model.getProperty('/workbooksBusy') && ++tries < 100) { setTimeout(checkLoad, 50); return; }
            var loadLog = model.getProperty('/performanceLog');
            assert.strictEqual(loadLog[loadLog.length - 1].operation, 'load', 'Manual Load captured in performance log');
            assert.strictEqual(loadLog[loadLog.length - 1].timings.gitMs, 20, 'Load includes server Git timing');
            assert.strictEqual(loadLog[loadLog.length - 1].timings.gitPullMs, 12, 'Load log includes full pull phase');
            assert.strictEqual(loadLog[loadLog.length - 1].timings.gitRefsMs, 4, 'Load log includes branch discovery phase');
            container.destroy(); component.destroy(); done();
          }
          checkLoad();
        }).catch(function (error) {
          assert.ok(false, error.stack || error.message);
          container.destroy(); component.destroy(); done();
        });
      }
      check();
    });
    QUnit.test('Read-only restore preview API contract', function (assert) {
      var done = assert.async();
      function preview(head) {
        return jQuery.ajax({ url: '/sap/bc/zbpc_git/restore-preview', type: 'POST', dataType: 'json',
          headers: { 'X-Requested-With': 'XMLHttpRequest' },
          data: { environment: 'TEST', commit: head, paths: 'PLAN/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.XLSX' } });
      }
      preview('a'.repeat(40)).then(function (plan) {
        assert.strictEqual(plan.canRestore, true, 'Valid plan can be reviewed');
        assert.strictEqual(plan.objects[0].files.length, 2, 'Workbook companion included');
        assert.strictEqual(plan.objects[0].files[0].overwritesBpc, true, 'Overwrite is explicit');
        assert.strictEqual(plan.objects[0].files[1].action, 'DELETE', 'Companion deletion is explicit');
        assert.strictEqual(plan.objects[0].files[0].currentBpcSha1.length, 40, 'Local fingerprint available');
        return preview('e'.repeat(40));
      }).then(function (plan) {
        assert.strictEqual(plan.canRestore, false, 'Stale head blocks preview');
        assert.strictEqual(plan.objects.length, 0, 'Invalid plan offers no executable objects');
        done();
      }, function (error) { assert.ok(false, String(error)); done(); });
    });
    QUnit.start();
  });
});
