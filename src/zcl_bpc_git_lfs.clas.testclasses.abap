CLASS ltcl_lfs DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PUBLIC SECTION.
    CLASS-DATA calls TYPE string_table.
    CLASS-DATA mode TYPE string.
    CLASS-METHODS reply IMPORTING action TYPE zcl_bpc_git_lfs=>ty_action method TYPE string data TYPE xstring
      RETURNING VALUE(result) TYPE xstring RAISING zcx_abapgit_exception.
  PRIVATE SECTION.
    METHODS setup.
    METHODS pointer_roundtrip FOR TESTING RAISING zcx_abapgit_exception.
    METHODS malformed_pointer FOR TESTING.
    METHODS workbook_scope FOR TESTING.
    METHODS upload_and_verify FOR TESTING RAISING zcx_abapgit_exception.
    METHODS already_uploaded FOR TESTING RAISING zcx_abapgit_exception.
    METHODS download_integrity FOR TESTING RAISING zcx_abapgit_exception.
    METHODS action_headers FOR TESTING RAISING zcx_abapgit_exception.
    METHODS quoted_attributes FOR TESTING RAISING zcx_abapgit_exception.
ENDCLASS.

CLASS ltcl_lfs IMPLEMENTATION.
  METHOD setup.
    CLEAR: calls, mode.
    TEST-INJECTION lfs_http.
      rv_data = ltcl_lfs=>reply( action = is_action method = iv_method data = iv_data ).
    END-TEST-INJECTION.
  ENDMETHOD.

  METHOD reply.
    APPEND method && ':' && action-href TO calls.
    DATA(payload) = cl_abap_codepage=>convert_to( 'abc' ).
    IF action-href CS '/objects/batch'.
      DATA(hash) = zcl_bpc_git_lfs=>sha256( payload ).
      DATA(json) = |\{"transfer":"basic","objects":[\{"oid":"{ hash }","size":3|.
      IF mode <> 'existing'.
        json = json && `,"actions":{"upload":{"href":"https://storage.example.invalid/upload",` &&
          `"header":{"Authorization":"Bearer action-token","X-Object-Meta":"abc"}},` &&
          `"verify":{"href":"https://storage.example.invalid/verify"},` &&
          `"download":{"href":"https://storage.example.invalid/download"}}`.
      ENDIF.
      result = cl_abap_codepage=>convert_to( json && `}]}` ).
    ELSEIF method = 'PUT'.
      cl_abap_unit_assert=>assert_equals( act = data exp = payload ).
      cl_abap_unit_assert=>assert_equals( act = action-header[ name = 'Authorization' ]-value exp = 'Bearer action-token' ).
      cl_abap_unit_assert=>assert_equals( act = action-header[ name = 'X-Object-Meta' ]-value exp = 'abc' ).
    ELSEIF method = 'GET'.
      result = COND #( WHEN mode = 'bad' THEN cl_abap_codepage=>convert_to( 'abd' ) ELSE payload ).
    ELSE.
      cl_abap_unit_assert=>assert_true( xsdbool( action-href CS '/verify' ) ).
      cl_abap_unit_assert=>assert_true( xsdbool( cl_abap_codepage=>convert_from( data ) CS '"size":3' ) ).
    ENDIF.
  ENDMETHOD.

  METHOD pointer_roundtrip.
    DATA(data) = cl_abap_codepage=>convert_to( 'abc' ).
    DATA(pointer) = zcl_bpc_git_lfs=>pointer( data ).
    DATA(parsed) = zcl_bpc_git_lfs=>parse( pointer ).
    cl_abap_unit_assert=>assert_equals( act = parsed-oid
      exp = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' ).
    cl_abap_unit_assert=>assert_equals( act = parsed-size exp = 3 ).
    cl_abap_unit_assert=>assert_initial( zcl_bpc_git_lfs=>parse( data ) ).
    cl_abap_unit_assert=>assert_initial( zcl_bpc_git_lfs=>parse( CONV xstring( '504B0304' ) ) ).
  ENDMETHOD.

  METHOD malformed_pointer.
    TRY.
        zcl_bpc_git_lfs=>parse( cl_abap_codepage=>convert_to(
          'version https://git-lfs.github.com/spec/v1' && cl_abap_char_utilities=>newline && 'oid sha256:bad' ) ).
        cl_abap_unit_assert=>fail( 'Malformed pointer must not be restored as workbook bytes' ).
      CATCH zcx_abapgit_exception.
    ENDTRY.
  ENDMETHOD.

  METHOD workbook_scope.
    cl_abap_unit_assert=>assert_true( zcl_bpc_git_lfs=>eligible( 'M/TEAM FILES/T/EEXCEL/REPORTS/X.XLSM' ) ).
    cl_abap_unit_assert=>assert_true( zcl_bpc_git_lfs=>eligible( 'M/EEXCEL/INPUT SCHEDULES/x.xlsx' ) ).
    cl_abap_unit_assert=>assert_false( zcl_bpc_git_lfs=>eligible( 'M/DATAMANAGER/TRANSFORMATIONFILES/X.XLS' ) ).
    cl_abap_unit_assert=>assert_false( zcl_bpc_git_lfs=>eligible( 'M/EEXCEL/REPORTS/X.xml' ) ).
  ENDMETHOD.

  METHOD upload_and_verify.
    DATA(lfs) = NEW zcl_bpc_git_lfs( iv_url = 'https://bitbucket.org/test/repo.git' iv_user = 'x-token-auth' iv_token = 'fake' ).
    DATA(pointer) = lfs->upload( cl_abap_codepage=>convert_to( 'abc' ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( calls ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = calls[ 2 ] exp = 'PUT:https://storage.example.invalid/upload' ).
    cl_abap_unit_assert=>assert_equals( act = calls[ 3 ] exp = 'POST:https://storage.example.invalid/verify' ).
    DATA(parsed) = zcl_bpc_git_lfs=>parse( pointer ).
    cl_abap_unit_assert=>assert_equals( act = parsed-size exp = 3 ).
  ENDMETHOD.

  METHOD already_uploaded.
    mode = 'existing'.
    DATA(lfs) = NEW zcl_bpc_git_lfs( iv_url = 'https://bitbucket.org/test/repo' iv_user = '' iv_token = '' ).
    lfs->upload( cl_abap_codepage=>convert_to( 'abc' ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( calls ) exp = 1 ).
  ENDMETHOD.

  METHOD download_integrity.
    DATA(lfs) = NEW zcl_bpc_git_lfs( iv_url = 'https://bitbucket.org/test/repo' iv_user = '' iv_token = '' ).
    DATA(pointer) = zcl_bpc_git_lfs=>parse( zcl_bpc_git_lfs=>pointer( cl_abap_codepage=>convert_to( 'abc' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lfs->download( pointer ) exp = cl_abap_codepage=>convert_to( 'abc' ) ).
    mode = 'bad'.
    TRY.
        lfs->download( pointer ).
        cl_abap_unit_assert=>fail( 'Same-size corrupt content must be rejected' ).
      CATCH zcx_abapgit_exception.
    ENDTRY.
  ENDMETHOD.

  METHOD action_headers.
    DATA object TYPE zcl_bpc_git_lfs=>ty_object.
    /ui2/cl_json=>deserialize( EXPORTING json =
      `{"actions":{"upload":{"href":"https://example.invalid","header":{"Authorization":"Bearer test","X-Name":"value"}}}}`
      assoc_arrays = abap_true assoc_arrays_opt = abap_true CHANGING data = object ).
    cl_abap_unit_assert=>assert_equals( act = object-actions-upload-header[ name = 'Authorization' ]-value exp = 'Bearer test' ).
    cl_abap_unit_assert=>assert_equals( act = object-actions-upload-header[ name = 'X-Name' ]-value exp = 'value' ).
  ENDMETHOD.

  METHOD quoted_attributes.
    DATA(text) = zcl_bpc_git_lfs=>attributes( iv_attributes = '*.txt text'
      iv_path = 'M/EEXCEL/INPUT SCHEDULES/[Plan].XLSX' ).
    cl_abap_unit_assert=>assert_true( xsdbool( text CS '*.txt text' ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( text CS '"/M/EEXCEL/INPUT SCHEDULES/\\[Plan\\].XLSX" filter=lfs diff=lfs merge=lfs -text' ) ).
  ENDMETHOD.
ENDCLASS.
