"! Git access for bpcGit. The only class that calls abapGit (docs/SPEC.md 7.1).
"! Credentials work as in abapGit: they are optional, because public
"! repositories can be read without them, and the Git host asks for them
"! (HTTP 401) when it needs them, e.g. always to push. They live only for
"! the current request, in abapGit's login manager, and are never stored.
CLASS zcl_bpc_git_remote DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES ty_branches TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_connection,
        "! Branch names, without refs/heads/
        branches     TYPE ty_branches,
        branch_found TYPE abap_bool,
        "! Push access was checked; only done with credentials
        push_checked TYPE abap_bool,
        push_ok      TYPE abap_bool,
        push_message TYPE string,
      END OF ty_connection.
    TYPES:
      BEGIN OF ty_file,
        "! Repository path without leading slash, e.g. AGGR_OPEX/EEXCEL/X.XLSX
        path TYPE string,
        "! Git blob SHA-1, lower case
        sha1 TYPE string,
      END OF ty_file,
      ty_files TYPE SORTED TABLE OF ty_file WITH UNIQUE KEY path.
    TYPES:
      BEGIN OF ty_branch_content,
        "! False if the branch does not exist yet, e.g. in an empty repository
        branch_found TYPE abap_bool,
        "! Head commit of the branch
        commit       TYPE string,
        files        TYPE ty_files,
      END OF ty_branch_content.
    TYPES:
      BEGIN OF ty_change,
        "! Repository path, as in ty_file
        path   TYPE string,
        "! New content; ignored when deleting
        data   TYPE xstring,
        delete TYPE abap_bool,
      END OF ty_change,
      ty_changes TYPE STANDARD TABLE OF ty_change WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_version,
        commit TYPE string,
        author TYPE string,
        date TYPE string,
        message TYPE string,
        present TYPE abap_bool,
        complete TYPE abap_bool,
      END OF ty_version,
      ty_versions TYPE STANDARD TABLE OF ty_version WITH DEFAULT KEY,
      BEGIN OF ty_history,
        head TYPE string,
        truncated TYPE abap_bool,
        versions TYPE ty_versions,
      END OF ty_history.
    METHODS history
      IMPORTING iv_branch TYPE csequence it_paths TYPE string_table iv_depth TYPE i DEFAULT 100
      RETURNING VALUE(rs_history) TYPE ty_history
      RAISING zcx_abapgit_exception.
    METHODS read_version
      IMPORTING iv_commit TYPE string
      RETURNING VALUE(rs_content) TYPE ty_branch_content
      RAISING zcx_abapgit_exception.
    "! Version of the installed abapGit developer version, initial if it is
    "! missing. Read dynamically so the caller can report a missing abapGit.
    CLASS-METHODS get_abapgit_version
      RETURNING VALUE(rv_version) TYPE string.
    "! True if the Git host refused the request for missing or wrong credentials.
    CLASS-METHODS is_auth_error
      IMPORTING ix_error TYPE REF TO zcx_abapgit_exception
      RETURNING VALUE(rv_auth_error) TYPE abap_bool.
    "! Git blob SHA-1 of a file content, lower case, as Git computes it.
    CLASS-METHODS blob_sha1
      IMPORTING iv_data TYPE xstring
      RETURNING VALUE(rv_sha1) TYPE string
      RAISING zcx_abapgit_exception.
    "! Name and e-mail of an SAP user for commits, from the user master as
    "! abapGit reads them. Without an e-mail, the GitHub no-reply address of
    "! the Git user is used, or failing that one made from the SAP user.
    CLASS-METHODS get_author
      IMPORTING iv_user TYPE syuname iv_git_user TYPE string OPTIONAL
      EXPORTING ev_name TYPE string ev_email TYPE string.
    METHODS constructor
      IMPORTING iv_url TYPE csequence
                iv_user TYPE string OPTIONAL
                iv_token TYPE string OPTIONAL
      RAISING zcx_abapgit_exception.
    "! Reads the branches of the repository and, with credentials, checks
    "! that they may push.
    METHODS test_connection
      IMPORTING iv_branch TYPE csequence
      RETURNING VALUE(rs_result) TYPE ty_connection
      RAISING zcx_abapgit_exception.
    "! Paths and blob hashes of all files at the head of a branch. Keeps the
    "! Git objects, so that commit can build on this head.
    METHODS read_branch
      IMPORTING iv_branch TYPE csequence iv_metadata_only TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rs_content) TYPE ty_branch_content
      RAISING zcx_abapgit_exception.
    "! Content of a file at the head that read_branch returned.
    METHODS read_paths
      IMPORTING iv_branch TYPE csequence it_paths TYPE string_table
      RETURNING VALUE(rs_content) TYPE ty_branch_content RAISING zcx_abapgit_exception.
    METHODS get_content
      IMPORTING iv_path TYPE string
      RETURNING VALUE(rv_data) TYPE xstring
      RAISING zcx_abapgit_exception.
    "! Adds, updates and deletes files in one commit on top of the head that
    "! read_branch returned, and pushes it. Returns the new commit. The push
    "! fails if the branch has moved since, so nothing is overwritten.
    METHODS commit
      IMPORTING it_changes TYPE ty_changes
                iv_message TYPE string
                iv_author_name TYPE string
                iv_author_email TYPE string
      RETURNING VALUE(rv_commit) TYPE string
      RAISING zcx_abapgit_exception.
  PRIVATE SECTION.
    CONSTANTS c_heads TYPE string VALUE 'refs/heads/' ##NO_TEXT.
    DATA mv_url TYPE string.
    DATA mv_cache_user TYPE string.
    DATA mv_token TYPE string.
    DATA mv_bitbucket_api TYPE string.
    METHODS bitbucket_get
      IMPORTING iv_suffix TYPE string iv_allow_missing TYPE abap_bool DEFAULT abap_false
        iv_binary TYPE abap_bool DEFAULT abap_false
      EXPORTING ev_content TYPE xstring ev_missing TYPE abap_bool
      RETURNING VALUE(rv_json) TYPE string RAISING zcx_abapgit_exception.
    METHODS bitbucket_history
      IMPORTING iv_head TYPE string it_paths TYPE string_table iv_depth TYPE i
      RETURNING VALUE(rs_history) TYPE ty_history RAISING zcx_abapgit_exception.
    DATA mv_has_credentials TYPE abap_bool.
    "! Head read by read_branch: branch ref, commit, files and Git objects
    DATA mv_branch_ref TYPE string.
    DATA mv_commit TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA mt_files TYPE ty_files.
    DATA mt_objects TYPE zif_abapgit_definitions=>ty_objects_tt.
    "! Files with content, as abapGit's pull returns them
    DATA mt_pulled TYPE zif_abapgit_git_definitions=>ty_files_tt.
    "! Asks for the push advertisement (git-receive-pack), which the Git host
    "! only sends to users who may push.
    METHODS tree_signature
      IMPORTING it_objects TYPE zif_abapgit_definitions=>ty_objects_tt
                iv_tree TYPE zif_abapgit_git_definitions=>ty_sha1 it_paths TYPE string_table
      EXPORTING ev_signature TYPE string ev_present TYPE abap_bool ev_complete TYPE abap_bool
      RAISING zcx_abapgit_exception.
    METHODS check_push_access
      RAISING zcx_abapgit_exception.
