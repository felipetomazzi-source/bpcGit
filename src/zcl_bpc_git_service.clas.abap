"! bpcGit business logic: environments, the repository setup of an
"! environment (table ZBPC_GIT_REPO) and the Git status of its EPM workbooks
"! (docs/SPEC.md sections 3 and 6).
CLASS zcl_bpc_git_service DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES ty_environments TYPE STANDARD TABLE OF uj_appset_id WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_workbook,
        "! Repository path, e.g. AGGR_OPEX/EEXCEL/REPORTS/X.XLSX
        path       TYPE string,
        model      TYPE string,
        "! One of c_status
        status     TYPE string,
        in_bpc     TYPE abap_bool,
        "! Last change in BPC as YYYY-MM-DD HH:MM:SS, with user and size
        changed_at TYPE string,
        changed_by TYPE string,
        size       TYPE i,
        "! For commit and restore: BPC document and its last change
        docname     TYPE uj_docname,
        lstmod_date TYPE uj_lstmod_date,
        lstmod_time TYPE uj_lstmod_time,
      END OF ty_workbook,
      ty_workbooks TYPE STANDARD TABLE OF ty_workbook WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_overview,
        branch_found TYPE abap_bool,
        commit       TYPE string,
        workbooks    TYPE ty_workbooks,
      END OF ty_overview.
    CONSTANTS:
      BEGIN OF c_status,
        unchanged    TYPE string VALUE 'UNCHANGED',
        modified_bpc TYPE string VALUE 'MODIFIED_BPC',
        modified_git TYPE string VALUE 'MODIFIED_GIT',
        conflict     TYPE string VALUE 'CONFLICT',
        new_bpc      TYPE string VALUE 'NEW_BPC',
        new_git      TYPE string VALUE 'NEW_GIT',
        deleted_bpc  TYPE string VALUE 'DELETED_BPC',
        deleted_git  TYPE string VALUE 'DELETED_GIT',
        "! In BPC and Git with different content, but never synced by bpcGit
        differs      TYPE string VALUE 'DIFFERS',
      END OF c_status.

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
    "! Workbooks of the environment in BPC and in Git, each with its status.
    "! BPC content is only read when its hash is needed for the status.
    METHODS get_overview
      IMPORTING iv_environment TYPE uj_appset_id
                io_remote TYPE REF TO zcl_bpc_git_remote
      RETURNING VALUE(rs_overview) TYPE ty_overview
      RAISING cx_uj_no_auth cx_uj_static_check zcx_abapgit_exception.
    "! Commits the BPC version of the given workbooks in one commit (F4) and
    "! records them as synced. Refuses, with ev_error for the user, if the
    "! branch has moved past iv_expected_commit (the head the user saw) or a
    "! workbook's status does not allow a commit (see is_committable).
    METHODS commit_workbooks
      IMPORTING iv_environment TYPE uj_appset_id
                io_remote TYPE REF TO zcl_bpc_git_remote
                it_paths TYPE string_table
                iv_message TYPE string
                iv_expected_commit TYPE string
                iv_git_user TYPE string OPTIONAL
      EXPORTING ev_error TYPE string
                ev_commit TYPE string
      RAISING cx_uj_no_auth cx_uj_static_check zcx_abapgit_exception.
    "! True for the statuses whose BPC version may be committed: new or
    "! modified in BPC, never synced but different, or deleted in BPC.
    "! Conflicts and Git-side changes are refused, so nothing in Git that the
    "! user has not seen is overwritten.
    CLASS-METHODS is_committable
      IMPORTING iv_status TYPE string
      RETURNING VALUE(rv_committable) TYPE abap_bool.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_bpc_workbook,
        path        TYPE string,
        docname     TYPE uj_docname,
        model       TYPE string,
        lstmod_date TYPE uj_lstmod_date,
        lstmod_time TYPE uj_lstmod_time,
        lstmod_user TYPE string,
        size        TYPE i,
      END OF ty_bpc_workbook,
      ty_bpc_workbooks TYPE SORTED TABLE OF ty_bpc_workbook WITH UNIQUE KEY path.
    TYPES ty_states TYPE SORTED TABLE OF zbpc_git_state WITH UNIQUE KEY docname.
    TYPES ty_models TYPE STANDARD TABLE OF uj_appl_id WITH DEFAULT KEY.

    CONSTANTS c_default_branch TYPE string VALUE 'main' ##NO_TEXT.
    CONSTANTS c_branch_prefix TYPE string VALUE 'refs/heads/' ##NO_TEXT.
    "! Folder of the EPM workbook libraries below each model (section 3).
    CONSTANTS c_webexcel_folder TYPE string VALUE 'EEXCEL' ##NO_TEXT.
    "! Recognised workbook extensions; the file service stores them as DOCTYPE.
    CONSTANTS c_workbook_types TYPE string VALUE 'XLSX XLSM XLS XLTX XLTM' ##NO_TEXT.

    "! Raises CX_UJ_NO_AUTH unless the user may access the environment.
    METHODS check_environment
      IMPORTING iv_environment TYPE uj_appset_id
      RAISING cx_uj_no_auth cx_uj_static_check.
    "! Models of the environment; also sets the BPC context for the file service.
    METHODS get_models
      IMPORTING iv_environment TYPE uj_appset_id
      RETURNING VALUE(rt_models) TYPE ty_models
      RAISING cx_uj_static_check.
    METHODS get_file_service
      IMPORTING iv_environment TYPE uj_appset_id
      RETURNING VALUE(ro_files) TYPE REF TO cl_ujf_file_service_mgr.
    METHODS get_workbook_types
      RETURNING VALUE(rt_types) TYPE string_table.
    "! Workbooks below \ROOT\WEBFOLDERS\<env>\<model>\EEXCEL\ of all models.
    METHODS list_workbooks
      IMPORTING iv_environment TYPE uj_appset_id
      RETURNING VALUE(rt_workbooks) TYPE ty_bpc_workbooks
      RAISING cx_uj_static_check.
    "! True for a repository path <model>/EEXCEL/.../<name>.<workbook type>.
    METHODS is_workbook_path
      IMPORTING iv_path TYPE string
      RETURNING VALUE(rv_workbook) TYPE abap_bool.
    "! BPC document name of a repository path, and the reverse.
    METHODS to_docname
      IMPORTING iv_environment TYPE uj_appset_id iv_path TYPE string
      RETURNING VALUE(rv_docname) TYPE uj_docname.
    METHODS to_path
      IMPORTING iv_environment TYPE uj_appset_id iv_docname TYPE csequence
      RETURNING VALUE(rv_path) TYPE string.
    "! Status of a workbook that is in BPC and in Git (section 6).
    METHODS compare
      IMPORTING io_files TYPE REF TO cl_ujf_file_service_mgr
                is_bpc TYPE ty_bpc_workbook
                iv_git_sha1 TYPE string
                is_state TYPE zbpc_git_state
                iv_synced TYPE abap_bool
      RETURNING VALUE(rv_status) TYPE string
      RAISING cx_uj_static_check zcx_abapgit_exception.
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

  METHOD get_overview.
    DATA lt_states TYPE ty_states.
    DATA ls_state TYPE zbpc_git_state.
    DATA lv_synced TYPE abap_bool.

    DATA(ls_config) = get_config( iv_environment ).
    DATA(lt_bpc) = list_workbooks( iv_environment ).
    DATA(ls_branch) = io_remote->read_branch( ls_config-branch ).
    rs_overview-branch_found = ls_branch-branch_found.
    rs_overview-commit = ls_branch-commit.
    SELECT * FROM zbpc_git_state
      WHERE appset = @iv_environment
      INTO TABLE @lt_states.
    DATA(lo_files) = get_file_service( iv_environment ).

    " Workbooks in BPC, with or without a Git counterpart
    LOOP AT lt_bpc INTO DATA(ls_bpc).
      DATA(ls_row) = VALUE ty_workbook(
        path       = ls_bpc-path
        model      = ls_bpc-model
        in_bpc     = abap_true
        changed_at = |{ ls_bpc-lstmod_date DATE = ISO } { ls_bpc-lstmod_time TIME = ISO }|
        changed_by = ls_bpc-lstmod_user
        size       = ls_bpc-size
        docname     = ls_bpc-docname
        lstmod_date = ls_bpc-lstmod_date
        lstmod_time = ls_bpc-lstmod_time ).
      CLEAR ls_state.
      READ TABLE lt_states INTO ls_state WITH TABLE KEY docname = ls_bpc-docname.
      lv_synced = boolc( sy-subrc = 0 ).
      READ TABLE ls_branch-files INTO DATA(ls_git) WITH TABLE KEY path = ls_bpc-path.
      IF sy-subrc <> 0.
        ls_row-status = COND #( WHEN lv_synced = abap_true THEN c_status-deleted_git
                                ELSE c_status-new_bpc ).
      ELSE.
        ls_row-status = compare( io_files = lo_files is_bpc = ls_bpc iv_git_sha1 = ls_git-sha1
                                 is_state = ls_state iv_synced = lv_synced ).
      ENDIF.
      APPEND ls_row TO rs_overview-workbooks.
    ENDLOOP.

    " Workbooks only in Git; other files such as README.md are not ours
    LOOP AT ls_branch-files INTO ls_git.
      IF line_exists( lt_bpc[ path = ls_git-path ] ) OR is_workbook_path( ls_git-path ) = abap_false.
        CONTINUE.
      ENDIF.
      DATA(lv_docname) = to_docname( iv_environment = iv_environment iv_path = ls_git-path ).
      APPEND VALUE #(
        path    = ls_git-path
        model   = substring_before( val = ls_git-path sub = '/' )
        docname = lv_docname
        status  = COND #( WHEN line_exists( lt_states[ docname = lv_docname ] )
                          THEN c_status-deleted_bpc ELSE c_status-new_git ) )
        TO rs_overview-workbooks.
    ENDLOOP.
    SORT rs_overview-workbooks BY path.
  ENDMETHOD.

  METHOD commit_workbooks.
    DATA lt_changes TYPE zcl_bpc_git_remote=>ty_changes.
    DATA lt_synced TYPE STANDARD TABLE OF zbpc_git_state WITH DEFAULT KEY.
    DATA lt_unsynced TYPE STANDARD TABLE OF uj_docname WITH DEFAULT KEY.
    DATA lv_document TYPE xstring.
    CLEAR: ev_error, ev_commit.

    IF condense( iv_message ) = ``.
      ev_error = 'Enter a commit message'.
      RETURN.
    ENDIF.
    IF it_paths IS INITIAL.
      ev_error = 'Select at least one workbook'.
      RETURN.
    ENDIF.

    " Statuses as of now, from the same head the commit builds on
    DATA(ls_config) = get_config( iv_environment ).
    DATA(ls_overview) = get_overview( iv_environment = iv_environment io_remote = io_remote ).
    IF ls_overview-branch_found = abap_false.
      ev_error = |Branch { ls_config-branch } does not exist in the repository yet. | &&
                 |Create it on the Git host first, for example by adding a README file.|.
      RETURN.
    ENDIF.
    IF ls_overview-commit <> to_lower( iv_expected_commit ).
      ev_error = |Branch { ls_config-branch } has new commits since you loaded the list. | &&
                 |Reload it and check the changes before committing.|.
      RETURN.
    ENDIF.

    DATA(lo_files) = get_file_service( iv_environment ).
    LOOP AT it_paths INTO DATA(lv_path).
      READ TABLE ls_overview-workbooks INTO DATA(ls_workbook) WITH KEY path = lv_path.
      IF sy-subrc <> 0.
        ev_error = |{ lv_path } is no longer in BPC or Git. Reload the list.|.
        RETURN.
      ENDIF.
      IF is_committable( ls_workbook-status ) = abap_false.
        ev_error = |{ lv_path } cannot be committed in its current status ({ ls_workbook-status }). Reload the list.|.
        RETURN.
      ENDIF.

      IF ls_workbook-status = c_status-deleted_bpc.
        APPEND VALUE #( path = lv_path delete = abap_true ) TO lt_changes.
        APPEND ls_workbook-docname TO lt_unsynced.
      ELSE.
        CLEAR lv_document.
        lo_files->get_document( EXPORTING i_docname = ls_workbook-docname i_retzip = abap_false
                                IMPORTING e_document_content = lv_document ).
        APPEND VALUE #( path = lv_path data = lv_document ) TO lt_changes.
        APPEND VALUE #( appset      = iv_environment
                        docname     = ls_workbook-docname
                        blob_sha1   = zcl_bpc_git_remote=>blob_sha1( lv_document )
                        lstmod_date = ls_workbook-lstmod_date
                        lstmod_time = ls_workbook-lstmod_time
                        synced_by   = sy-uname ) TO lt_synced.
      ENDIF.
    ENDLOOP.

    zcl_bpc_git_remote=>get_author( EXPORTING iv_user = sy-uname iv_git_user = iv_git_user
                                    IMPORTING ev_name = DATA(lv_author) ev_email = DATA(lv_email) ).
    ev_commit = io_remote->commit( it_changes = lt_changes
                                   iv_message = iv_message
                                   iv_author_name = lv_author
                                   iv_author_email = lv_email ).

    " Pushed: record what Git now holds for these documents
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    LOOP AT lt_synced ASSIGNING FIELD-SYMBOL(<ls_synced>).
      <ls_synced>-commit_sha1 = ev_commit.
      <ls_synced>-synced_at = lv_now.
    ENDLOOP.
    MODIFY zbpc_git_state FROM TABLE lt_synced.
    LOOP AT lt_unsynced INTO DATA(lv_docname).
      DELETE FROM zbpc_git_state WHERE appset = @iv_environment AND docname = @lv_docname.
    ENDLOOP.
    COMMIT WORK.
  ENDMETHOD.

  METHOD is_committable.
    rv_committable = xsdbool( iv_status = c_status-new_bpc
                           OR iv_status = c_status-modified_bpc
                           OR iv_status = c_status-differs
                           OR iv_status = c_status-deleted_bpc ).
  ENDMETHOD.

  METHOD compare.
    DATA lv_document TYPE xstring.
    DATA lv_bpc_sha1 TYPE string.
    IF iv_synced = abap_true
        AND is_bpc-lstmod_date = is_state-lstmod_date AND is_bpc-lstmod_time = is_state-lstmod_time.
      " Not touched in BPC since the last sync
      lv_bpc_sha1 = to_lower( is_state-blob_sha1 ).
    ELSE.
      io_files->get_document( EXPORTING i_docname = is_bpc-docname i_retzip = abap_false
                              IMPORTING e_document_content = lv_document ).
      lv_bpc_sha1 = zcl_bpc_git_remote=>blob_sha1( lv_document ).
    ENDIF.

    IF lv_bpc_sha1 = iv_git_sha1.
      rv_status = c_status-unchanged.
    ELSEIF iv_synced = abap_false.
      rv_status = c_status-differs.
    ELSE.
      DATA(lv_synced_sha1) = to_lower( is_state-blob_sha1 ).
      DATA(lv_bpc_changed) = xsdbool( lv_bpc_sha1 <> lv_synced_sha1 ).
      DATA(lv_git_changed) = xsdbool( iv_git_sha1 <> lv_synced_sha1 ).
      rv_status = COND #( WHEN lv_bpc_changed = abap_true AND lv_git_changed = abap_true
                          THEN c_status-conflict
                          WHEN lv_bpc_changed = abap_true THEN c_status-modified_bpc
                          ELSE c_status-modified_git ).
    ENDIF.
  ENDMETHOD.

  METHOD list_workbooks.
    DATA lt_documents TYPE ujf_t_doc.
    DATA lv_directory TYPE ujf_doctree-docname.
    DATA lv_doctype TYPE ujf_doc-doctype.

    DATA(lt_types) = get_workbook_types( ).
    DATA(lt_models) = get_models( iv_environment ).
    DATA(lo_files) = get_file_service( iv_environment ).
    LOOP AT lt_models INTO DATA(lv_model).
      lv_directory = |\\ROOT\\WEBFOLDERS\\{ iv_environment }\\{ lv_model }\\{ c_webexcel_folder }\\|.
      " The file service lists one document type at a time
      LOOP AT lt_types INTO DATA(lv_type).
        lv_doctype = lv_type.
        CLEAR lt_documents.
        TRY.
            lo_files->list_directory(
              EXPORTING i_dirname = lv_directory i_doctype = lv_doctype
                        i_sort = abap_false i_include_subfldrs = abap_true
              IMPORTING et_document_list = lt_documents ).
          CATCH cx_ujf_file_service_error.
            " A model without workbooks has no EEXCEL folder
            CLEAR lt_documents.
        ENDTRY.
        LOOP AT lt_documents INTO DATA(ls_document).
          INSERT VALUE #( path        = to_path( iv_environment = iv_environment
                                                 iv_docname = ls_document-docname )
                          docname     = ls_document-docname
                          model       = lv_model
                          lstmod_date = ls_document-lstmod_date
                          lstmod_time = ls_document-lstmod_time
                          lstmod_user = ls_document-lstmod_user
                          size        = ls_document-doc_length ) INTO TABLE rt_workbooks.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_workbook_path.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    IF lines( lt_parts ) < 3 OR lt_parts[ 2 ] <> c_webexcel_folder.
      RETURN.
    ENDIF.
    DATA(lv_type) = to_upper( substring_after( val = iv_path sub = '.' occ = -1 ) ).
    DATA(lt_types) = get_workbook_types( ).
    rv_workbook = boolc( line_exists( lt_types[ table_line = lv_type ] ) ).
  ENDMETHOD.

  METHOD get_workbook_types.
    SPLIT c_workbook_types AT space INTO TABLE rt_types.
  ENDMETHOD.

  METHOD to_docname.
    DATA(lv_relative) = iv_path.
    REPLACE ALL OCCURRENCES OF '/' IN lv_relative WITH '\'.
    rv_docname = |\\ROOT\\WEBFOLDERS\\{ iv_environment }\\{ lv_relative }|.
  ENDMETHOD.

  METHOD to_path.
    DATA(lv_prefix) = |\\ROOT\\WEBFOLDERS\\{ iv_environment }\\|.
    rv_path = iv_docname.
    IF strlen( rv_path ) > strlen( lv_prefix )
        AND substring( val = rv_path len = strlen( lv_prefix ) ) = lv_prefix.
      rv_path = substring( val = rv_path off = strlen( lv_prefix ) ).
    ENDIF.
    REPLACE ALL OCCURRENCES OF '\' IN rv_path WITH '/'.
  ENDMETHOD.

  METHOD get_models.
    DATA(ls_user) = VALUE uj0_s_user( user_id = sy-uname langu = sy-langu ).
    cl_uj_context=>set_cur_context( i_appset_id = iv_environment is_user = ls_user ).
    DATA(lo_manager) = cl_uja_bpc_admin_factory=>get_appset_manager(
      i_appset_id = iv_environment if_disable_security = abap_false ).
    lo_manager->get_applications( IMPORTING et_applications = DATA(lt_applications) ).
    LOOP AT lt_applications INTO DATA(ls_application).
      APPEND ls_application-application_id TO rt_models.
    ENDLOOP.
    SORT rt_models.
    DELETE ADJACENT DUPLICATES FROM rt_models.
  ENDMETHOD.

  METHOD get_file_service.
    DATA(ls_user) = VALUE uj0_s_user( user_id = sy-uname langu = sy-langu ).
    ro_files = cl_ujf_file_service_mgr=>factory( i_appset = iv_environment is_user = ls_user ).
  ENDMETHOD.

  METHOD check_environment.
    DATA(lt_environments) = get_environments( ).
    IF NOT line_exists( lt_environments[ table_line = iv_environment ] ).
      RAISE EXCEPTION TYPE cx_uj_no_auth.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
