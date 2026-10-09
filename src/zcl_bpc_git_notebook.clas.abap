"! Optional Notebook provider; no static dependency on ZBPC_NOTEBOOK.
CLASS zcl_bpc_git_notebook DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_file,
             path TYPE string,
             content TYPE xstring,
             model TYPE string,
             title TYPE string,
             revision TYPE i,
           END OF ty_file,
           ty_files TYPE STANDARD TABLE OF ty_file WITH DEFAULT KEY,
           BEGIN OF ty_wire_file,
             path TYPE string,
             content_base64 TYPE string,
           END OF ty_wire_file,
           ty_wire_files TYPE STANDARD TABLE OF ty_wire_file WITH DEFAULT KEY,
           BEGIN OF ty_bundle,
             key TYPE string,
             title TYPE string,
             model TYPE string,
             revision TYPE i,
             files TYPE ty_wire_files,
           END OF ty_bundle,
           ty_bundles TYPE STANDARD TABLE OF ty_bundle WITH DEFAULT KEY.
    CLASS-METHODS get_kind IMPORTING iv_path TYPE string RETURNING VALUE(rv_kind) TYPE string.
    CLASS-METHODS logical_path IMPORTING iv_path TYPE string RETURNING VALUE(rv_path) TYPE string.
    CLASS-METHODS key IMPORTING iv_path TYPE string RETURNING VALUE(rv_key) TYPE string.
    CLASS-METHODS prefix IMPORTING iv_path TYPE string RETURNING VALUE(rv_prefix) TYPE string.
    CLASS-METHODS can_read IMPORTING iv_environment TYPE uj_appset_id
      RETURNING VALUE(rv_allowed) TYPE abap_bool.
    CLASS-METHODS list IMPORTING iv_environment TYPE uj_appset_id iv_model TYPE string OPTIONAL
      RETURNING VALUE(rt_files) TYPE ty_files RAISING zcx_abapgit_exception.
    CLASS-METHODS apply IMPORTING iv_environment TYPE uj_appset_id iv_path TYPE string
      iv_expected_revision TYPE i iv_source_commit TYPE string it_files TYPE ty_wire_files
      iv_preview TYPE abap_bool DEFAULT abap_false
      EXPORTING ev_revision TYPE i RETURNING VALUE(rv_error) TYPE string.
  PRIVATE SECTION.
    CLASS-METHODS call IMPORTING iv_operation TYPE string iv_request TYPE string
      RETURNING VALUE(rv_json) TYPE string RAISING zcx_abapgit_exception.
