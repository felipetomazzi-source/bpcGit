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

    "! Version of the installed abapGit developer version, initial if it is
    "! missing. Read dynamically so the caller can report a missing abapGit.
    CLASS-METHODS get_abapgit_version
      RETURNING VALUE(rv_version) TYPE string.
    "! True if the Git host refused the request for missing or wrong credentials.
    CLASS-METHODS is_auth_error
      IMPORTING ix_error TYPE REF TO zcx_abapgit_exception
      RETURNING VALUE(rv_auth_error) TYPE abap_bool.
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
  PRIVATE SECTION.
    DATA mv_url TYPE string.
    DATA mv_has_credentials TYPE abap_bool.
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
