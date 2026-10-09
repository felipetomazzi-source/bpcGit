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
    METHODS url_credentials FOR TESTING RAISING zcx_abapgit_exception.
    METHODS mapping_and_scope FOR TESTING RAISING zcx_abapgit_exception.
    METHODS rooted_content FOR TESTING RAISING zcx_abapgit_exception.
    METHODS invalid_folder FOR TESTING.
ENDCLASS.

CLASS ltcl_root_folder IMPLEMENTATION.
  METHOD url_credentials.
    DATA(url) = `https://user%40example.com:fake+token%3Apart=one@bitbucket.org/test/repo.git`.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = url ).
    cl_abap_unit_assert=>assert_equals( act = remote->mv_url exp = 'https://bitbucket.org/test/repo.git' ).
    cl_abap_unit_assert=>assert_equals( act = remote->mv_cache_user exp = 'user@example.com' ).
    cl_abap_unit_assert=>assert_equals( act = remote->mv_token exp = 'fake+token:part=one' ).
    cl_abap_unit_assert=>assert_equals( act = remote->mv_bitbucket_api
      exp = 'https://api.bitbucket.org/2.0/repositories/test/repo' ).
    cl_abap_unit_assert=>assert_true( remote->mv_has_credentials ).
    remote = NEW zcl_bpc_git_remote( iv_url = url iv_user = 'override' iv_token = 'fake-override' ).
    cl_abap_unit_assert=>assert_equals( act = remote->mv_cache_user exp = 'override' ).
    cl_abap_unit_assert=>assert_equals( act = remote->mv_token exp = 'fake-override' ).
    remote = NEW zcl_bpc_git_remote( iv_url = 'https://github.com/test/repo.git' ).
    cl_abap_unit_assert=>assert_initial( remote->mv_token ).
    TRY.
        remote = NEW zcl_bpc_git_remote( iv_url = 'https://user:@github.com/test/repo.git' ).
        cl_abap_unit_assert=>fail( 'Empty embedded token must fail before a request' ).
      CATCH zcx_abapgit_exception.
    ENDTRY.
    zcl_abapgit_login_manager=>clear( ).
  ENDMETHOD.

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

CLASS ltcl_auth_diagnostics DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PUBLIC SECTION.
    CLASS-DATA fail_read TYPE abap_bool.
  PRIVATE SECTION.
    METHODS setup.
    METHODS credentials_and_urls FOR TESTING RAISING zcx_abapgit_exception.
    METHODS anonymous_failure FOR TESTING RAISING zcx_abapgit_exception.
    METHODS status_classification FOR TESTING.
ENDCLASS.

CLASS ltcl_auth_diagnostics IMPLEMENTATION.
  METHOD setup.
    fail_read = abap_false.
    TEST-INJECTION auth_diagnostic_http.
      IF ltcl_auth_diagnostics=>fail_read = abap_true AND lv_service = 'upload'.
        zcx_abapgit_exception=>raise( 'Forbidden (HTTP 403) diagnostic-fixture-secret' ).
      ENDIF.
      ls_check-status = 200.
      ls_check-status_source = 'fixture'.
      ls_check-ok = abap_true.
    END-TEST-INJECTION.
  ENDMETHOD.

  METHOD credentials_and_urls.
    fail_read = abap_true.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo.git'
      iv_user = 'x-token-auth' iv_token = 'diagnostic-fixture-secret' ).
    DATA(result) = remote->auth_diagnostics( ).
    cl_abap_unit_assert=>assert_equals( act = result-credentials_found exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = result-username exp = 'x-token-auth' ).
    cl_abap_unit_assert=>assert_equals( act = result-rest_scheme exp = 'Bearer' ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-checks ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 1 ]-status exp = 403 ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 1 ]-auth_required exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 1 ]-message exp = 'Forbidden (HTTP 403) [redacted]' ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 2 ]-ok exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 2 ]-url
      exp = 'https://bitbucket.org/test/repo.git/info/refs?service=git-receive-pack' ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 2 ]-auth_scheme exp = 'Basic' ).
  ENDMETHOD.

  METHOD anonymous_failure.
    fail_read = abap_true.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://bitbucket.org/test/repo.git' ).
    DATA(result) = remote->auth_diagnostics( ).
    cl_abap_unit_assert=>assert_equals( act = result-credentials_found exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 1 ]-auth_scheme exp = 'none' ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 1 ]-auth_required exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = result-checks[ 2 ]-ok exp = abap_true ).
  ENDMETHOD.

  METHOD status_classification.
    DATA messages TYPE string_table.
    APPEND 'Unauthorized access. Check your credentials' TO messages.
    APPEND 'Authentication failed (HTTP 401)' TO messages.
    APPEND 'Access to resource forbidden (HTTP 403)' TO messages.
    APPEND 'Repository missing (HTTP 404)' TO messages.
    LOOP AT messages INTO DATA(message).
      TRY.
          zcx_abapgit_exception=>raise( message ).
        CATCH zcx_abapgit_exception INTO DATA(error).
          cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_remote=>is_auth_error( error )
            exp = xsdbool( message NS '404' ) ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_snapshot_cache DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PUBLIC SECTION.
    CLASS-DATA head TYPE zif_abapgit_git_definitions=>ty_sha1.
    CLASS-DATA pulls TYPE i.
    CLASS-DATA denied TYPE abap_bool.
  PRIVATE SECTION.
    METHODS reuse_and_invalidate FOR TESTING RAISING zcx_abapgit_exception.
