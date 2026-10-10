CLASS ltcl_restore_preview DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS actions FOR TESTING.
    METHODS preview_is_read_only FOR TESTING RAISING cx_static_check.
    METHODS companion_plan FOR TESTING RAISING cx_static_check.
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

  METHOD companion_plan.
    TEST-INJECTION restore_overview.
      ls_config-branch = 'main'.
      ls_overview = VALUE #( branch_found = abap_true commit = repeat( val = 'a' occ = 40 )
        workbooks = VALUE #(
          ( path = 'PLAN/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.XLSX' kind = 'TRANSFORMATION'
            generated = abap_true in_bpc = abap_true content = '0102' status = 'MODIFIED_GIT' )
          ( path = 'PLAN/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.TDM' kind = 'TRANSFORMATION'
            generated = abap_true in_bpc = abap_true content = '0304' status = 'DELETED_GIT' ) ) ).
    END-TEST-INJECTION.
    TEST-INJECTION restore_file_service.
      CLEAR lo_files.
    END-TEST-INJECTION.
    DATA(service) = NEW zcl_bpc_git_service( ).
    DATA remote TYPE REF TO zcl_bpc_git_remote.
    service->restore_files( EXPORTING iv_environment = 'TEST' io_remote = remote
      it_paths = VALUE #( ( `PLAN/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.XLSX` )
        ( `PLAN/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.TDM` ) )
      iv_expected_commit = repeat( val = 'a' occ = 40 ) iv_preview = abap_true
      IMPORTING es_preview = DATA(preview) ev_error = DATA(error) ).
    cl_abap_unit_assert=>assert_initial( error ).
    cl_abap_unit_assert=>assert_equals( act = preview-can_restore exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = lines( preview-objects ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( preview-objects[ 1 ]-files ) exp = 2 ).
    DATA(files) = preview-objects[ 1 ]-files.
    cl_abap_unit_assert=>assert_equals( act = files[ 1 ]-action exp = 'UPDATE' ).
    cl_abap_unit_assert=>assert_equals( act = files[ 2 ]-action exp = 'DELETE' ).
    cl_abap_unit_assert=>assert_equals( act = files[ 2 ]-overwrites_bpc exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = files[ 1 ]-current_bpc_sha1
      exp = zcl_bpc_git_remote=>blob_sha1( CONV xstring( '0102' ) ) ).
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

CLASS ltcl_diff_summary DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS summary_preserves_comparison FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltcl_diff_summary IMPLEMENTATION.
  METHOD summary_preserves_comparison.
    TEST-INJECTION diff_sources.
      lt_bpc = VALUE #( ( path = iv_path generated = abap_true content = '4142' ) ).
      lt_paths = VALUE #( ( iv_path ) ).
      ls_branch = VALUE #( commit = repeat( val = 'a' occ = 40 ) files = VALUE #( ( path = iv_path ) ) ).
    END-TEST-INJECTION.
    TEST-INJECTION diff_git_content.
      lv_git = '4143'.
    END-TEST-INJECTION.
    TEST-INJECTION diff_file_service.
      CLEAR lo_files.
    END-TEST-INJECTION.
    DATA(service) = NEW zcl_bpc_git_service( ).
    DATA remote TYPE REF TO zcl_bpc_git_remote.
    DATA(full) = service->get_diff( iv_environment = 'TEST' io_remote = remote iv_path = 'ADMINAPP/PLAN/TEST.LGF' ).
    DATA(summary) = service->get_diff( iv_environment = 'TEST' io_remote = remote
      iv_path = 'ADMINAPP/PLAN/TEST.LGF' iv_summary = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = full-parts[ 1 ]-bpc_text exp = 'AB' ).
    cl_abap_unit_assert=>assert_equals( act = full-parts[ 1 ]-git_text exp = 'AC' ).
    cl_abap_unit_assert=>assert_initial( summary-parts[ 1 ]-bpc_text ).
    cl_abap_unit_assert=>assert_initial( summary-parts[ 1 ]-git_text ).
    CLEAR: full-parts[ 1 ]-bpc_text, full-parts[ 1 ]-git_text.
    cl_abap_unit_assert=>assert_equals( act = summary exp = full ).
    cl_abap_unit_assert=>assert_equals( act = summary-parts[ 1 ]-changed exp = abap_true ).
  ENDMETHOD.
ENDCLASS.
