CLASS ltcl_bitbucket_history DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PUBLIC SECTION.
    CLASS-DATA missing_all TYPE abap_bool.
    CLASS-DATA diff_calls TYPE i.
    CLASS-DATA paginate TYPE abap_bool.
    CLASS-METHODS reply IMPORTING suffix TYPE string RETURNING VALUE(json) TYPE string.
  PRIVATE SECTION.
    METHODS setup.
    METHODS paired_history FOR TESTING RAISING zcx_abapgit_exception.
    METHODS deleted_pair FOR TESTING RAISING zcx_abapgit_exception.
    METHODS depth_boundary FOR TESTING RAISING zcx_abapgit_exception.
    METHODS incomplete_page FOR TESTING RAISING zcx_abapgit_exception.
    METHODS read IMPORTING depth TYPE i RETURNING VALUE(result) TYPE zcl_bpc_git_remote=>ty_history
      RAISING zcx_abapgit_exception.
ENDCLASS.

CLASS ltcl_bitbucket_history IMPLEMENTATION.
  METHOD setup.
    CLEAR: missing_all, diff_calls, paginate.
    TEST-INJECTION bitbucket_http.
      rv_json = ltcl_bitbucket_history=>reply( iv_suffix ).
    END-TEST-INJECTION.
  ENDMETHOD.

  METHOD reply.
    DATA(path) = COND string( WHEN suffix CS 'IMPORT.TDM' THEN 'M/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.TDM'
      ELSE 'M/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.XLS' ).
    IF suffix CP '/src/*'.
      IF missing_all = abap_false AND suffix NS 'IMPORT.TDM'.
        json = `{"type":"commit_file","path":"` && path && `"}`.
      ENDIF.
    ELSEIF suffix CP '/commits/*'.
      " Second parent is deliberately absent: only the first-parent chain counts.
      json = `{"values":[{"hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","message":"Remove companion",` &&
        `"author":{"raw":"Consultant <test@example.invalid>"},"date":"2026-10-05T00:00:00Z",` &&
        `"parents":[{"hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},` &&
        `{"hash":"cccccccccccccccccccccccccccccccccccccccc"}]},` &&
        `{"hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","message":"Initial pair",` &&
        `"author":{"raw":"Consultant"},"date":"2026-10-04T00:00:00Z","parents":[]}]}`.
    ELSEIF suffix CP '/diffstat/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa*'.
      diff_calls = diff_calls + 1.
      IF paginate = abap_true.
        json = `{"values":[],"next":"https://untrusted.invalid/page"}`.
      ELSEIF missing_all = abap_true OR suffix CS 'IMPORT.TDM'.
        json = `{"values":[{"status":"removed","old":{"type":"commit_file","path":"` && path && `"},"new":null}]}`.
      ELSE.
        json = `{"values":[]}`.
      ENDIF.
    ELSE.
      cl_abap_unit_assert=>fail( 'Unexpected HTTP request: history must not download files or follow second parents' ).
    ENDIF.
  ENDMETHOD.

  METHOD read.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo.git' ).
    result = remote->bitbucket_history( iv_head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' iv_depth = depth
      it_paths = VALUE #( ( `M/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.XLS` )
                         ( `M/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.TDM` ) ) ).
  ENDMETHOD.

  METHOD paired_history.
    DATA(result) = read( 20 ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-versions ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = result-versions[ 1 ]-present exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = result-versions[ 1 ]-complete exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = result-versions[ 2 ]-complete exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = result-versions[ 2 ]-commit exp = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' ).
    cl_abap_unit_assert=>assert_equals( act = result-truncated exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = diff_calls exp = 2 ).
  ENDMETHOD.

  METHOD deleted_pair.
    missing_all = abap_true.
    DATA(result) = read( 20 ).
    cl_abap_unit_assert=>assert_equals( act = result-versions[ 1 ]-present exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = result-versions[ 1 ]-complete exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = result-versions[ 2 ]-present exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = result-versions[ 2 ]-complete exp = abap_true ).
  ENDMETHOD.

  METHOD depth_boundary.
    DATA(result) = read( 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-versions ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = result-truncated exp = abap_true ).
  ENDMETHOD.

  METHOD incomplete_page.
    paginate = abap_true.
    TRY.
        DATA(result) = read( 20 ).
        cl_abap_unit_assert=>fail( 'A partial diff must not appear as complete history' ).
      CATCH zcx_abapgit_exception.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_lfs_hash DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS threshold_and_compare FOR TESTING RAISING zcx_abapgit_exception.
    METHODS existing_lfs FOR TESTING RAISING zcx_abapgit_exception.
ENDCLASS.

CLASS ltcl_lfs_hash IMPLEMENTATION.
  METHOD threshold_and_compare.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo'
      iv_lfs_enabled = abap_true iv_lfs_mb = 1 ).
    DATA(data) = cl_abap_codepage=>convert_to( repeat( val = 'a' occ = 1048576 ) ).
    DATA(path) = `M/EEXCEL/REPORTS/X.XLSX`.
    cl_abap_unit_assert=>assert_equals( act = remote->content_hash( iv_path = path iv_data = data )
      exp = zcl_bpc_git_remote=>blob_sha1( data ) ).
    cl_abap_unit_assert=>assert_equals( act = remote->content_hash( iv_path = path iv_data = data iv_staged = abap_true )
      exp = zcl_bpc_git_remote=>blob_sha1( zcl_bpc_git_lfs=>pointer( data ) ) ).
    cl_abap_unit_assert=>assert_equals( act = remote->content_hash(
      iv_path = 'M/DATAMANAGER/TRANSFORMATIONFILES/X.XLS' iv_data = data iv_staged = abap_true )
      exp = zcl_bpc_git_remote=>blob_sha1( data ) ).
    data = data(1048575).
    cl_abap_unit_assert=>assert_equals( act = remote->content_hash( iv_path = path iv_data = data iv_staged = abap_true )
      exp = zcl_bpc_git_remote=>blob_sha1( data ) ).
  ENDMETHOD.

  METHOD existing_lfs.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo' ).
    DATA(data) = cl_abap_codepage=>convert_to( 'abc' ).
    DATA(path) = `M/EEXCEL/REPORTS/X.XLSX`.
    INSERT VALUE #( path = path pointer = zcl_bpc_git_lfs=>parse( zcl_bpc_git_lfs=>pointer( data ) ) ) INTO TABLE remote->mt_lfs.
    " Existing pointers compare correctly even with the opt-in turned off.
    cl_abap_unit_assert=>assert_equals( act = remote->content_hash( iv_path = path iv_data = data )
      exp = zcl_bpc_git_remote=>blob_sha1( zcl_bpc_git_lfs=>pointer( data ) ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_root_folder DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS mapping_and_scope FOR TESTING RAISING zcx_abapgit_exception.
    METHODS rooted_content FOR TESTING RAISING zcx_abapgit_exception.
    METHODS invalid_folder FOR TESTING.
ENDCLASS.

CLASS ltcl_root_folder IMPLEMENTATION.
  METHOD mapping_and_scope.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo' iv_root_folder = '/content/bpc/' ).
    cl_abap_unit_assert=>assert_equals( act = remote->repository_path( 'M/EEXCEL/REPORTS/X.XLSX' )
      exp = 'content/bpc/M/EEXCEL/REPORTS/X.XLSX' ).
    DATA(content) = VALUE zcl_bpc_git_remote=>ty_branch_content( files = VALUE #(
      ( path = 'src/zexample.clas.abap' sha1 = '1' )
      ( path = 'content/bpc/M/X.XLS' sha1 = '2' )
      ( path = 'content/bpc-other/M/X.XLS' sha1 = '3' ) ) ).
    INSERT VALUE #( path = 'content/bpc/M/X.XLS' ) INTO TABLE content-lfs.
    INSERT VALUE #( path = 'src/OTHER.XLS' ) INTO TABLE content-lfs.
    remote->scope_content( CHANGING cs_content = content ).
    cl_abap_unit_assert=>assert_equals( act = lines( content-files ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = content-files[ 1 ]-path exp = 'M/X.XLS' ).
    cl_abap_unit_assert=>assert_equals( act = content-lfs[ 1 ]-path exp = 'M/X.XLS' ).
    DATA(legacy) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo' ).
    cl_abap_unit_assert=>assert_equals( act = legacy->repository_path( 'M/X.XLS' ) exp = 'M/X.XLS' ).
  ENDMETHOD.

  METHOD rooted_content.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo' iv_root_folder = 'bpc' ).
    DATA(data) = cl_abap_codepage=>convert_to( 'workbook bytes' ).
    INSERT VALUE #( path = '/bpc/M/EEXCEL/REPORTS/' filename = 'X.XLSX' data = data ) INTO TABLE remote->mt_pulled.
    cl_abap_unit_assert=>assert_equals( act = remote->get_content( 'M/EEXCEL/REPORTS/X.XLSX' ) exp = data ).
    INSERT VALUE #( path = 'bpc/M/EEXCEL/REPORTS/X.XLSX'
      pointer = zcl_bpc_git_lfs=>parse( zcl_bpc_git_lfs=>pointer( data ) ) ) INTO TABLE remote->mt_lfs.
    cl_abap_unit_assert=>assert_equals( act = remote->content_hash( iv_path = 'M/EEXCEL/REPORTS/X.XLSX' iv_data = data )
      exp = zcl_bpc_git_remote=>blob_sha1( zcl_bpc_git_lfs=>pointer( data ) ) ).
  ENDMETHOD.

  METHOD invalid_folder.
    TRY.
        DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo' iv_root_folder = 'bpc/../src' ).
        cl_abap_unit_assert=>fail( 'Traversal must be rejected' ).
      CATCH zcx_abapgit_exception.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
