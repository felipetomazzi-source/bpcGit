CLASS zcl_bpc_git_http DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_http_extension.
  PRIVATE SECTION.
    "! Request and response of the current call.
    DATA mo_server TYPE REF TO if_http_server.
    CLASS-METHODS has_form_field
      IMPORTING it_fields TYPE tihttpnvp iv_name TYPE string
      RETURNING VALUE(rv_present) TYPE abap_bool.
    "! Set once read_field has answered with 400; later reads are skipped.
    DATA mv_invalid TYPE abap_bool.
    " Resources served by this handler.
    CONSTANTS:
      BEGIN OF c_resource,
        ping         TYPE string VALUE '/ping',
        environments TYPE string VALUE '/environments',
        config       TYPE string VALUE '/config',
        connection   TYPE string VALUE '/connection',
        diagnostics  TYPE string VALUE '/diagnostics',
        models       TYPE string VALUE '/models',
        dimensions   TYPE string VALUE '/dimensions',
        workbooks    TYPE string VALUE '/workbooks',
        commit       TYPE string VALUE '/commit',
        restore      TYPE string VALUE '/restore',
        history      TYPE string VALUE '/history',
        diff         TYPE string VALUE '/diff',
      END OF c_resource.
    "! Longest Git user name and access token accepted.
    CONSTANTS c_max_user TYPE i VALUE 255 ##NO_TEXT.
    CONSTANTS c_max_token TYPE i VALUE 1024 ##NO_TEXT.
    "! Longest commit message, and most workbooks in one commit.
    CONSTANTS c_max_message TYPE i VALUE 4000 ##NO_TEXT.
    CONSTANTS c_max_paths TYPE i VALUE 1000 ##NO_TEXT.
    CONSTANTS:
      BEGIN OF c_method,
        get  TYPE string VALUE 'GET',
        post TYPE string VALUE 'POST',
      END OF c_method.

    "! Sends 405 unless the request uses the expected method. A POST must also
    "! carry X-Requested-With, which a cross-site form cannot set (CSRF guard).
    METHODS require_method
      IMPORTING iv_method TYPE string
      RETURNING VALUE(rv_allowed) TYPE abap_bool.
    "! Reads a form field. Answers 400 and sets mv_invalid if it is longer than
    "! iv_max_length, or empty while iv_required is set.
    METHODS read_field
      IMPORTING iv_name TYPE string iv_label TYPE string
                iv_max_length TYPE i iv_required TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rv_value) TYPE string.
    "! Reports the caller, the system and the abapGit installation.
    METHODS handle_ping.
    METHODS handle_environments
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    METHODS handle_get_config
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    METHODS handle_save_config
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    "! Reads the branches of the environment's repository; with the optional
    "! user and token, also checks push access. Credentials are used for this
    "! request only and never stored.
    METHODS handle_test_connection
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    METHODS handle_diagnostics
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    "! Workbooks of the environment in BPC and Git, with their status.
    METHODS handle_dimensions IMPORTING io_service TYPE REF TO zcl_bpc_git_service RAISING cx_uj_static_check.
    METHODS handle_models
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    METHODS handle_workbooks
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    "! Commits the BPC version of the selected workbooks in one commit.
    "! Fields: environment, message, commit (head the user saw), paths (one
    "! repository path per line), and the optional user and token.
    METHODS handle_commit
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    "! Writes the Git version of the selected files into BPC. Fields:
    "! environment, commit (head the user saw), paths (one per line), and the
    "! optional user and token. Answers the result of each file.
    METHODS handle_restore
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    METHODS handle_history
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      RAISING cx_uj_static_check.
    METHODS handle_diff IMPORTING io_service TYPE REF TO zcl_bpc_git_service RAISING cx_uj_static_check.
    METHODS read_history_depth
      RETURNING VALUE(rv_depth) TYPE i.
    "! Reads the paths field: one repository path per line. Answers 400 and
    "! returns nothing if there are none or too many.
    METHODS read_paths
      RETURNING VALUE(rt_paths) TYPE string_table.
    "! Reads environment, user and token of a request that talks to the Git
    "! host and creates the Git client for the environment's repository.
    "! Answers the request and returns nothing if the input is invalid.
    METHODS create_remote
      IMPORTING io_service TYPE REF TO zcl_bpc_git_service
      EXPORTING ev_environment TYPE uj_appset_id
                es_config TYPE zbpc_git_repo
                eo_remote TYPE REF TO zcl_bpc_git_remote
                ev_with_login TYPE abap_bool
      RAISING cx_uj_static_check zcx_abapgit_exception.
    "! Answers an abapGit error: asks for a login if the Git host wants one.
    METHODS respond_git_error
      IMPORTING ix_error TYPE REF TO zcx_abapgit_exception
                iv_with_login TYPE abap_bool.
    "! Repository setup as JSON; "configured" is false when there is none.
    METHODS config_json
      IMPORTING is_config TYPE zbpc_git_repo iv_environment TYPE uj_appset_id
      RETURNING VALUE(rv_json) TYPE string.
    METHODS respond
      IMPORTING iv_code TYPE i iv_reason TYPE string iv_json TYPE string
                iv_allow TYPE string OPTIONAL.
    "! iv_auth_required tells the app to ask for the Git user and token.
    METHODS respond_error
      IMPORTING iv_code TYPE i iv_reason TYPE string iv_message TYPE string
                iv_allow TYPE string OPTIONAL
                iv_auth_required TYPE abap_bool DEFAULT abap_false.
    "! JSON string literal, without the padding of fixed length fields.
    METHODS quote
      IMPORTING iv_value TYPE clike
      RETURNING VALUE(rv_json) TYPE string.
