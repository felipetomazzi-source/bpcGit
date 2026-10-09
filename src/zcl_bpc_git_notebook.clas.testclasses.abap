CLASS ltcl_notebook_provider DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PUBLIC SECTION.
    CLASS-DATA mode TYPE string.
    CLASS-METHODS reply IMPORTING operation TYPE string request TYPE string RETURNING VALUE(json) TYPE string.
  PRIVATE SECTION.
    METHODS paths FOR TESTING.
    METHODS exact_sources FOR TESTING RAISING zcx_abapgit_exception.
    METHODS refuses_invalid_import FOR TESTING.
ENDCLASS.
CLASS ltcl_notebook_provider IMPLEMENTATION.
  METHOD reply.
    TYPES: BEGIN OF ty_request, contract_version TYPE i, expected_revision TYPE i, END OF ty_request.
    DATA parsed TYPE ty_request.
    /ui2/cl_json=>deserialize( EXPORTING json = request pretty_name = /ui2/cl_json=>pretty_mode-camel_case CHANGING data = parsed ).
    cl_abap_unit_assert=>assert_equals( act = parsed-contract_version exp = 1 ).
    IF operation = 'CAPABILITIES'.
      json = '{"contractVersion":1,"callerTransaction":true}'.
    ELSEIF operation = 'LIST'.
      DATA(source) = CONV xstring( 'EFBBBF4441544120782E20200D0A0D0A' ).
      json = '{"contractVersion":1,"bundles":[{"key":"revenue","title":"Revenue","model":"PLAN","revision":5,"files":[' &&
        '{"path":"NOTEBOOKS/revenue/notebook.json","contentBase64":"e30="},' &&
        '{"path":"NOTEBOOKS/revenue/cells/calculate.abap","contentBase64":"' &&
        cl_http_utility=>encode_x_base64( source ) && '"}]}]}'.
    ELSEIF operation = 'PREVIEW' OR operation = 'IMPORT'.
      cl_abap_unit_assert=>assert_equals( act = parsed-expected_revision exp = 5 ).
      json = '{"contractVersion":1,"canImport":false,"validationError":"Script import is unsupported","revision":0}'.
    ELSE.
      cl_abap_unit_assert=>fail( 'Unexpected provider operation' ).
    ENDIF.
  ENDMETHOD.
  METHOD paths.
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_notebook=>get_kind(
      'NOTEBOOKS/revenue/cells/calculate.bns' ) exp = 'NOTEBOOK' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_notebook=>logical_path(
      'NOTEBOOKS/revenue/cells/calculate.generated.abap' ) exp = 'NOTEBOOKS/revenue/notebook.json' ).
    cl_abap_unit_assert=>assert_initial( zcl_bpc_git_notebook=>get_kind( 'NOTEBOOKS/../notebook.json' ) ).
    cl_abap_unit_assert=>assert_initial( zcl_bpc_git_notebook=>get_kind( 'NOTEBOOKS/revenue/cells/../secret.abap' ) ).
    cl_abap_unit_assert=>assert_initial( zcl_bpc_git_notebook=>get_kind( 'NOTEBOOKS/revenue/output.json' ) ).
    cl_abap_unit_assert=>assert_initial( zcl_bpc_git_notebook=>get_kind( 'NOTEBOOKS/revenue/cells/run.xml' ) ).
  ENDMETHOD.
  METHOD exact_sources.
    TEST-INJECTION notebook_dispatch.
      rv_json = ltcl_notebook_provider=>reply( operation = iv_operation request = iv_request ).
    END-TEST-INJECTION.
    cl_abap_unit_assert=>assert_true( zcl_bpc_git_notebook=>can_read( 'TEST' ) ).
    DATA(files) = zcl_bpc_git_notebook=>list( 'TEST' ).
    cl_abap_unit_assert=>assert_equals( act = files[ path = 'NOTEBOOKS/revenue/cells/calculate.abap' ]-content
      exp = CONV xstring( 'EFBBBF4441544120782E20200D0A0D0A' ) ).
    cl_abap_unit_assert=>assert_equals( act = files[ 1 ]-revision exp = 5 ).
  ENDMETHOD.
  METHOD refuses_invalid_import.
    TEST-INJECTION notebook_dispatch.
      rv_json = ltcl_notebook_provider=>reply( operation = iv_operation request = iv_request ).
    END-TEST-INJECTION.
    DATA(error) = zcl_bpc_git_notebook=>apply( iv_environment = 'TEST'
      iv_path = 'NOTEBOOKS/revenue/notebook.json' iv_expected_revision = 5 iv_source_commit = 'a'
      it_files = VALUE #( ( path = 'NOTEBOOKS/revenue/notebook.json' content_base64 = 'e30=' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = error exp = 'Script import is unsupported' ).
    error = zcl_bpc_git_notebook=>apply( iv_environment = 'TEST'
      iv_path = 'NOTEBOOKS/revenue/notebook.json' iv_expected_revision = 5 iv_source_commit = 'a'
      it_files = VALUE #( ) ).
    cl_abap_unit_assert=>assert_not_initial( error ).
  ENDMETHOD.
ENDCLASS.
