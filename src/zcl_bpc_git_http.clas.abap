CLASS zcl_bpc_git_http DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_http_extension.
  PRIVATE SECTION.
    "! Request and response of the current call.
    DATA mo_server TYPE REF TO if_http_server.
    "! Set once read_field has answered with 400; later reads are skipped.
    DATA mv_invalid TYPE abap_bool.
    " Resources served by this handler.
    CONSTANTS:
      BEGIN OF c_resource,
        ping         TYPE string VALUE '/ping',
        environments TYPE string VALUE '/environments',
        config       TYPE string VALUE '/config',
        connection   TYPE string VALUE '/connection',
      END OF c_resource.
    "! Longest Git user name and access token accepted.
    CONSTANTS c_max_user TYPE i VALUE 255 ##NO_TEXT.
    CONSTANTS c_max_token TYPE i VALUE 1024 ##NO_TEXT.
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
    DATA lv_environment_id TYPE uj_appset_id.
    DESCRIBE FIELD lv_environment_id LENGTH DATA(lv_length) IN CHARACTER MODE.
    DATA(lv_environment) = read_field( iv_name = 'environment' iv_label = 'environment'
                                       iv_max_length = lv_length ).
    DATA(lv_user) = read_field( iv_name = 'user' iv_label = 'Git user'
                                iv_max_length = c_max_user iv_required = abap_false ).
    DATA(lv_token) = read_field( iv_name = 'token' iv_label = 'access token'
                                 iv_max_length = c_max_token iv_required = abap_false ).
    IF mv_invalid = abap_true.
      RETURN.
    ENDIF.
    lv_environment_id = lv_environment.
    DATA(ls_config) = io_service->get_config( lv_environment_id ).
    IF ls_config IS INITIAL.
      respond_error( iv_code = 400 iv_reason = 'Bad Request'
                     iv_message = 'Save the repository setup first' ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_remote) = NEW zcl_bpc_git_remote( iv_url = ls_config-url
                                                  iv_user = lv_user
                                                  iv_token = lv_token ).
        DATA(ls_result) = lo_remote->test_connection( ls_config-branch ).
      CATCH zcx_abapgit_exception INTO DATA(lx_git).
        IF zcl_bpc_git_remote=>is_auth_error( lx_git ) = abap_true.
          respond_error( iv_code = 403 iv_reason = 'Forbidden' iv_auth_required = abap_true
                         iv_message = COND #( WHEN lv_token IS INITIAL
                                              THEN 'The Git host needs a login for this repository'
                                              ELSE 'The Git host rejected the user or access token' ) ).
        ELSE.
          respond_error( iv_code = 502 iv_reason = 'Bad Gateway'
                         iv_message = |Git host: { lx_git->get_text( ) }| ).
        ENDIF.
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

  METHOD config_json.
    DATA lv_changed_at TYPE string.
    IF is_config-changed_at IS NOT INITIAL.
      lv_changed_at = |{ is_config-changed_at TIMESTAMP = USER TIMEZONE = sy-zonlo }|.
    ENDIF.
    rv_json = `{"environment":` && quote( iv_environment ) &&
      `,"configured":` && COND string( WHEN is_config IS INITIAL THEN `false` ELSE `true` ) &&
      `,"url":` && quote( is_config-url ) &&
      `,"branch":` && quote( is_config-branch ) &&
      `,"changedBy":` && quote( is_config-changed_by ) &&
      `,"changedAt":` && quote( lv_changed_at ) && `}`.
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
