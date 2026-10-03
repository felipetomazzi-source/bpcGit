CLASS zcl_bpc_git_http DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_http_extension.
  PRIVATE SECTION.
    "! Request and response of the current call.
    DATA mo_server TYPE REF TO if_http_server.
    " Resources served by this handler.
    CONSTANTS:
      BEGIN OF c_resource,
        ping TYPE string VALUE '/ping',
      END OF c_resource.
    CONSTANTS:
      BEGIN OF c_method,
        get  TYPE string VALUE 'GET',
        post TYPE string VALUE 'POST',
      END OF c_method.

    "! Sends 405 unless the request uses the expected method.
    METHODS require_method
      IMPORTING iv_method TYPE string
      RETURNING VALUE(rv_allowed) TYPE abap_bool.
    "! Reports the caller, the system and the abapGit installation.
    METHODS handle_ping.
    METHODS respond
      IMPORTING iv_code TYPE i iv_reason TYPE string iv_json TYPE string
                iv_allow TYPE string OPTIONAL.
    METHODS respond_error
      IMPORTING iv_code TYPE i iv_reason TYPE string iv_message TYPE string
                iv_allow TYPE string OPTIONAL.
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
        CASE lv_path.
          WHEN c_resource-ping.
            IF require_method( c_method-get ).
              handle_ping( ).
            ENDIF.
          WHEN OTHERS.
            respond_error( iv_code = 404 iv_reason = 'Not Found'
                           iv_message = 'Unknown resource' ).
        ENDCASE.
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

  METHOD require_method.
    IF mo_server->request->get_method( ) = iv_method.
      rv_allowed = abap_true.
      RETURN.
    ENDIF.
    respond_error( iv_code = 405 iv_reason = 'Method Not Allowed'
                   iv_message = |Only { iv_method } is supported| iv_allow = iv_method ).
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
             iv_json = `{"error":{"message":` && quote( iv_message ) && `}}` ).
  ENDMETHOD.

  METHOD quote.
    DATA(lv_value) = |{ iv_value }|.
    rv_json = `"` && escape( val = lv_value format = cl_abap_format=>e_json_string ) && `"`.
  ENDMETHOD.
ENDCLASS.
