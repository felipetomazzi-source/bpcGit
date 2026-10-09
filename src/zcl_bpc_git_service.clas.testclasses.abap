CLASS ltcl_restore_preview DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS actions FOR TESTING.
    METHODS preview_is_read_only FOR TESTING RAISING cx_static_check.
    METHODS stale_head FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltcl_restore_preview IMPLEMENTATION.
  METHOD actions.
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_service=>restore_action(
      VALUE #( status = 'UNCHANGED' in_bpc = abap_true ) ) exp = 'UNCHANGED' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_service=>restore_action(
      VALUE #( status = 'DELETED_GIT' in_bpc = abap_true ) ) exp = 'DELETE' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_service=>restore_action(
      VALUE #( status = 'MODIFIED_GIT' in_bpc = abap_true ) ) exp = 'UPDATE' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_service=>restore_action(
      VALUE #( status = 'NEW_GIT' ) ) exp = 'CREATE' ).
  ENDMETHOD.

  METHOD preview_is_read_only.
    TEST-INJECTION restore_overview.
      ls_config-branch = 'main'.
      ls_overview = VALUE #( branch_found = abap_true commit = repeat( val = 'a' occ = 40 )
        workbooks = VALUE #( ( path = 'DIMENSIONS/ACCOUNT/MEMBERS/CASH.xml'
          kind = 'DIMMEMBER' generated = abap_true status = 'NEW_GIT' git_sha1 = repeat( val = 'b' occ = 40 ) ) ) ).
    END-TEST-INJECTION.
    TEST-INJECTION restore_file_service.
      CLEAR lo_files.
    END-TEST-INJECTION.
    DATA(service) = NEW zcl_bpc_git_service( ).
    DATA remote TYPE REF TO zcl_bpc_git_remote.
    service->restore_files( EXPORTING iv_environment = 'TEST' io_remote = remote
      it_paths = VALUE #( ( `DIMENSIONS/ACCOUNT/MEMBERS/CASH.xml` ) )
      iv_expected_commit = repeat( val = 'a' occ = 40 ) iv_preview = abap_true
      IMPORTING es_preview = DATA(preview) ev_error = DATA(error)
        et_results = DATA(results) et_entities = DATA(entities) ).
    cl_abap_unit_assert=>assert_initial( error ).
    cl_abap_unit_assert=>assert_equals( act = preview-can_restore exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = preview-objects[ 1 ]-files[ 1 ]-action exp = 'CREATE' ).
    cl_abap_unit_assert=>assert_initial( results ).
    cl_abap_unit_assert=>assert_initial( entities ).
  ENDMETHOD.

  METHOD stale_head.
    TEST-INJECTION restore_overview.
      ls_config-branch = 'main'.
      ls_overview = VALUE #( branch_found = abap_true commit = repeat( val = 'b' occ = 40 ) ).
    END-TEST-INJECTION.
    DATA(service) = NEW zcl_bpc_git_service( ).
    DATA remote TYPE REF TO zcl_bpc_git_remote.
    service->restore_files( EXPORTING iv_environment = 'TEST' io_remote = remote
      it_paths = VALUE #( ( `DIMENSIONS/ACCOUNT/MEMBERS/CASH.xml` ) )
      iv_expected_commit = repeat( val = 'a' occ = 40 ) iv_preview = abap_true
      IMPORTING es_preview = DATA(preview) ev_error = DATA(error) ).
    cl_abap_unit_assert=>assert_not_initial( error ).
    cl_abap_unit_assert=>assert_initial( preview-can_restore ).
    cl_abap_unit_assert=>assert_initial( preview-objects ).
    cl_abap_unit_assert=>assert_equals( act = preview-current_head exp = repeat( val = 'b' occ = 40 ) ).
  ENDMETHOD.
ENDCLASS.