ENDCLASS.
CLASS ltcl_snapshot_cache IMPLEMENTATION.
  METHOD reuse_and_invalidate.
    DATA key TYPE c LENGTH 40.
    key = zcl_bpc_git_remote=>blob_sha1( cl_abap_codepage=>convert_to(
      |root-v1//{ sy-mandt }/{ sy-uname }//https://example.invalid/snapshot-test.git/refs/heads/main| ) ).
    DELETE FROM SHARED BUFFER indx(bf) ID key.
    CLEAR: pulls, denied.
    head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'.
    TEST-INJECTION snapshot_refs.
      IF ltcl_snapshot_cache=>denied = abap_true.
        zcx_abapgit_exception=>raise( 'Read denied' ).
      ENDIF.
      lt_branches = VALUE #( ( name = lv_ref sha1 = ltcl_snapshot_cache=>head ) ).
    END-TEST-INJECTION.
    TEST-INJECTION snapshot_pull.
      ltcl_snapshot_cache=>pulls = ltcl_snapshot_cache=>pulls + 1.
      ls_pull-commit = ltcl_snapshot_cache=>head.
      ls_pull-objects = VALUE #( ( type = zif_abapgit_git_definitions=>c_type-blob
        sha1 = ltcl_snapshot_cache=>head data = '4142' ) ).
      ls_pull-files = VALUE #( ( path = '/M/EEXCEL/' filename = 'TEST.XLS'
        sha1 = ltcl_snapshot_cache=>head data = '4142' ) ).
    END-TEST-INJECTION.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://example.invalid/snapshot-test.git' ).
    DATA(first) = remote->read_branch( 'main' ).
    DATA(second) = remote->read_branch( 'main' ).
    cl_abap_unit_assert=>assert_equals( act = pulls exp = 1 msg = 'Same head reuses full snapshot' ).
    cl_abap_unit_assert=>assert_equals( act = second exp = first ).
    cl_abap_unit_assert=>assert_equals( act = remote->get_content( 'M/EEXCEL/TEST.XLS' ) exp = CONV xstring( '4142' ) ).
    head = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'.
    DATA(changed) = remote->read_branch( 'main' ).
    cl_abap_unit_assert=>assert_equals( act = pulls exp = 2 msg = 'New head pulls again' ).
    cl_abap_unit_assert=>assert_equals( act = changed-commit exp = CONV string( head ) ).
    denied = abap_true.
    TRY.
        remote->read_branch( 'main' ).
        cl_abap_unit_assert=>fail( 'Cached snapshot must not bypass access check' ).
      CATCH zcx_abapgit_exception.
    ENDTRY.
    DELETE FROM SHARED BUFFER indx(bf) ID key.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_notebook_history DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS directory_changes FOR TESTING RAISING zcx_abapgit_exception.
ENDCLASS.
CLASS ltcl_notebook_history IMPLEMENTATION.
  METHOD directory_changes.
    DATA(remote) = NEW zcl_bpc_git_remote( iv_url = 'https://example.invalid/notebook-test.git' ).
    DATA(root) = repeat( val = 'a' occ = 40 ).
    DATA(folder) = repeat( val = 'b' occ = 40 ).
    DATA(first) = repeat( val = 'c' occ = 40 ).
    DATA(second) = repeat( val = 'd' occ = 40 ).
    DATA objects TYPE zif_abapgit_definitions=>ty_objects_tt.
    objects = VALUE #( ( sha1 = root type = zif_abapgit_git_definitions=>c_type-tree
      data = zcl_abapgit_git_pack=>encode_tree( VALUE #( ( name = 'NOTEBOOKS'
        chmod = zif_abapgit_git_definitions=>c_chmod-dir sha1 = folder ) ) ) )
      ( sha1 = folder type = zif_abapgit_git_definitions=>c_type-tree
      data = zcl_abapgit_git_pack=>encode_tree( VALUE #( ( name = 'revenue'
        chmod = zif_abapgit_git_definitions=>c_chmod-dir sha1 = first ) ) ) ) ).
    remote->tree_signature( EXPORTING it_objects = objects iv_tree = root
      it_paths = VALUE #( ( `NOTEBOOKS/revenue/` ) )
      IMPORTING ev_signature = DATA(before) ev_present = DATA(present) ev_complete = DATA(complete) ).
    cl_abap_unit_assert=>assert_true( present ).
    cl_abap_unit_assert=>assert_true( complete ).
    READ TABLE objects ASSIGNING FIELD-SYMBOL(<folder>) WITH KEY type COMPONENTS
      type = zif_abapgit_git_definitions=>c_type-tree sha1 = folder.
    <folder>-data = zcl_abapgit_git_pack=>encode_tree( VALUE #( ( name = 'revenue'
      chmod = zif_abapgit_git_definitions=>c_chmod-dir sha1 = second ) ) ).
    remote->tree_signature( EXPORTING it_objects = objects iv_tree = root
      it_paths = VALUE #( ( `NOTEBOOKS/revenue/` ) ) IMPORTING ev_signature = DATA(after) ).
    cl_abap_unit_assert=>assert_differs( act = after exp = before ).
    remote->tree_signature( EXPORTING it_objects = objects iv_tree = root
      it_paths = VALUE #( ( `NOTEBOOKS/missing/` ) ) IMPORTING ev_present = present ).
    cl_abap_unit_assert=>assert_false( present ).
  ENDMETHOD.
ENDCLASS.
