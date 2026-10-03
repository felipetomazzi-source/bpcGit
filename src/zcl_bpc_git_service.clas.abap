"! bpcGit business logic: environments and the repository setup of an
"! environment (table ZBPC_GIT_REPO).
CLASS zcl_bpc_git_service DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES ty_environments TYPE STANDARD TABLE OF uj_appset_id WITH DEFAULT KEY.

    "! Environments the current user may access.
    METHODS get_environments
      RETURNING VALUE(rt_environments) TYPE ty_environments
      RAISING cx_uj_static_check.
    "! Repository setup of an environment; initial if it has none yet.
    METHODS get_config
      IMPORTING iv_environment TYPE uj_appset_id
      RETURNING VALUE(rs_config) TYPE zbpc_git_repo
      RAISING cx_uj_no_auth cx_uj_static_check.
    "! Checks and saves the repository setup of an environment. Returns a
    "! message for the user when the input is invalid, else nothing.
    METHODS save_config
      IMPORTING is_config TYPE zbpc_git_repo
      RETURNING VALUE(rv_message) TYPE string
      RAISING cx_uj_no_auth cx_uj_static_check.
  PRIVATE SECTION.
    CONSTANTS c_default_branch TYPE string VALUE 'main' ##NO_TEXT.
    CONSTANTS c_branch_prefix TYPE string VALUE 'refs/heads/' ##NO_TEXT.
    "! Raises CX_UJ_NO_AUTH unless the user may access the environment.
    METHODS check_environment
      IMPORTING iv_environment TYPE uj_appset_id
      RAISING cx_uj_no_auth cx_uj_static_check.
ENDCLASS.

CLASS zcl_bpc_git_service IMPLEMENTATION.
  METHOD get_environments.
    DATA(lo_manager) = cl_uja_bpc_admin_factory=>get_appset_manager(
      if_disable_security = abap_false ).
    lo_manager->get_appsets(
      EXPORTING i_user_id = CONV uj_user_id( sy-uname )
      IMPORTING et_appsets = DATA(lt_appsets) ).
    LOOP AT lt_appsets INTO DATA(ls_appset).
      APPEND ls_appset-appset_id TO rt_environments.
    ENDLOOP.
    SORT rt_environments.
    DELETE ADJACENT DUPLICATES FROM rt_environments.
  ENDMETHOD.

  METHOD get_config.
    check_environment( iv_environment ).
    SELECT SINGLE * FROM zbpc_git_repo
      WHERE appset = @iv_environment
      INTO @rs_config.
  ENDMETHOD.

  METHOD save_config.
    check_environment( is_config-appset ).

    DATA(lv_url) = condense( CONV string( is_config-url ) ).
    IF lv_url IS INITIAL OR lv_url NP 'https://*/*' OR lv_url CA ` `.
      rv_message = 'The repository URL must be an https:// address without spaces'.
      RETURN.
    ENDIF.

    DATA(lv_branch) = condense( CONV string( is_config-branch ) ).
    IF lv_branch IS INITIAL.
      lv_branch = c_default_branch.
    ENDIF.
    IF strlen( lv_branch ) > strlen( c_branch_prefix )
        AND substring( val = lv_branch len = strlen( c_branch_prefix ) ) = c_branch_prefix.
      lv_branch = substring( val = lv_branch off = strlen( c_branch_prefix ) ).
    ENDIF.
    IF lv_branch CA ` `.
      rv_message = 'The branch name must not contain spaces'.
      RETURN.
    ENDIF.

    " One environment per repository: both would write the same paths.
    SELECT SINGLE appset FROM zbpc_git_repo
      WHERE url = @lv_url AND appset <> @is_config-appset
      INTO @DATA(lv_other).
    IF sy-subrc = 0.
      rv_message = |This repository is already used by environment { lv_other }|.
      RETURN.
    ENDIF.

    DATA(ls_config) = VALUE zbpc_git_repo(
      appset     = is_config-appset
      url        = lv_url
      branch     = lv_branch
      changed_by = sy-uname ).
    GET TIME STAMP FIELD ls_config-changed_at.
    MODIFY zbpc_git_repo FROM ls_config.
  ENDMETHOD.

  METHOD check_environment.
    DATA(lt_environments) = get_environments( ).
    IF NOT line_exists( lt_environments[ table_line = iv_environment ] ).
      RAISE EXCEPTION TYPE cx_uj_no_auth.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