ENDCLASS.

CLASS zcl_bpc_git_http IMPLEMENTATION.
  METHOD if_http_extension~handle_request.
    mo_server = server.
    server->response->set_content_type( 'application/json; charset=utf-8' ).
    server->response->set_header_field( name = 'Cache-Control' value = 'no-store' ).
    server->response->set_header_field( name = 'X-Content-Type-Options' value = 'nosniff' ).

    DATA(lv_path) = server->request->get_header_field( '~path_info' ).
    REPLACE REGEX '/$' IN lv_path WITH ''.
    TRY.
        DATA(lo_service) = NEW zcl_bpc_git_service( ).
        CASE lv_path.
          WHEN c_resource-ping.
            IF require_method( c_method-get ).
              handle_ping( ).
            ENDIF.
          WHEN c_resource-environments.
            IF require_method( c_method-get ).
              handle_environments( lo_service ).
            ENDIF.
          WHEN c_resource-config.
            IF server->request->get_method( ) = c_method-get.
              handle_get_config( lo_service ).
            ELSEIF require_method( c_method-post ).
              handle_save_config( lo_service ).
            ENDIF.
          WHEN c_resource-connection.
            IF require_method( c_method-post ).
              handle_test_connection( lo_service ).
            ENDIF.
          WHEN c_resource-diagnostics.
            IF require_method( c_method-post ).
              handle_diagnostics( lo_service ).
            ENDIF.
          WHEN c_resource-dimensions.
            IF require_method( c_method-get ).
              handle_dimensions( lo_service ).
            ENDIF.
          WHEN c_resource-models.
            IF require_method( c_method-get ).
              handle_models( lo_service ).
            ENDIF.
          WHEN c_resource-workbooks.
            IF require_method( c_method-post ).
              handle_workbooks( lo_service ).
            ENDIF.
          WHEN c_resource-commit.
            IF require_method( c_method-post ).
              handle_commit( lo_service ).
            ENDIF.
          WHEN c_resource-history.
            IF require_method( c_method-post ).
              handle_history( lo_service ).
            ENDIF.
          WHEN c_resource-diff.
            IF require_method( c_method-post ) = abap_true.
              handle_diff( lo_service ).
            ENDIF.
          WHEN c_resource-restore.
            IF require_method( c_method-post ).
              handle_restore( lo_service ).
            ENDIF.
          WHEN OTHERS.
            respond_error( iv_code = 404 iv_reason = 'Not Found'
                           iv_message = 'Unknown resource' ).
        ENDCASE.
      CATCH cx_uj_no_auth.
        respond_error( iv_code = 403 iv_reason = 'Forbidden'
                       iv_message = 'BPC access denied' ).
      CATCH cx_uj_static_check.
        respond_error( iv_code = 500 iv_reason = 'Internal Server Error'
                       iv_message = 'Cannot load BPC metadata' ).
      CATCH cx_root.
        respond_error( iv_code = 500 iv_reason = 'Internal Server Error'
                       iv_message = 'Unexpected error in the bpcGit API' ).
    ENDTRY.
  ENDMETHOD.

  METHOD handle_ping.
    DATA(lv_abapgit) = zcl_bpc_git_remote=>get_abapgit_version( ).
    respond( iv_code = 200 iv_reason = 'OK' iv_json =
      `{"user":` && quote( sy-uname ) &&
      `,"system":` && quote( sy-sysid ) &&
      `,"client":` && quote( sy-mandt ) &&
      `,"abapGit":{"installed":` && COND string( WHEN lv_abapgit IS INITIAL THEN `false` ELSE `true` ) &&
      `,"version":` && quote( lv_abapgit ) && `}}` ).
  ENDMETHOD.

  METHOD handle_environments.
    DATA lv_json TYPE string.
    DATA lv_separator TYPE string.
    DATA(lt_environments) = io_service->get_environments( ).
    LOOP AT lt_environments INTO DATA(lv_environment).
      lv_json = lv_json && lv_separator && `{"id":` && quote( lv_environment ) && `}`.
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json = `{"environments":[` && lv_json && `]}` ).
  ENDMETHOD.

  METHOD handle_get_config.
    DATA lv_environment_id TYPE uj_appset_id.
    DESCRIBE FIELD lv_environment_id LENGTH DATA(lv_length) IN CHARACTER MODE.
    DATA(lv_environment) = read_field( iv_name = 'environment' iv_label = 'environment'
                                       iv_max_length = lv_length ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    lv_environment_id = lv_environment.
    respond( iv_code = 200 iv_reason = 'OK'
             iv_json = config_json( is_config = io_service->get_config( lv_environment_id )
                                    iv_environment = lv_environment_id ) ).
  ENDMETHOD.

  METHOD handle_save_config.
    DATA ls_config TYPE zbpc_git_repo.
    DESCRIBE FIELD ls_config-appset LENGTH DATA(lv_environment_length) IN CHARACTER MODE.
    DESCRIBE FIELD ls_config-url LENGTH DATA(lv_url_length) IN CHARACTER MODE.
    DESCRIBE FIELD ls_config-branch LENGTH DATA(lv_branch_length) IN CHARACTER MODE.
    DATA(lv_environment) = read_field( iv_name = 'environment' iv_label = 'environment'
                                       iv_max_length = lv_environment_length ).
    DATA(lv_url) = read_field( iv_name = 'url' iv_label = 'repository URL'
                               iv_max_length = lv_url_length ).
    DATA(lv_branch) = read_field( iv_name = 'branch' iv_label = 'branch'
                                  iv_max_length = lv_branch_length iv_required = abap_false ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    ls_config-appset = lv_environment.
    ls_config-url = lv_url.
    ls_config-branch = lv_branch.
    DATA lt_fields TYPE tihttpnvp.
    mo_server->request->get_form_fields( CHANGING fields = lt_fields ).
    IF has_form_field( it_fields = lt_fields iv_name = 'rootFolder' ) = abap_true.
      ls_config-root_folder = read_field( iv_name = 'rootFolder' iv_label = 'BPC root folder'
        iv_max_length = 255 iv_required = abap_false ).
    ELSE.
      DATA(ls_saved) = io_service->get_config( ls_config-appset ).
      ls_config-root_folder = ls_saved-root_folder.
    ENDIF.
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    DATA(lv_lfs_enabled) = read_field( iv_name = 'lfsEnabled' iv_label = 'Git LFS enabled'
      iv_max_length = 5 iv_required = abap_false ).
    DATA(lv_lfs_mb) = read_field( iv_name = 'lfsThresholdMb' iv_label = 'Git LFS threshold'
      iv_max_length = 3 iv_required = abap_false ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    IF lv_lfs_enabled IS NOT INITIAL AND lv_lfs_enabled <> 'true' AND lv_lfs_enabled <> 'false'.
      respond_error( iv_code = 400 iv_reason = 'Bad Request' iv_message = 'Invalid Git LFS option' ).
      RETURN.
    ENDIF.
    ls_config-lfs_enabled = xsdbool( lv_lfs_enabled = 'true' ).
    ls_config-lfs_mb = 5.
    IF lv_lfs_mb IS NOT INITIAL.
      IF lv_lfs_mb CN '0123456789'.
        respond_error( iv_code = 400 iv_reason = 'Bad Request' iv_message = 'Git LFS threshold must be a whole number from 1 to 100 MB' ).
        RETURN.
      ENDIF.
      ls_config-lfs_mb = lv_lfs_mb.
    ENDIF.

    DATA(lv_message) = io_service->save_config( ls_config ).
    IF lv_message IS NOT INITIAL.
      respond_error( iv_code = 400 iv_reason = 'Bad Request' iv_message = lv_message ).
      RETURN.
    ENDIF.
    respond( iv_code = 200 iv_reason = 'OK'
             iv_json = config_json( is_config = io_service->get_config( ls_config-appset )
                                    iv_environment = ls_config-appset ) ).
  ENDMETHOD.

  METHOD handle_test_connection.
    DATA ls_config TYPE zbpc_git_repo.
    DATA lo_remote TYPE REF TO zcl_bpc_git_remote.
    DATA lv_with_login TYPE abap_bool.
    TRY.
        create_remote( EXPORTING io_service = io_service
                       IMPORTING es_config = ls_config eo_remote = lo_remote
                                 ev_with_login = lv_with_login ).
        IF lo_remote IS NOT BOUND.
          RETURN.
        ENDIF.
        DATA(ls_result) = lo_remote->test_connection( ls_config-branch ).
      CATCH zcx_abapgit_exception INTO DATA(lx_git).
        respond_git_error( ix_error = lx_git iv_with_login = lv_with_login ).
        RETURN.
    ENDTRY.

    DATA lv_branches TYPE string.
    DATA lv_separator TYPE string.
    LOOP AT ls_result-branches INTO DATA(lv_branch).
      lv_branches = lv_branches && lv_separator && quote( lv_branch ).
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json =
      `{"url":` && quote( ls_config-url ) &&
      `,"branch":` && quote( ls_config-branch ) &&
      `,"branches":[` && lv_branches && `]` &&
      `,"branchFound":` && COND string( WHEN ls_result-branch_found = abap_true THEN `true` ELSE `false` ) &&
      `,"pushChecked":` && COND string( WHEN ls_result-push_checked = abap_true THEN `true` ELSE `false` ) &&
      `,"pushOk":` && COND string( WHEN ls_result-push_ok = abap_true THEN `true` ELSE `false` ) &&
      `,"pushMessage":` && quote( ls_result-push_message ) && `}` ).
  ENDMETHOD.

  METHOD handle_diagnostics.
    DATA ls_config TYPE zbpc_git_repo.
    DATA lo_remote TYPE REF TO zcl_bpc_git_remote.
    TRY.
        create_remote( EXPORTING io_service = io_service
          IMPORTING es_config = ls_config eo_remote = lo_remote ).
        IF lo_remote IS NOT BOUND.
          RETURN.
        ENDIF.
        DATA(ls_result) = lo_remote->auth_diagnostics( ).
      CATCH zcx_abapgit_exception INTO DATA(lx_git).
        respond_git_error( ix_error = lx_git iv_with_login = abap_false ).
        RETURN.
    ENDTRY.
    DATA lv_checks TYPE string.
    DATA lv_separator TYPE string.
    LOOP AT ls_result-checks INTO DATA(ls_check).
      lv_checks = lv_checks && lv_separator && `{"check":` && quote( ls_check-check_name ) &&
        `,"method":` && quote( ls_check-method ) && `,"url":` && quote( ls_check-url ) &&
        `,"authScheme":` && quote( ls_check-auth_scheme ) && `,"status":` && CONV string( ls_check-status ) &&
        `,"statusSource":` && quote( ls_check-status_source ) &&
        `,"elapsedMs":` && CONV string( ls_check-elapsed_ms ) &&
        `,"ok":` && COND string( WHEN ls_check-ok = abap_true THEN `true` ELSE `false` ) &&
        `,"authRequired":` && COND string( WHEN ls_check-auth_required = abap_true THEN `true` ELSE `false` ) &&
        `,"message":` && quote( ls_check-message ) && `}`.
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json =
      `{"environment":` && quote( ls_config-appset ) && `,"branch":` && quote( ls_config-branch ) &&
      `,"credentialSource":"request form only; no SAP credential store",` &&
      `"credentialFound":` && COND string( WHEN ls_result-credentials_found = abap_true THEN `true` ELSE `false` ) &&
      `,"username":` && quote( ls_result-username ) && `,"restApiUrl":` && quote( ls_result-rest_url ) &&
      `,"restAuthScheme":` && quote( ls_result-rest_scheme ) && `,"restChecked":false,` &&
      `"checks":[` && lv_checks && `]}` ).
  ENDMETHOD.

  METHOD handle_dimensions.
    DATA(lv_environment) = read_field( iv_name = 'environment' iv_label = 'Environment' iv_max_length = 20 ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    DATA(lt_dimensions) = io_service->available_dimensions( CONV #( lv_environment ) ).
    DATA lv_json TYPE string.
    DATA lv_separator TYPE string.
    LOOP AT lt_dimensions INTO DATA(lv_dimension).
      lv_json = lv_json && lv_separator && quote( lv_dimension ).
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json = `{"dimensions":[` && lv_json && `]}` ).
  ENDMETHOD.

  METHOD handle_models.
    DATA(lv_environment) = read_field( iv_name = 'environment' iv_label = 'Environment' iv_max_length = 20 ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    DATA(lt_models) = io_service->available_models( CONV #( lv_environment ) ).
    DATA lv_json TYPE string.
    DATA lv_separator TYPE string.
    LOOP AT lt_models INTO DATA(lv_model).
      lv_json = lv_json && lv_separator && quote( lv_model ).
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json = `{"models":[` && lv_json && `]}` ).
  ENDMETHOD.

  METHOD handle_workbooks.
    DATA(lv_kind) = read_field( iv_name = 'kind' iv_label = 'Object type' iv_max_length = 20 iv_required = abap_false ).
    DATA(lv_model) = read_field( iv_name = 'model' iv_label = 'Model' iv_max_length = 20 iv_required = abap_false ).
    DATA(lv_dimension) = read_field( iv_name = 'dimension' iv_label = 'Dimension' iv_max_length = 20 iv_required = abap_false ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    IF lv_kind IS NOT INITIAL AND lv_kind <> 'WORKBOOK' AND lv_kind <> 'SCRIPT'
        AND lv_kind <> 'DIMMEMBER' AND lv_kind <> 'BPF' AND lv_kind <> 'TEAM' AND lv_kind <> 'TASKPROFILE' AND lv_kind <> 'DATAPROFILE'
        AND lv_kind <> 'REPORT' AND lv_kind <> 'SCHEDULE' AND lv_kind <> 'OTHER'
        AND lv_kind <> 'TRANSFORMATION' AND lv_kind <> 'CONVERSION' AND lv_kind <> 'PACKAGE' AND lv_kind <> 'LINK'.
      respond_error( iv_code = 400 iv_reason = 'Bad Request' iv_message = 'Choose a supported object type' ).
      RETURN.
    ENDIF.
    IF ( lv_dimension IS NOT INITIAL AND lv_kind <> 'DIMMEMBER' )
        OR ( lv_kind = 'DIMMEMBER' AND lv_model IS NOT INITIAL ).
      respond_error( iv_code = 400 iv_reason = 'Bad Request'
        iv_message = 'Dimension members apply to the environment; select a dimension and leave model empty' ).
      RETURN.
    ENDIF.
    IF ( lv_kind = 'TEAM' OR lv_kind = 'TASKPROFILE' OR lv_kind = 'DATAPROFILE' ) AND lv_model IS NOT INITIAL.
      respond_error( iv_code = 400 iv_reason = 'Bad Request' iv_message = 'Security definitions apply to the environment; leave model empty' ).
      RETURN.
    ENDIF.
    DATA lv_environment TYPE uj_appset_id.
    DATA ls_config TYPE zbpc_git_repo.
    DATA lo_remote TYPE REF TO zcl_bpc_git_remote.
    DATA lv_with_login TYPE abap_bool.
    TRY.
        create_remote( EXPORTING io_service = io_service
                       IMPORTING ev_environment = lv_environment es_config = ls_config
                                 eo_remote = lo_remote ev_with_login = lv_with_login ).
        IF lo_remote IS NOT BOUND.
          RETURN.
        ENDIF.
        DATA(ls_overview) = io_service->get_overview( iv_environment = lv_environment
                                                      io_remote = lo_remote iv_kind = lv_kind iv_model = lv_model iv_dimension = lv_dimension ).
      CATCH zcx_abapgit_exception INTO DATA(lx_git).
        respond_git_error( ix_error = lx_git iv_with_login = lv_with_login ).
        RETURN.
    ENDTRY.

    DATA lv_json TYPE string.
    DATA lv_separator TYPE string.
    LOOP AT ls_overview-workbooks INTO DATA(ls_workbook).
      lv_json = lv_json && lv_separator &&
        `{"path":` && quote( ls_workbook-path ) &&
        `,"kind":` && quote( ls_workbook-kind ) &&
        `,"memberDescription":` && quote( ls_workbook-member_description ) &&
        `,"model":` && quote( ls_workbook-model ) &&
        `,"team":` && quote( ls_workbook-team ) &&
        `,"status":` && quote( ls_workbook-status ) &&
        `,"inBpc":` && COND string( WHEN ls_workbook-in_bpc = abap_true THEN `true` ELSE `false` ) &&
        `,"changedAt":` && quote( ls_workbook-changed_at ) &&
        `,"changedBy":` && quote( ls_workbook-changed_by ) &&
        `,"size":` && |{ ls_workbook-size }| && `}`.
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json =
      `{"branch":` && quote( ls_config-branch ) &&
      `,"branchFound":` && COND string( WHEN ls_overview-branch_found = abap_true THEN `true` ELSE `false` ) &&
      `,"commit":` && quote( ls_overview-commit ) &&
      `,"timings":{"bpcMs":` && |{ ls_overview-bpc_ms }| &&
      `,"gitMs":` && |{ ls_overview-git_ms }| && `,"compareMs":` && |{ ls_overview-compare_ms }| && `}` &&
      `,"workbooks":[` && lv_json && `]}` ).
  ENDMETHOD.

  METHOD handle_commit.
    DATA lv_environment TYPE uj_appset_id.
    DATA ls_config TYPE zbpc_git_repo.
    DATA lo_remote TYPE REF TO zcl_bpc_git_remote.
    DATA lv_with_login TYPE abap_bool.
    DATA lt_paths TYPE string_table.
    DATA lv_error TYPE string.
    DATA lv_commit TYPE string.

    DATA(lv_message) = read_field( iv_name = 'message' iv_label = 'commit message'
                                   iv_max_length = c_max_message ).
    DATA(lv_expected) = read_field( iv_name = 'commit' iv_label = 'current commit'
                                    iv_max_length = 40 iv_required = abap_false ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    lt_paths = read_paths( ).
    IF lt_paths IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        create_remote( EXPORTING io_service = io_service
                       IMPORTING ev_environment = lv_environment es_config = ls_config
                                 eo_remote = lo_remote ev_with_login = lv_with_login ).
        IF lo_remote IS NOT BOUND.
          RETURN.
        ENDIF.
        io_service->commit_workbooks(
          EXPORTING iv_environment = lv_environment
                    io_remote = lo_remote
                    it_paths = lt_paths
                    iv_message = lv_message
                    iv_expected_commit = lv_expected
                    iv_git_user = mo_server->request->get_form_field( 'user' )
          IMPORTING ev_error = lv_error
                    ev_commit = lv_commit ).
      CATCH zcx_abapgit_exception INTO DATA(lx_git).
        respond_git_error( ix_error = lx_git iv_with_login = lv_with_login ).
        RETURN.
    ENDTRY.

    IF lv_error IS NOT INITIAL.
      respond_error( iv_code = 409 iv_reason = 'Conflict' iv_message = lv_error ).
      RETURN.
    ENDIF.
    respond( iv_code = 200 iv_reason = 'OK' iv_json =
      `{"commit":` && quote( lv_commit ) &&
      `,"count":` && |{ lines( lt_paths ) }| && `}` ).
  ENDMETHOD.

  METHOD handle_restore.
    DATA lv_environment TYPE uj_appset_id.
    DATA ls_config TYPE zbpc_git_repo.
    DATA lo_remote TYPE REF TO zcl_bpc_git_remote.
    DATA lv_with_login TYPE abap_bool.
    DATA lv_error TYPE string.
    DATA lt_results TYPE zcl_bpc_git_service=>ty_restore_results.

    DATA(lv_expected) = read_field( iv_name = 'commit' iv_label = 'current commit'
                                    iv_max_length = 40 iv_required = abap_false ).
    DATA(lv_version) = to_lower( read_field( iv_name = 'version' iv_label = 'history commit'
      iv_max_length = 40 iv_required = abap_false ) ).
    DATA(lv_depth) = read_history_depth( ).
    IF lv_version IS NOT INITIAL AND ( strlen( lv_version ) <> 40 OR lv_version CN '0123456789abcdef' ).
      mv_invalid = abap_true.
      respond_error( iv_code = 400 iv_reason = 'Bad Request' iv_message = 'Invalid history commit' ).
    ENDIF.
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    DATA(lt_paths) = read_paths( ).
    IF lt_paths IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        create_remote( EXPORTING io_service = io_service
                       IMPORTING ev_environment = lv_environment es_config = ls_config
                                 eo_remote = lo_remote ev_with_login = lv_with_login ).
        IF lo_remote IS NOT BOUND.
          RETURN.
        ENDIF.
        io_service->restore_files( EXPORTING iv_environment = lv_environment
                                             io_remote = lo_remote
                                             it_paths = lt_paths
                                             iv_expected_commit = lv_expected
                                             iv_version = lv_version
                                             iv_depth = lv_depth
                                   IMPORTING ev_error = lv_error
                                             et_results = lt_results ).
      CATCH zcx_abapgit_exception INTO DATA(lx_git).
        respond_git_error( ix_error = lx_git iv_with_login = lv_with_login ).
        RETURN.
    ENDTRY.

    IF lv_error IS NOT INITIAL.
      respond_error( iv_code = 409 iv_reason = 'Conflict' iv_message = lv_error ).
      RETURN.
    ENDIF.
    DATA lv_json TYPE string.
    DATA lv_separator TYPE string.
    LOOP AT lt_results INTO DATA(ls_result).
      lv_json = lv_json && lv_separator &&
        `{"path":` && quote( ls_result-path ) &&
        `,"ok":` && COND string( WHEN ls_result-ok = abap_true THEN `true` ELSE `false` ) &&
        `,"message":` && quote( ls_result-message ) && `}`.
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json = `{"results":[` && lv_json && `]}` ).
  ENDMETHOD.

  METHOD read_history_depth.
    rv_depth = 100.
    DATA(lv_depth) = read_field( iv_name = 'depth' iv_label = 'history range'
      iv_max_length = 4 iv_required = abap_false ).
    IF lv_depth IS INITIAL.
      RETURN.
    ENDIF.
    IF lv_depth CN '0123456789'.
      mv_invalid = abap_true.
    ELSE.
      rv_depth = CONV i( lv_depth ).
      IF rv_depth < 1 OR rv_depth > 1000.
        mv_invalid = abap_true.
      ENDIF.
    ENDIF.
    IF mv_invalid = abap_true.
      respond_error( iv_code = 400 iv_reason = 'Bad Request'
        iv_message = 'History range must be between 1 and 1000 commits' ).
    ENDIF.
  ENDMETHOD.

  METHOD handle_history.
    DATA lv_environment TYPE uj_appset_id.
    DATA ls_config TYPE zbpc_git_repo.
    DATA lo_remote TYPE REF TO zcl_bpc_git_remote.
    DATA lv_with_login TYPE abap_bool.
    DATA(lv_path) = read_field( iv_name = 'path' iv_label = 'file path' iv_max_length = 255 ).
    DATA(lv_depth) = read_history_depth( ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    TRY.
        create_remote( EXPORTING io_service = io_service
          IMPORTING ev_environment = lv_environment es_config = ls_config
                    eo_remote = lo_remote ev_with_login = lv_with_login ).
        IF lo_remote IS NOT BOUND.
          RETURN.
        ENDIF.
        DATA(ls_history) = io_service->get_history( iv_environment = lv_environment
          io_remote = lo_remote iv_path = lv_path iv_depth = lv_depth ).
      CATCH zcx_abapgit_exception INTO DATA(lx_git).
        respond_git_error( ix_error = lx_git iv_with_login = lv_with_login ).
        RETURN.
    ENDTRY.
    DATA lv_json TYPE string.
    DATA lv_separator TYPE string.
    LOOP AT ls_history-versions INTO DATA(ls_version).
      lv_json = lv_json && lv_separator && `{"commit":` && quote( ls_version-commit ) &&
        `,"author":` && quote( ls_version-author ) && `,"date":` && quote( ls_version-date ) &&
        `,"message":` && quote( ls_version-message ) &&
        `,"present":` && COND string( WHEN ls_version-present = abap_true THEN `true` ELSE `false` ) &&
        `,"complete":` && COND string( WHEN ls_version-complete = abap_true THEN `true` ELSE `false` ) && `}`.
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json = `{"head":` && quote( ls_history-head ) &&
      `,"truncated":` && COND string( WHEN ls_history-truncated = abap_true THEN `true` ELSE `false` ) &&
      `,"versions":[` && lv_json && `]}` ).
  ENDMETHOD.

  METHOD handle_diff.
    DATA lv_environment TYPE uj_appset_id.
    DATA ls_config TYPE zbpc_git_repo.
    DATA lo_remote TYPE REF TO zcl_bpc_git_remote.
    DATA lv_with_login TYPE abap_bool.
    DATA(lv_path) = read_field( iv_name = 'path' iv_label = 'file path' iv_max_length = 255 ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    TRY.
        create_remote( EXPORTING io_service = io_service
          IMPORTING ev_environment = lv_environment es_config = ls_config
                    eo_remote = lo_remote ev_with_login = lv_with_login ).
        IF lo_remote IS NOT BOUND.
          RETURN.
        ENDIF.
        DATA(ls_diff) = io_service->get_diff( iv_environment = lv_environment io_remote = lo_remote iv_path = lv_path ).
      CATCH zcx_abapgit_exception INTO DATA(lx_git).
        respond_git_error( ix_error = lx_git iv_with_login = lv_with_login ).
        RETURN.
    ENDTRY.
    DATA lv_json TYPE string.
    DATA lv_separator TYPE string.
    LOOP AT ls_diff-parts INTO DATA(ls_part).
      lv_json = lv_json && lv_separator && `{"path":` && quote( ls_part-path ) &&
        `,"inBpc":` && COND string( WHEN ls_part-in_bpc = abap_true THEN `true` ELSE `false` ) &&
        `,"inGit":` && COND string( WHEN ls_part-in_git = abap_true THEN `true` ELSE `false` ) &&
        `,"changed":` && COND string( WHEN ls_part-changed = abap_true THEN `true` ELSE `false` ) &&
        `,"textAvailable":` && COND string( WHEN ls_part-text_available = abap_true THEN `true` ELSE `false` ) &&
        `,"message":` && quote( ls_part-message ) &&
        `,"bpcText":` && quote( ls_part-bpc_text ) && `,"gitText":` && quote( ls_part-git_text ) &&
        `,"bpcSize":` && CONV string( ls_part-bpc_size ) && `,"gitSize":` && CONV string( ls_part-git_size ) && `}`.
      lv_separator = ','.
    ENDLOOP.
    respond( iv_code = 200 iv_reason = 'OK' iv_json = `{"head":` && quote( ls_diff-head ) &&
      `,"parts":[` && lv_json && `]}` ).
  ENDMETHOD.

  METHOD read_paths.
    DATA(lv_paths) = mo_server->request->get_form_field( 'paths' ).
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_paths WITH cl_abap_char_utilities=>newline.
    SPLIT lv_paths AT cl_abap_char_utilities=>newline INTO TABLE rt_paths.
    DELETE rt_paths WHERE table_line IS INITIAL.
    IF rt_paths IS INITIAL OR lines( rt_paths ) > c_max_paths.
      CLEAR rt_paths.
      respond_error( iv_code = 400 iv_reason = 'Bad Request'
                     iv_message = |Select between 1 and { c_max_paths } files| ).
    ENDIF.
  ENDMETHOD.

  METHOD create_remote.
    CLEAR: ev_environment, es_config, eo_remote, ev_with_login.
    DESCRIBE FIELD ev_environment LENGTH DATA(lv_length) IN CHARACTER MODE.
    DATA(lv_environment) = read_field( iv_name = 'environment' iv_label = 'environment'
                                       iv_max_length = lv_length ).
    DATA(lv_user) = read_field( iv_name = 'user' iv_label = 'Git user'
                                iv_max_length = c_max_user iv_required = abap_false ).
    DATA(lv_token) = read_field( iv_name = 'token' iv_label = 'access token'
                                 iv_max_length = c_max_token iv_required = abap_false ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    ev_environment = lv_environment.
    es_config = io_service->get_config( ev_environment ).
    IF es_config IS INITIAL.
      respond_error( iv_code = 400 iv_reason = 'Bad Request'
                     iv_message = 'Save the repository setup first' ).
      RETURN.
    ENDIF.
    ev_with_login = xsdbool( lv_user IS NOT INITIAL AND lv_token IS NOT INITIAL ).
    eo_remote = NEW zcl_bpc_git_remote( iv_url = es_config-url iv_user = lv_user iv_token = lv_token
      iv_root_folder = CONV string( es_config-root_folder ) iv_lfs_enabled = es_config-lfs_enabled iv_lfs_mb = COND #( WHEN es_config-lfs_mb > 0 THEN es_config-lfs_mb ELSE 5 ) ).
  ENDMETHOD.

  METHOD respond_git_error.
    IF zcl_bpc_git_remote=>is_auth_error( ix_error ) = abap_true.
      respond_error( iv_code = 403 iv_reason = 'Forbidden' iv_auth_required = abap_true
                     iv_message = COND #( WHEN iv_with_login = abap_true
                                          THEN 'The Git host rejected the user or access token'
                                          ELSE 'The Git host needs a login for this repository' ) ).
    ELSE.
      respond_error( iv_code = 502 iv_reason = 'Bad Gateway'
                     iv_message = |Git host: { ix_error->get_text( ) }| ).
    ENDIF.
  ENDMETHOD.

  METHOD config_json.
    DATA lv_changed_at TYPE string.
    IF is_config-changed_at IS NOT INITIAL.
      lv_changed_at = |{ is_config-changed_at TIMESTAMP = USER TIMEZONE = sy-zonlo }|.
    ENDIF.
    rv_json = `{"environment":` && quote( iv_environment ) &&
      `,"configured":` && COND string( WHEN is_config IS INITIAL THEN `false` ELSE `true` ) &&
      `,"url":` && quote( is_config-url ) &&
      `,"branch":` && quote( is_config-branch ) &&
      `,"rootFolder":` && quote( is_config-root_folder ) &&
      `,"lfsEnabled":` && COND string( WHEN is_config-lfs_enabled = abap_true THEN `true` ELSE `false` ) &&
      `,"lfsThresholdMb":` && CONV string( COND i( WHEN is_config-lfs_mb > 0 THEN is_config-lfs_mb ELSE 5 ) ) &&
      `,"changedBy":` && quote( is_config-changed_by ) &&
      `,"changedAt":` && quote( lv_changed_at ) && `}`.
  ENDMETHOD.

  METHOD has_form_field.
    LOOP AT it_fields INTO DATA(ls_field).
      IF to_lower( ls_field-name ) = to_lower( iv_name ).
        rv_present = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_field.
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    rv_value = condense( mo_server->request->get_form_field( iv_name ) ).
    IF rv_value IS INITIAL AND iv_required = abap_true.
      mv_invalid = abap_true.
      respond_error( iv_code = 400 iv_reason = 'Bad Request'
                     iv_message = |The { iv_label } is required| ).
    ELSEIF strlen( rv_value ) > iv_max_length.
      mv_invalid = abap_true.
      respond_error( iv_code = 400 iv_reason = 'Bad Request'
                     iv_message = |The { iv_label } is longer than { iv_max_length } characters| ).
    ENDIF.
  ENDMETHOD.

  METHOD require_method.
    IF mo_server->request->get_method( ) <> iv_method.
      respond_error( iv_code = 405 iv_reason = 'Method Not Allowed'
                     iv_message = |Only { iv_method } is supported| iv_allow = iv_method ).
      RETURN.
    ENDIF.
    IF iv_method = c_method-post
        AND mo_server->request->get_header_field( 'x-requested-with' ) <> 'XMLHttpRequest'.
      respond_error( iv_code = 403 iv_reason = 'Forbidden'
                     iv_message = 'Requests that change data must come from the bpcGit app' ).
      RETURN.
    ENDIF.
    rv_allowed = abap_true.
  ENDMETHOD.

  METHOD respond.
    IF iv_allow IS NOT INITIAL.
      mo_server->response->set_header_field( name = 'Allow' value = iv_allow ).
    ENDIF.
    mo_server->response->set_status( code = iv_code reason = iv_reason ).
    mo_server->response->set_cdata( iv_json ).
  ENDMETHOD.

  METHOD respond_error.
    respond( iv_code = iv_code iv_reason = iv_reason iv_allow = iv_allow
             iv_json = `{"error":{"message":` && quote( iv_message ) &&
                       COND string( WHEN iv_auth_required = abap_true THEN `,"authRequired":true` ) &&
                       `}}` ).
  ENDMETHOD.

  METHOD quote.
    DATA(lv_value) = |{ iv_value }|.
    rv_json = `"` && escape( val = lv_value format = cl_abap_format=>e_json_string ) && `"`.
  ENDMETHOD.
ENDCLASS.
