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
    QUnit.start();
  });
});