ENDCLASS.
CLASS zcl_bpc_git_notebook IMPLEMENTATION.
  METHOD key.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    IF lines( lt_parts ) < 3 OR lt_parts[ 1 ] <> 'NOTEBOOKS'.
      RETURN.
    ENDIF.
    DATA(lv_key) = lt_parts[ 2 ].
    FIND REGEX '^[A-Za-z0-9_-]{1,64}$' IN lv_key.
    IF sy-subrc = 0.
      rv_key = lv_key.
    ENDIF.
  ENDMETHOD.
  METHOD get_kind.
    DATA(lv_key) = key( iv_path ).
    IF lv_key IS INITIAL.
      RETURN.
    ENDIF.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    IF lines( lt_parts ) = 3 AND lt_parts[ 3 ] = 'notebook.json'.
      rv_kind = 'NOTEBOOK'.
    ELSEIF lines( lt_parts ) = 4 AND lt_parts[ 3 ] = 'cells'.
      FIND REGEX '^[A-Za-z][A-Za-z0-9_-]{0,29}\.(abap|bns|generated\.abap)$' IN lt_parts[ 4 ].
      IF sy-subrc = 0.
        rv_kind = 'NOTEBOOK'.
      ENDIF.
    ENDIF.
  ENDMETHOD.
  METHOD logical_path.
    IF get_kind( iv_path ) IS NOT INITIAL.
      rv_path = |NOTEBOOKS/{ key( iv_path ) }/notebook.json|.
    ENDIF.
  ENDMETHOD.
  METHOD prefix.
    IF get_kind( iv_path ) IS NOT INITIAL.
      rv_prefix = |NOTEBOOKS/{ key( iv_path ) }/|.
    ENDIF.
  ENDMETHOD.
  METHOD call.
    TRY.
        TEST-SEAM notebook_dispatch.
          CALL METHOD ('ZCL_BN_GIT')=>('DISPATCH')
            EXPORTING operation = iv_operation request = iv_request RECEIVING json = rv_json.
        END-TEST-SEAM.
      CATCH cx_root INTO DATA(lx_provider).
        zcx_abapgit_exception=>raise( |Notebook provider: { lx_provider->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.
  METHOD can_read.
    TYPES: BEGIN OF ty_capabilities, contract_version TYPE i, caller_transaction TYPE abap_bool, END OF ty_capabilities.
    DATA ls_capabilities TYPE ty_capabilities.
    TYPES: BEGIN OF ty_request, contract_version TYPE i, environment TYPE string, END OF ty_request.
    DATA(ls_request) = VALUE ty_request( contract_version = 1 environment = iv_environment ).
    TRY.
        DATA(lv_json) = call( iv_operation = 'CAPABILITIES'
          iv_request = /ui2/cl_json=>serialize( data = ls_request pretty_name = /ui2/cl_json=>pretty_mode-camel_case ) ).
        /ui2/cl_json=>deserialize( EXPORTING json = lv_json pretty_name = /ui2/cl_json=>pretty_mode-camel_case CHANGING data = ls_capabilities ).
        rv_allowed = xsdbool( ls_capabilities-contract_version = 1 AND ls_capabilities-caller_transaction = abap_true ).
      CATCH cx_root.
        rv_allowed = abap_false.
    ENDTRY.
  ENDMETHOD.
  METHOD list.
    TYPES: BEGIN OF ty_request, contract_version TYPE i, environment TYPE string, model TYPE string, END OF ty_request,
           BEGIN OF ty_response, contract_version TYPE i, bundles TYPE ty_bundles, END OF ty_response.
    DATA(ls_request) = VALUE ty_request( contract_version = 1 environment = iv_environment model = iv_model ).
    DATA ls_response TYPE ty_response.
    DATA(lv_json) = call( iv_operation = 'LIST'
      iv_request = /ui2/cl_json=>serialize( data = ls_request pretty_name = /ui2/cl_json=>pretty_mode-camel_case ) ).
    /ui2/cl_json=>deserialize( EXPORTING json = lv_json pretty_name = /ui2/cl_json=>pretty_mode-camel_case CHANGING data = ls_response ).
    IF ls_response-contract_version <> 1.
      zcx_abapgit_exception=>raise( 'Notebook Git provider contract version 1 is required' ).
    ENDIF.
    LOOP AT ls_response-bundles INTO DATA(ls_bundle).
      IF ls_bundle-revision < 1 OR lines( ls_bundle-files ) > 61
          OR NOT line_exists( ls_bundle-files[ path = |NOTEBOOKS/{ ls_bundle-key }/notebook.json| ] ).
        zcx_abapgit_exception=>raise( 'Notebook provider returned an invalid saved bundle' ).
      ENDIF.
      LOOP AT ls_bundle-files INTO DATA(ls_wire).
        IF get_kind( ls_wire-path ) IS INITIAL OR key( ls_wire-path ) <> ls_bundle-key
            OR line_exists( rt_files[ path = ls_wire-path ] ).
          zcx_abapgit_exception=>raise( 'Notebook provider returned an invalid or duplicate source path' ).
        ENDIF.
        DATA(lv_content) = cl_http_utility=>decode_x_base64( ls_wire-content_base64 ).
        IF xstrlen( lv_content ) > 1048576.
          zcx_abapgit_exception=>raise( 'Notebook source file exceeds 1 MB' ).
        ENDIF.
        APPEND VALUE #( path = ls_wire-path content = lv_content model = ls_bundle-model
          title = ls_bundle-title revision = ls_bundle-revision ) TO rt_files.
      ENDLOOP.
    ENDLOOP.
    SORT rt_files BY path.
  ENDMETHOD.
  METHOD apply.
    TYPES: BEGIN OF ty_request,
             contract_version TYPE i, environment TYPE string, key TYPE string, expected_revision TYPE i,
             source_commit TYPE string, files TYPE ty_wire_files,
           END OF ty_request,
           BEGIN OF ty_response,
             contract_version TYPE i, can_import TYPE abap_bool,
             validation_error TYPE string, revision TYPE i,
           END OF ty_response.
    DATA ls_response TYPE ty_response.
    CLEAR ev_revision.
    IF logical_path( iv_path ) <> iv_path OR it_files IS INITIAL
        OR NOT line_exists( it_files[ path = iv_path ] ).
      rv_error = 'A complete Notebook definition is required; whole-notebook deletion is not supported'.
      RETURN.
    ENDIF.
    DATA(ls_request) = VALUE ty_request( contract_version = 1 environment = iv_environment key = key( iv_path )
      expected_revision = iv_expected_revision source_commit = iv_source_commit files = it_files ).
    TRY.
        DATA(lv_json) = call( iv_operation = COND #( WHEN iv_preview = abap_true THEN 'PREVIEW' ELSE 'IMPORT' )
          iv_request = /ui2/cl_json=>serialize( data = ls_request pretty_name = /ui2/cl_json=>pretty_mode-camel_case ) ).
        /ui2/cl_json=>deserialize( EXPORTING json = lv_json pretty_name = /ui2/cl_json=>pretty_mode-camel_case CHANGING data = ls_response ).
        IF ls_response-contract_version <> 1 OR ls_response-can_import = abap_false
            OR ( iv_preview = abap_false AND ls_response-revision <= iv_expected_revision ).
          rv_error = COND #( WHEN ls_response-validation_error IS NOT INITIAL THEN ls_response-validation_error
            ELSE 'Notebook provider did not confirm a valid import' ).
          RETURN.
        ENDIF.
        ev_revision = ls_response-revision.
      CATCH cx_root INTO DATA(lx_provider).
        rv_error = lx_provider->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
