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
      IMPORTING iv_branch TYPE csequence
      RETURNING VALUE(rs_content) TYPE ty_branch_content
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
    DATA mv_has_credentials TYPE abap_bool.
    "! Head read by read_branch: branch ref, commit, files and Git objects
    DATA mv_branch_ref TYPE string.
    DATA mv_commit TYPE zif_abapgit_git_definitions=>ty_sha1.
    DATA mt_files TYPE ty_files.
    DATA mt_objects TYPE zif_abapgit_definitions=>ty_objects_tt.
    "! Asks for the push advertisement (git-receive-pack), which the Git host
    "! only sends to users who may push.
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
    CLEAR: mv_branch_ref, mv_commit, mt_files, mt_objects.
    DATA(lv_ref) = c_heads && iv_branch.
    DATA(lt_branches) = zcl_abapgit_git_transport=>branches( mv_url )->get_branches_only( ).
    IF NOT line_exists( lt_branches[ KEY name_key name = lv_ref ] ).
      RETURN.
    ENDIF.
    rs_content-branch_found = abap_true.

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