ENDCLASS.

CLASS zcl_bpc_git_remote IMPLEMENTATION.
  METHOD get_abapgit_version.
    FIELD-SYMBOLS <lv_version> TYPE any.
    ASSIGN ('ZIF_ABAPGIT_VERSION=>C_ABAP_VERSION') TO <lv_version>.
    IF sy-subrc = 0.
      rv_version = <lv_version>.
    ENDIF.
  ENDMETHOD.

  METHOD is_auth_error.
    " abapGit has no own exception for this; both of its texts say so
    " ('Unauthorized access. Check your credentials' and '... (HTTP 401) ...').
    rv_auth_error = boolc( ix_error->get_text( ) CS 'Unauthorized' ).
  ENDMETHOD.

  METHOD blob_sha1.
    rv_sha1 = to_lower( zcl_abapgit_hash=>sha1_blob( iv_data ) ).
  ENDMETHOD.

  METHOD get_author.
    DATA(li_user) = zcl_abapgit_env_factory=>get_user_record( ).
    ev_name = li_user->get_name( iv_user ).
    ev_email = li_user->get_email( iv_user ).
    IF ev_name IS INITIAL.
      ev_name = iv_user.
    ENDIF.
    IF ev_email IS INITIAL.
      ev_email = COND #( WHEN iv_git_user IS NOT INITIAL
                         THEN |{ iv_git_user }@users.noreply.github.com|
                         ELSE |{ to_lower( iv_user ) }@{ to_lower( sy-sysid ) }.sap| ).
    ENDIF.
  ENDMETHOD.

  METHOD constructor.
    mv_url = iv_url.
    mv_cache_user = iv_user.
    mv_token = iv_token.
    DATA lv_workspace TYPE string.
    DATA lv_repository TYPE string.
    FIND REGEX '^https://bitbucket[.]org/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/?$'
      IN mv_url SUBMATCHES lv_workspace lv_repository.
    IF sy-subrc = 0.
      REPLACE REGEX '[.]git$' IN lv_repository WITH ''.
      mv_bitbucket_api = |https://api.bitbucket.org/2.0/repositories/{ lv_workspace }/{ lv_repository }|.
    ENDIF.
    zcl_abapgit_login_manager=>clear( ).
    IF iv_user IS NOT INITIAL AND iv_token IS NOT INITIAL.
      zcl_abapgit_login_manager=>set_basic( iv_uri = mv_url
                                            iv_username = iv_user
                                            iv_password = iv_token ).
      mv_has_credentials = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD test_connection.
    DATA(li_branch_list) = zcl_abapgit_git_transport=>branches( mv_url ).
    DATA(lt_branches) = li_branch_list->get_branches_only( ).
    LOOP AT lt_branches INTO DATA(ls_branch).
      APPEND ls_branch-display_name TO rs_result-branches.
      IF ls_branch-display_name = iv_branch.
        rs_result-branch_found = abap_true.
      ENDIF.
    ENDLOOP.
    SORT rs_result-branches.

    IF mv_has_credentials = abap_true.
      rs_result-push_checked = abap_true.
      TRY.
          check_push_access( ).
          rs_result-push_ok = abap_true.
        CATCH zcx_abapgit_exception INTO DATA(lx_push).
          rs_result-push_message = lx_push->get_text( ).
      ENDTRY.
    ENDIF.
  ENDMETHOD.

  METHOD read_branch.
    CLEAR: mv_branch_ref, mv_commit, mt_files, mt_objects, mt_pulled.
    DATA(lv_ref) = c_heads && iv_branch.
    DATA(lt_branches) = zcl_abapgit_git_transport=>branches( mv_url )->get_branches_only( ).
    IF NOT line_exists( lt_branches[ KEY name_key name = lv_ref ] ).
      RETURN.
    ENDIF.
    rs_content-branch_found = abap_true.
    " Cache only path/hash metadata. Verify current read access and head above
    " on every request; commits and restores always pull the full fresh tree.
    DATA lv_cache_key TYPE c LENGTH 40.
    lv_cache_key = blob_sha1( cl_abap_codepage=>convert_to(
      |{ sy-mandt }/{ sy-uname }/{ mv_cache_user }/{ mv_url }/{ lv_ref }| ) ).
    IF iv_metadata_only = abap_true.
      DATA ls_cached TYPE ty_branch_content.
      TRY.
          IMPORT metadata = ls_cached FROM SHARED BUFFER indx(bg) ID lv_cache_key.
          IF sy-subrc = 0 AND ls_cached-branch_found = abap_true
              AND ls_cached-commit = to_lower( lt_branches[ KEY name_key name = lv_ref ]-sha1 ).
            rs_content = ls_cached.
            RETURN.
          ENDIF.
        CATCH cx_sy_import_mismatch_error.
          CLEAR ls_cached.
      ENDTRY.
    ENDIF.

    DATA(ls_pull) = zcl_abapgit_git_porcelain=>pull_by_branch( iv_url = mv_url iv_branch_name = lv_ref ).
    rs_content-commit = to_lower( ls_pull-commit ).
    LOOP AT ls_pull-files INTO DATA(ls_file).
      " abapGit paths start and end with a slash, e.g. /AGGR_OPEX/EEXCEL/
      DATA(lv_path) = ls_file-path && ls_file-filename.
      IF strlen( lv_path ) > 1 AND lv_path(1) = '/'.
        lv_path = lv_path+1.
      ENDIF.
      INSERT VALUE #( path = lv_path sha1 = to_lower( ls_file-sha1 ) ) INTO TABLE rs_content-files.
    ENDLOOP.

    mv_branch_ref = lv_ref.
    mv_commit = ls_pull-commit.
    mt_files = rs_content-files.
    mt_objects = ls_pull-objects.
    mt_pulled = ls_pull-files.
    " Shared buffer may evict entries at any time; a miss simply pulls again.
    EXPORT metadata = rs_content TO SHARED BUFFER indx(bg) ID lv_cache_key.
  ENDMETHOD.

  METHOD tree_signature.
    CLEAR: ev_signature, ev_present, ev_complete.
    DATA lv_count TYPE i.
    LOOP AT it_paths INTO DATA(lv_path).
      DATA(lv_tree) = iv_tree.
      DATA lt_parts TYPE string_table.
      SPLIT lv_path AT '/' INTO TABLE lt_parts.
      DATA lv_blob TYPE string.
      CLEAR lv_blob.
      LOOP AT lt_parts INTO DATA(lv_part).
        DATA(lv_index) = sy-tabix.
        READ TABLE it_objects INTO DATA(ls_object) WITH KEY type COMPONENTS
          type = zif_abapgit_git_definitions=>c_type-tree sha1 = lv_tree.
        IF sy-subrc <> 0.
          zcx_abapgit_exception=>raise( 'Incomplete Git history tree' ).
        ENDIF.
        DATA(lt_nodes) = zcl_abapgit_git_pack=>decode_tree( ls_object-data ).
        READ TABLE lt_nodes INTO DATA(ls_node) WITH KEY name = lv_part.
        IF sy-subrc <> 0.
          CLEAR lv_blob.
          EXIT.
        ENDIF.
        IF lv_index = lines( lt_parts ).
          IF ls_node-chmod = zif_abapgit_git_definitions=>c_chmod-file
              OR ls_node-chmod = zif_abapgit_git_definitions=>c_chmod-executable.
            lv_blob = to_lower( ls_node-sha1 ).
          ENDIF.
        ELSEIF ls_node-chmod <> zif_abapgit_git_definitions=>c_chmod-dir.
          EXIT.
        ENDIF.
        lv_tree = ls_node-sha1.
      ENDLOOP.
      ev_signature = ev_signature && lv_path && ':' && lv_blob && ';'.
      IF lv_blob IS NOT INITIAL.
        lv_count = lv_count + 1.
      ENDIF.
    ENDLOOP.
    ev_present = xsdbool( lv_count > 0 ).
    ev_complete = xsdbool( lv_count = 0 OR lv_count = lines( it_paths ) ).
  ENDMETHOD.

  METHOD history.
    IF iv_depth < 1 OR iv_depth > 1000.
      zcx_abapgit_exception=>raise( 'History depth must be between 1 and 1000' ).
    ENDIF.
    " Recheck remote authorization/head even when a history result is cached.
    DATA(lt_branches) = zcl_abapgit_git_transport=>branches( mv_url )->get_branches_only( ).
    DATA(lv_ref) = c_heads && iv_branch.
    READ TABLE lt_branches INTO DATA(ls_branch) WITH KEY name_key COMPONENTS name = lv_ref.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( 'History branch does not exist' ).
    ENDIF.
    DATA lv_cache_key TYPE c LENGTH 40.
    lv_cache_key = blob_sha1( cl_abap_codepage=>convert_to(
      |history-v2/{ sy-mandt }/{ sy-uname }/{ mv_cache_user }/{ mv_url }/{ lv_ref }/{ iv_depth }| &&
      concat_lines_of( table = it_paths sep = cl_abap_char_utilities=>newline ) ) ).
    TRY.
        IMPORT history = rs_history FROM SHARED BUFFER indx(bh) ID lv_cache_key.
        IF sy-subrc = 0 AND rs_history-head = to_lower( ls_branch-sha1 ).
          RETURN.
        ENDIF.
      CATCH cx_sy_import_mismatch_error.
    ENDTRY.
    CLEAR rs_history.
    IF mv_bitbucket_api IS NOT INITIAL.
      rs_history = bitbucket_history( iv_head = to_lower( ls_branch-sha1 ) it_paths = it_paths iv_depth = iv_depth ).
      EXPORT history = rs_history TO SHARED BUFFER indx(bh) ID lv_cache_key.
      RETURN.
    ENDIF.
    " History needs commits and trees, not a materialized branch file list.
    DATA ls_pull TYPE zcl_abapgit_git_porcelain=>ty_pull_result.
    zcl_abapgit_git_transport=>upload_pack_by_branch(
      EXPORTING iv_url = mv_url iv_branch_name = lv_ref iv_deepen_level = iv_depth + 1
      IMPORTING et_objects = ls_pull-objects ev_branch = ls_pull-commit ).
    rs_history-head = to_lower( ls_pull-commit ).
    DATA(lv_commit) = ls_pull-commit.
    DATA lv_scanned TYPE i.
    WHILE lv_commit IS NOT INITIAL AND lv_scanned < iv_depth.
      READ TABLE ls_pull-objects INTO DATA(ls_object) WITH KEY type COMPONENTS
        type = zif_abapgit_git_definitions=>c_type-commit sha1 = lv_commit.
      IF sy-subrc <> 0.
        rs_history-truncated = abap_true.
        EXIT.
      ENDIF.
      DATA(ls_commit) = zcl_abapgit_git_pack=>decode_commit( ls_object-data ).
      tree_signature( EXPORTING it_objects = ls_pull-objects iv_tree = ls_commit-tree it_paths = it_paths
        IMPORTING ev_signature = DATA(lv_current) ev_present = DATA(lv_present) ev_complete = DATA(lv_complete) ).
      DATA lv_parent_signature TYPE string.
      CLEAR lv_parent_signature.
      IF ls_commit-parent IS NOT INITIAL.
        READ TABLE ls_pull-objects INTO DATA(ls_parent_object) WITH KEY type COMPONENTS
          type = zif_abapgit_git_definitions=>c_type-commit sha1 = ls_commit-parent.
        IF sy-subrc <> 0.
          rs_history-truncated = abap_true.
          EXIT.
        ENDIF.
        DATA(ls_parent) = zcl_abapgit_git_pack=>decode_commit( ls_parent_object-data ).
        tree_signature( EXPORTING it_objects = ls_pull-objects iv_tree = ls_parent-tree it_paths = it_paths
          IMPORTING ev_signature = lv_parent_signature ).
      ENDIF.
      IF lv_current <> lv_parent_signature AND ( ls_commit-parent IS NOT INITIAL OR lv_present = abap_true ).
        DATA lv_author TYPE string.
        DATA lv_seconds TYPE string.
        DATA lv_zone TYPE string.
        CLEAR: lv_author, lv_seconds, lv_zone.
        FIND REGEX '^(.*) <[^>]*> ([0-9]+) ([+-][0-9]{4})$' IN ls_commit-author
          SUBMATCHES lv_author lv_seconds lv_zone.
        DATA lv_date TYPE string.
        lv_date = lv_seconds.
        TRY.
            DATA lv_stamp TYPE timestampl.
            lv_stamp = cl_abap_tstmp=>add( tstmp = CONV timestamp( '19700101000000' ) secs = CONV i( lv_seconds ) ).
            DATA lv_day TYPE d.
            DATA lv_time TYPE t.
            CONVERT TIME STAMP lv_stamp TIME ZONE 'UTC' INTO DATE lv_day TIME lv_time.
            lv_date = |{ lv_day DATE = ISO } { lv_time TIME = ISO } UTC|.
          CATCH cx_root.
            lv_date = lv_seconds.
        ENDTRY.
        APPEND VALUE #( commit = to_lower( lv_commit ) author = lv_author date = lv_date
          message = ls_commit-body present = lv_present complete = lv_complete ) TO rs_history-versions.
      ENDIF.
      lv_commit = ls_commit-parent.
      lv_scanned = lv_scanned + 1.
    ENDWHILE.
    IF lv_commit IS NOT INITIAL.
      rs_history-truncated = abap_true.
    ENDIF.
    EXPORT history = rs_history TO SHARED BUFFER indx(bh) ID lv_cache_key.
  ENDMETHOD.

  METHOD bitbucket_get.
    TEST-SEAM bitbucket_http.
      " These private calls use pinned commit hashes; history rechecks Git access.
      DATA lv_cache_key TYPE c LENGTH 40.
      lv_cache_key = blob_sha1( cl_abap_codepage=>convert_to(
        |bitbucket-meta-v1/{ sy-mandt }/{ sy-uname }/{ mv_cache_user }/{ mv_bitbucket_api }/{ iv_suffix }| ) ).
      CLEAR: ev_content, ev_missing.
      IF iv_binary = abap_false.
      TRY.
          IMPORT metadata = rv_json FROM SHARED BUFFER indx(bi) ID lv_cache_key.
          IF sy-subrc = 0.
            RETURN.
          ENDIF.
        CATCH cx_sy_import_mismatch_error.
          CLEAR rv_json.
      ENDTRY.
      ENDIF.
      " The host is constructed locally; credentials never follow API links.
      DATA lo_client TYPE REF TO if_http_client.
      cl_http_client=>create_by_url( EXPORTING url = mv_bitbucket_api && iv_suffix
        IMPORTING client = lo_client EXCEPTIONS OTHERS = 1 ).
      IF sy-subrc <> 0.
        zcx_abapgit_exception=>raise( 'Cannot connect to api.bitbucket.org; check SAP HTTPS configuration' ).
      ENDIF.
      lo_client->propertytype_logon_popup = if_http_client=>co_disabled.
      lo_client->propertytype_redirect = if_http_client=>co_disabled.
      lo_client->request->set_method( 'GET' ).
      lo_client->request->set_header_field( name = 'Accept' value = COND string(
        WHEN iv_binary = abap_true THEN 'application/octet-stream' ELSE 'application/json' ) ).
      IF mv_has_credentials = abap_true.
        IF mv_cache_user = 'x-token-auth'.
          lo_client->request->set_header_field( name = 'Authorization' value = |Bearer { mv_token }| ).
        ELSE.
          lo_client->authenticate( username = mv_cache_user password = mv_token ).
        ENDIF.
      ENDIF.
      lo_client->send( EXPORTING timeout = 30 EXCEPTIONS OTHERS = 1 ).
      IF sy-subrc = 0.
        lo_client->receive( EXCEPTIONS OTHERS = 1 ).
      ENDIF.
      IF sy-subrc <> 0.
        DATA lv_error_code TYPE i.
        DATA lv_error_message TYPE string.
        lo_client->get_last_error( IMPORTING code = lv_error_code message = lv_error_message ).
        lo_client->close( ).
        IF mv_token IS NOT INITIAL.
          REPLACE ALL OCCURRENCES OF mv_token IN lv_error_message WITH '[redacted]'.
        ENDIF.
        zcx_abapgit_exception=>raise(
          |Bitbucket API connection failed (SAP { lv_error_code }): { lv_error_message }. Check HTTPS access to api.bitbucket.org| ).
      ENDIF.
      DATA lv_status TYPE i.
      lo_client->response->get_status( IMPORTING code = lv_status ).
      IF iv_binary = abap_true.
        ev_content = lo_client->response->get_data( ).
      ELSE.
        rv_json = lo_client->response->get_cdata( ).
      ENDIF.
      lo_client->close( ).
      IF lv_status = 404 AND iv_allow_missing = abap_true.
        CLEAR: rv_json, ev_content.
        ev_missing = abap_true.
        IF iv_binary = abap_false.
          EXPORT metadata = rv_json TO SHARED BUFFER indx(bi) ID lv_cache_key.
        ENDIF.
        RETURN.
      ENDIF.
      IF lv_status = 401.
        zcx_abapgit_exception=>raise( 'Unauthorized Bitbucket history API access. Use a repository access token with x-token-auth, or an API token with your Atlassian email as the user' ).
      ENDIF.
      IF lv_status <> 200.
        zcx_abapgit_exception=>raise( |Bitbucket history API returned HTTP { lv_status }; check API repository read permission and SAP connectivity| ).
      ENDIF.
      IF strlen( rv_json ) > 1048576.
        zcx_abapgit_exception=>raise( 'Bitbucket history metadata exceeds the 1 MB response limit' ).
      ENDIF.
      IF iv_binary = abap_false.
        EXPORT metadata = rv_json TO SHARED BUFFER indx(bi) ID lv_cache_key.
      ELSEIF xstrlen( ev_content ) > 16777216.
        zcx_abapgit_exception=>raise( 'Selected Git file exceeds the 16 MB Diff limit' ).
      ENDIF.
    END-TEST-SEAM.
  ENDMETHOD.

  METHOD bitbucket_history.
    TYPES: BEGIN OF ty_parent,
             hash TYPE string,
           END OF ty_parent,
           ty_parents TYPE STANDARD TABLE OF ty_parent WITH DEFAULT KEY,
           BEGIN OF ty_author,
             raw TYPE string,
           END OF ty_author,
           BEGIN OF ty_commit,
             hash TYPE string,
             message TYPE string,
             date TYPE string,
             author TYPE ty_author,
             parents TYPE ty_parents,
           END OF ty_commit,
           ty_commits TYPE STANDARD TABLE OF ty_commit WITH DEFAULT KEY,
           BEGIN OF ty_commit_page,
             values TYPE ty_commits,
           END OF ty_commit_page,
           BEGIN OF ty_file,
             path TYPE string,
             type TYPE string,
           END OF ty_file,
           BEGIN OF ty_change,
             status TYPE string,
             old TYPE ty_file,
             new TYPE ty_file,
           END OF ty_change,
           ty_changes TYPE STANDARD TABLE OF ty_change WITH DEFAULT KEY,
           BEGIN OF ty_diff,
             values TYPE ty_changes,
             next TYPE string,
           END OF ty_diff,
           BEGIN OF ty_presence,
             path TYPE string,
             present TYPE abap_bool,
           END OF ty_presence,
           ty_presences TYPE SORTED TABLE OF ty_presence WITH UNIQUE KEY path.
    DATA lt_present TYPE ty_presences.
    rs_history-head = iv_head.
    " Get presence once at the pinned head, then walk change metadata backwards.
    LOOP AT it_paths INTO DATA(lv_path).
      DATA(lv_json) = bitbucket_get( iv_suffix = |/src/{ iv_head }/{ cl_http_utility=>escape_url( lv_path ) }?format=meta|
        iv_allow_missing = abap_true ).
      DATA ls_meta TYPE ty_file.
      CLEAR ls_meta.
      IF lv_json IS NOT INITIAL.
        /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_meta ).
        IF ls_meta-type <> 'commit_file' OR ls_meta-path <> lv_path.
          zcx_abapgit_exception=>raise( 'Invalid Bitbucket history file metadata' ).
        ENDIF.
      ENDIF.
      INSERT VALUE #( path = lv_path present = xsdbool( lv_json IS NOT INITIAL ) ) INTO TABLE lt_present.
    ENDLOOP.
    " Batch recent commit headers; follow first parents locally, not API ordering.
    lv_json = bitbucket_get( |/commits/{ iv_head }?pagelen=100&fields=values.hash,values.message,values.date,values.author.raw,values.parents.hash| ).
    DATA ls_commits TYPE ty_commit_page.
    /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_commits ).
    DATA(lv_hash) = iv_head.
    DO iv_depth TIMES.
      IF strlen( lv_hash ) <> 40 OR lv_hash CN '0123456789abcdef'.
        zcx_abapgit_exception=>raise( 'Invalid Bitbucket history commit' ).
      ENDIF.
      DATA ls_commit TYPE ty_commit.
      CLEAR ls_commit.
      READ TABLE ls_commits-values INTO ls_commit WITH KEY hash = lv_hash.
      IF sy-subrc <> 0.
        lv_json = bitbucket_get( |/commit/{ lv_hash }| ).
        /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_commit ).
      ENDIF.
      IF ls_commit-hash <> lv_hash.
        zcx_abapgit_exception=>raise( 'Incomplete Bitbucket history commit metadata' ).
      ENDIF.
      DATA lv_changed TYPE abap_bool.
      DATA lv_count TYPE i.
      CLEAR: lv_changed, lv_count.
      LOOP AT lt_present INTO DATA(ls_present) WHERE present = abap_true.
        lv_count = lv_count + 1.
      ENDLOOP.
      DATA(lv_present) = xsdbool( lv_count > 0 ).
      DATA(lv_complete) = xsdbool( lv_count = 0 OR lv_count = lines( it_paths ) ).
      IF ls_commit-parents IS INITIAL.
        lv_changed = lv_present.
      ELSE.
        LOOP AT it_paths INTO lv_path.
          lv_json = bitbucket_get( |/diffstat/{ lv_hash }?path={ cl_http_utility=>escape_url( lv_path ) }&renames=false&pagelen=100| ).
          DATA ls_diff TYPE ty_diff.
          CLEAR ls_diff.
          /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_diff ).
          " A file filter should fit one page; never silently lose changes.
          IF lv_json NS '"values"'.
            zcx_abapgit_exception=>raise( 'Invalid Bitbucket history diff metadata' ).
          ENDIF.
          IF ls_diff-next IS NOT INITIAL.
            zcx_abapgit_exception=>raise( 'Bitbucket returned an incomplete filtered history diff' ).
          ENDIF.
          LOOP AT ls_diff-values INTO DATA(ls_change).
            IF ls_change-old-path <> lv_path AND ls_change-new-path <> lv_path.
              CONTINUE.
            ENDIF.
            lv_changed = abap_true.
            READ TABLE lt_present ASSIGNING FIELD-SYMBOL(<ls_present>) WITH TABLE KEY path = lv_path.
            <ls_present>-present = xsdbool( ls_change-old-path = lv_path AND ls_change-old-type = 'commit_file' ).
          ENDLOOP.
        ENDLOOP.
      ENDIF.
      IF lv_changed = abap_true.
        APPEND VALUE #( commit = lv_hash author = ls_commit-author-raw date = ls_commit-date
          message = ls_commit-message present = lv_present complete = lv_complete ) TO rs_history-versions.
      ENDIF.
      IF ls_commit-parents IS INITIAL.
        CLEAR lv_hash.
        EXIT.
      ENDIF.
      lv_hash = to_lower( ls_commit-parents[ 1 ]-hash ).
    ENDDO.
    rs_history-truncated = xsdbool( lv_hash IS NOT INITIAL ).
  ENDMETHOD.

  METHOD read_version.
    IF strlen( iv_commit ) <> 40 OR iv_commit CN '0123456789abcdef'.
      zcx_abapgit_exception=>raise( 'Invalid history commit' ).
    ENDIF.
    DATA(ls_pull) = zcl_abapgit_git_porcelain=>pull_by_commit(
      iv_url = mv_url iv_commit_hash = CONV #( iv_commit ) ).
    rs_content-branch_found = abap_true.
    rs_content-commit = to_lower( ls_pull-commit ).
    LOOP AT ls_pull-files INTO DATA(ls_file).
      DATA(lv_path) = ls_file-path && ls_file-filename.
      IF lv_path(1) = '/'.
        lv_path = lv_path+1.
      ENDIF.
      INSERT VALUE #( path = lv_path sha1 = to_lower( ls_file-sha1 ) ) INTO TABLE rs_content-files.
    ENDLOOP.
    mt_pulled = ls_pull-files.
  ENDMETHOD.

  METHOD read_paths.
    IF mv_bitbucket_api IS INITIAL.
      rs_content = read_branch( iv_branch ).
      RETURN.
    ENDIF.
    DATA(lv_ref) = c_heads && iv_branch.
    DATA(lt_branches) = zcl_abapgit_git_transport=>branches( mv_url )->get_branches_only( ).
    READ TABLE lt_branches INTO DATA(ls_branch) WITH KEY name_key COMPONENTS name = lv_ref.
    CLEAR mt_pulled.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    rs_content-branch_found = abap_true.
    rs_content-commit = to_lower( ls_branch-sha1 ).
    LOOP AT it_paths INTO DATA(lv_path).
      DATA lv_data TYPE xstring.
      DATA lv_missing TYPE abap_bool.
      bitbucket_get( EXPORTING iv_suffix = |/src/{ rs_content-commit }/{ cl_http_utility=>escape_url( lv_path ) }|
        iv_allow_missing = abap_true iv_binary = abap_true
        IMPORTING ev_content = lv_data ev_missing = lv_missing ).
      IF lv_missing = abap_true.
        CONTINUE.
      ENDIF.
      DATA(lv_sha1) = blob_sha1( lv_data ).
      INSERT VALUE #( path = lv_path sha1 = lv_sha1 ) INTO TABLE rs_content-files.
      APPEND VALUE #( path = |/{ substring_before( val = lv_path sub = '/' occ = -1 ) }/|
        filename = substring_after( val = lv_path sub = '/' occ = -1 ) data = lv_data sha1 = lv_sha1 ) TO mt_pulled.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_content.
    " abapGit keeps /folder/ and the file name separately
    DATA(lv_folder) = |/{ substring_before( val = iv_path sub = '/' occ = -1 ) }/|.
    DATA(lv_filename) = substring_after( val = iv_path sub = '/' occ = -1 ).
    READ TABLE mt_pulled INTO DATA(ls_file) WITH KEY file_path COMPONENTS path = lv_folder filename = lv_filename.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( |{ iv_path } is not in the repository| ).
    ENDIF.
    rv_data = ls_file-data.
  ENDMETHOD.

  METHOD commit.
    IF mv_commit IS INITIAL.
      zcx_abapgit_exception=>raise( 'The branch must exist and be read before committing' ).
    ENDIF.

    DATA(lo_stage) = NEW zcl_abapgit_stage( ).
    LOOP AT it_changes INTO DATA(ls_change).
      " abapGit wants /folder/ and the file name separately
      DATA(lv_folder) = |/{ substring_before( val = ls_change-path sub = '/' occ = -1 ) }/|.
      DATA(lv_filename) = substring_after( val = ls_change-path sub = '/' occ = -1 ).
      IF ls_change-delete = abap_true.
        " abapGit's push stops with an ASSERT for a file that is not in Git
        IF NOT line_exists( mt_files[ path = ls_change-path ] ).
          zcx_abapgit_exception=>raise( |{ ls_change-path } is not in the repository| ).
        ENDIF.
        lo_stage->rm( iv_path = lv_folder iv_filename = lv_filename ).
      ELSE.
        lo_stage->add( iv_path = lv_folder iv_filename = lv_filename iv_data = ls_change-data ).
      ENDIF.
    ENDLOOP.

    DATA ls_comment TYPE zif_abapgit_git_definitions=>ty_comment.
    ls_comment-committer-name = iv_author_name.
    ls_comment-committer-email = iv_author_email.
    ls_comment-comment = iv_message.
    DATA(ls_push) = zcl_abapgit_git_porcelain=>push( is_comment = ls_comment
                                                     io_stage = lo_stage
                                                     it_old_objects = mt_objects
                                                     iv_parent = mv_commit
                                                     iv_url = mv_url
                                                     iv_branch_name = mv_branch_ref ).
    rv_commit = to_lower( ls_push-branch ).
  ENDMETHOD.

  METHOD check_push_access.
    DATA lt_headers TYPE zcl_abapgit_http=>ty_headers.
    APPEND VALUE #( key   = '~request_uri'
                    value = zcl_abapgit_url=>path_name( mv_url ) && '/info/refs?service=git-receive-pack' )
      TO lt_headers.
    " Sends the request and raises unless the host answers 200
    DATA(lo_client) = zcl_abapgit_http=>create_by_url( iv_url = mv_url it_headers = lt_headers ).
    lo_client->check_smart_response(
      iv_expected_content_type = 'application/x-git-receive-pack-advertisement'
      iv_content_regex         = '^[0-9a-f]{4}#' ).
    lo_client->close( ).
  ENDMETHOD.
ENDCLASS.
