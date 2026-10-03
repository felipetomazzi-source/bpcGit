"! bpcGit business logic: environments, the repository setup of an
"! environment (table ZBPC_GIT_REPO) and the Git status of its EPM workbooks,
"! logic scripts, transformation and conversion files, Data Manager packages
"! package links, security definitions and BPF designs (docs/SPEC.md).
CLASS zcl_bpc_git_service DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES ty_environments TYPE STANDARD TABLE OF uj_appset_id WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_workbook,
        "! Repository path, e.g. AGGR_OPEX/EEXCEL/REPORTS/X.XLSX,
        "! AGGR_OPEX/TEAM FILES/<team>/EEXCEL/REPORTS/X.XLSX or
        "! ADMINAPP/AGGR_OPEX/CLEAR_DATA.LGF
        path       TYPE string,
        "! One of c_kind
        kind       TYPE string,
        model      TYPE string,
        "! Team folder of a team workbook; initial for company (public) ones
        team       TYPE string,
        "! One of c_status
        status     TYPE string,
        in_bpc     TYPE abap_bool,
        "! Last change in BPC as YYYY-MM-DD HH:MM:SS, with user and size
        changed_at TYPE string,
        changed_by TYPE string,
        size       TYPE i,
        "! For commit and restore: BPC document and its last change, and the
        "! Git blob at the branch head (initial if not in Git)
        docname     TYPE uj_docname,
        git_sha1    TYPE string,
        lstmod_date TYPE uj_lstmod_date,
        lstmod_time TYPE uj_lstmod_time,
        "! Definitions are generated XML rather than BPC file-service documents
        generated   TYPE abap_bool,
        content     TYPE xstring,
        members     TYPE string_table,
      END OF ty_workbook,
      ty_workbooks TYPE STANDARD TABLE OF ty_workbook WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_restore_result,
        path    TYPE string,
        ok      TYPE abap_bool,
        message TYPE string,
      END OF ty_restore_result,
      ty_restore_results TYPE STANDARD TABLE OF ty_restore_result WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_overview,
        branch_found TYPE abap_bool,
        commit       TYPE string,
        workbooks    TYPE ty_workbooks,
        bpc_ms       TYPE i,
        git_ms       TYPE i,
        compare_ms   TYPE i,
      END OF ty_overview.
    CONSTANTS:
      BEGIN OF c_kind,
        workbook       TYPE string VALUE 'WORKBOOK',
        bpf            TYPE string VALUE 'BPF',
        team           TYPE string VALUE 'TEAM',
        taskprofile    TYPE string VALUE 'TASKPROFILE',
        dataprofile    TYPE string VALUE 'DATAPROFILE',
        script         TYPE string VALUE 'SCRIPT',
        transformation TYPE string VALUE 'TRANSFORMATION',
        conversion     TYPE string VALUE 'CONVERSION',
        package        TYPE string VALUE 'PACKAGE',
        link           TYPE string VALUE 'LINK',
      END OF c_kind.
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

    TYPES ty_models TYPE STANDARD TABLE OF uj_appl_id WITH DEFAULT KEY.
    METHODS available_models
      IMPORTING iv_environment TYPE uj_appset_id
      RETURNING VALUE(rt_models) TYPE ty_models
      RAISING cx_uj_no_auth cx_uj_static_check.
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
    "! Workbooks and logic scripts of the environment in BPC and in Git,
    "! each with its status.
    "! BPC content is only read when its hash is needed for the status.
    METHODS get_overview
      IMPORTING iv_environment TYPE uj_appset_id
                io_remote TYPE REF TO zcl_bpc_git_remote
                iv_individual TYPE abap_bool DEFAULT abap_false
                iv_kind TYPE string OPTIONAL
                iv_model TYPE string OPTIONAL
      RETURNING VALUE(rs_overview) TYPE ty_overview
      RAISING cx_uj_no_auth cx_uj_static_check zcx_abapgit_exception.
    METHODS get_history
      IMPORTING iv_environment TYPE uj_appset_id io_remote TYPE REF TO zcl_bpc_git_remote
                iv_path TYPE string iv_depth TYPE i DEFAULT 100
      RETURNING VALUE(rs_history) TYPE zcl_bpc_git_remote=>ty_history
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
    "! Writes the Git version of the given files into BPC (F5): creates or
    "! overwrites them, or deletes those deleted in Git, and records them as
    "! synced. Refuses the whole request, with ev_error, if the branch has moved
    "! past iv_expected_commit or a file's status does not allow a restore.
    "! Otherwise each file succeeds or fails on its own (et_results), e.g. when
    "! it is locked in BPC or a logic script does not pass BPC's validation.
    METHODS restore_files
      IMPORTING iv_environment TYPE uj_appset_id
                io_remote TYPE REF TO zcl_bpc_git_remote
                it_paths TYPE string_table
                iv_expected_commit TYPE string
                iv_version TYPE string OPTIONAL
                iv_depth TYPE i DEFAULT 100
      EXPORTING ev_error TYPE string
                et_results TYPE ty_restore_results
      RAISING cx_uj_no_auth cx_uj_static_check zcx_abapgit_exception.
    "! True for the statuses whose Git version may be restored: new or
    "! modified in Git, never synced but different, deleted in Git, and -
    "! discarding the BPC side, which the app warns about - modified or
    "! deleted in BPC and conflicts.
    CLASS-METHODS is_restorable
      IMPORTING iv_status TYPE string
      RETURNING VALUE(rv_restorable) TYPE abap_bool.
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
        kind        TYPE string,
        docname     TYPE uj_docname,
        model       TYPE string,
        lstmod_date TYPE uj_lstmod_date,
        lstmod_time TYPE uj_lstmod_time,
        lstmod_user TYPE string,
        size        TYPE i,
        "! Definitions are generated XML rather than BPC file-service documents
        generated   TYPE abap_bool,
        content     TYPE xstring,
      END OF ty_bpc_workbook,
      ty_bpc_workbooks TYPE SORTED TABLE OF ty_bpc_workbook WITH UNIQUE KEY path.
    TYPES ty_states TYPE SORTED TABLE OF zbpc_git_state WITH UNIQUE KEY docname.

    CONSTANTS c_default_branch TYPE string VALUE 'main' ##NO_TEXT.
    CONSTANTS c_branch_prefix TYPE string VALUE 'refs/heads/' ##NO_TEXT.
    "! Folder of the EPM workbook libraries below each model (section 3), and
    "! of the team folders, which each have their own EEXCEL libraries.
    CONSTANTS c_webexcel_folder TYPE string VALUE 'EEXCEL' ##NO_TEXT.
    CONSTANTS c_team_folder TYPE string VALUE 'TEAM FILES' ##NO_TEXT.
    "! Logic scripts: \ROOT\WEBFOLDERS\<env>\ADMINAPP\<model>\<name>.LGF. The
    "! .LGX files next to them are compiled by BPC and are not tracked.
    CONSTANTS c_script_folder TYPE string VALUE 'ADMINAPP' ##NO_TEXT.
    CONSTANTS c_script_type TYPE string VALUE 'LGF' ##NO_TEXT.
    "! Recognised workbook extensions; the file service stores them as DOCTYPE.
    CONSTANTS c_workbook_types TYPE string VALUE 'XLSX XLSM XLS XLTX XLTM' ##NO_TEXT.
    "! Data Manager files below <model>\DATAMANAGER\ (and a team's DATAMANAGER):
    "! a definition (.TDM, .CDM) and the Excel file it is maintained in.
    CONSTANTS c_dm_folder TYPE string VALUE 'DATAMANAGER' ##NO_TEXT.
    CONSTANTS c_transformation_folder TYPE string VALUE 'TRANSFORMATIONFILES' ##NO_TEXT.
    CONSTANTS c_conversion_folder TYPE string VALUE 'CONVERSIONFILES' ##NO_TEXT.
    CONSTANTS c_transformation_types TYPE string VALUE 'TDM XLS XLSX' ##NO_TEXT.
    CONSTANTS c_conversion_types TYPE string VALUE 'CDM XLS XLSX' ##NO_TEXT.
    "! Data Manager packages and package links are table entries, not documents.
    "! bpcGit writes them as XML files (section 3.4):
    "!   <model>/DATAMANAGER/PACKAGES/<group>/<package>.xml (teams: below
    "!   <model>/TEAM FILES/<team>/) and <model>/DATAMANAGER/PACKAGELINKS/<name>.xml
    CONSTANTS c_package_folder TYPE string VALUE 'PACKAGES' ##NO_TEXT.
    CONSTANTS c_link_folder TYPE string VALUE 'PACKAGELINKS' ##NO_TEXT.
    CONSTANTS c_xml_type TYPE string VALUE 'XML' ##NO_TEXT.
    "! Line separator of package scripts in UJD_INSTRUCTION2
    "! (CL_UJD_PACKAGE=>GC_INSTRUCTION_SEPARATOR)
    CONSTANTS c_script_separator TYPE string VALUE '<BR>' ##NO_TEXT.
    TYPES:
      BEGIN OF ty_package,
        group      TYPE uj_pack_grp_id,
        id         TYPE uj_package_id,
        team       TYPE uj_team_id,
        descr      TYPE uj_desc,
        type       TYPE uj_pack_type,
        user_group TYPE uj_user_group,
        chain      TYPE rspc_chain,
        "! False if the package runs its process chain's default script
        has_script TYPE abap_bool,
        script     TYPE string_table,
      END OF ty_package.
    TYPES:
      BEGIN OF ty_folder,
        "! Below \ROOT\WEBFOLDERS\<env>\, with trailing backslash
        folder     TYPE string,
        "! Document types to list, separated by spaces
        types      TYPE string,
        subfolders TYPE abap_bool,
      END OF ty_folder,
      ty_folders TYPE STANDARD TABLE OF ty_folder WITH DEFAULT KEY.

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
    "! Tracked files of all models (section 3), each with its kind:
    "! workbooks below <model>\EEXCEL\ and <model>\TEAM FILES\<team>\EEXCEL\,
    "! logic scripts in ADMINAPP\<model>\, transformation and conversion files
    "! below <model>\DATAMANAGER\ and <model>\TEAM FILES\<team>\DATAMANAGER\.
    METHODS list_workbooks
      IMPORTING iv_environment TYPE uj_appset_id
                iv_kind TYPE string OPTIONAL iv_model TYPE string OPTIONAL
      RETURNING VALUE(rt_workbooks) TYPE ty_bpc_workbooks
      RAISING cx_uj_static_check zcx_abapgit_exception.
    "! Kind (c_kind) of a repository path, initial if bpcGit does not track it:
    "!   <model>/EEXCEL/.../<name>.<workbook type>                   workbook
    "!   ADMINAPP/<model>/<name>.LGF                                 logic script
    "!   <model>/DATAMANAGER/TRANSFORMATIONFILES/.../<name>.TDM|XLS  transformation
    "!   <model>/DATAMANAGER/CONVERSIONFILES/.../<name>.CDM|XLS      conversion
    "! and the same below <model>/TEAM FILES/<team>/ instead of <model>/.
    METHODS matches_scope
      IMPORTING iv_path TYPE string iv_kind TYPE string
      RETURNING VALUE(rv_matches) TYPE abap_bool.
    METHODS selection_scope
      IMPORTING it_paths TYPE string_table
      EXPORTING ev_kind TYPE string ev_model TYPE string.
    METHODS history_paths
      IMPORTING iv_path TYPE string
      RETURNING VALUE(rt_paths) TYPE string_table.
    METHODS logical_path
      IMPORTING iv_path TYPE string it_files TYPE ty_workbooks
      RETURNING VALUE(rv_path) TYPE string.
    METHODS group_files
      IMPORTING it_files TYPE ty_workbooks
      RETURNING VALUE(rt_files) TYPE ty_workbooks.
    METHODS expand_selection
      IMPORTING it_paths TYPE string_table it_files TYPE ty_workbooks iv_restore TYPE abap_bool
      EXPORTING et_paths TYPE string_table ev_error TYPE string.
    METHODS get_kind
      IMPORTING iv_path TYPE string
      RETURNING VALUE(rv_kind) TYPE string.
    "! Packages and package links of a model, as generated files.
    METHODS list_packages
      IMPORTING iv_environment TYPE uj_appset_id iv_model TYPE uj_appl_id
      CHANGING ct_workbooks TYPE ty_bpc_workbooks.
    METHODS list_links
      IMPORTING iv_environment TYPE uj_appset_id iv_model TYPE uj_appl_id
      CHANGING ct_workbooks TYPE ty_bpc_workbooks.
    "! A package as bpcGit's XML file, one script line per element.
    METHODS package_to_xml
      IMPORTING is_package TYPE ty_package
      RETURNING VALUE(rv_xml) TYPE xstring.
    METHODS xml_element
      IMPORTING iv_name TYPE string iv_value TYPE clike
      RETURNING VALUE(rv_xml) TYPE string.
    "! Reads a package file; ev_error tells what is wrong with it.
    METHODS parse_package
      IMPORTING iv_xml TYPE xstring
      EXPORTING es_package TYPE ty_package
                ev_error TYPE string.
    "! Name of a package link, from the first NAME property of its XML.
    METHODS get_link_name
      IMPORTING iv_xml TYPE string
      RETURNING VALUE(rv_name) TYPE string.
    "! Link XML with its system-specific ID property set to iv_id (or blank).
    METHODS set_link_id
      IMPORTING iv_xml TYPE string iv_id TYPE csequence
      RETURNING VALUE(rv_xml) TYPE string.
    "! File or folder name for a BPC name; characters Git paths cannot hold become _.
    METHODS to_file_name
      IMPORTING iv_name TYPE csequence
      RETURNING VALUE(rv_name) TYPE string.
    "! Writes a package or package link from its XML into BPC through BPC's own
    "! API, or deletes it. Returns a message if that did not work.
    METHODS restore_package
      IMPORTING iv_environment TYPE uj_appset_id iv_model TYPE string
                iv_xml TYPE xstring iv_delete TYPE abap_bool iv_path TYPE string
      RETURNING VALUE(rv_message) TYPE string.
    METHODS restore_link
      IMPORTING iv_environment TYPE uj_appset_id iv_model TYPE string
                iv_xml TYPE xstring iv_delete TYPE abap_bool iv_path TYPE string
      RETURNING VALUE(rv_message) TYPE string.
    "! True if a space-separated type list contains the type.
    METHODS has_type
      IMPORTING iv_types TYPE string iv_type TYPE string
      RETURNING VALUE(rv_found) TYPE abap_bool.
    "! Model of a repository path of a tracked file.
    METHODS get_model
      IMPORTING iv_path TYPE string
      RETURNING VALUE(rv_model) TYPE string.
    "! Team folder of a repository path; initial for company workbooks.
    METHODS get_team
      IMPORTING iv_path TYPE string
      RETURNING VALUE(rv_team) TYPE string.
    "! BPC document name of a repository path, and the reverse.
    METHODS to_docname
      IMPORTING iv_environment TYPE uj_appset_id iv_path TYPE string
      RETURNING VALUE(rv_docname) TYPE uj_docname.
    METHODS to_path
      IMPORTING iv_environment TYPE uj_appset_id iv_docname TYPE csequence
      RETURNING VALUE(rv_path) TYPE string.
    "! Writes one file from Git into BPC; returns a message if it was not.
    METHODS restore_file
      IMPORTING io_files TYPE REF TO cl_ujf_file_service_mgr
                io_remote TYPE REF TO zcl_bpc_git_remote
                iv_environment TYPE uj_appset_id
                is_file TYPE ty_workbook
      RETURNING VALUE(rv_message) TYPE string
      RAISING cx_uj_static_check zcx_abapgit_exception.
    "! Creates the missing folders of a document name, level by level.
    METHODS ensure_folder
      IMPORTING io_files TYPE REF TO cl_ujf_file_service_mgr
                iv_environment TYPE uj_appset_id
                iv_docname TYPE uj_docname
      RAISING cx_uj_static_check.
    "! Validates a logic script with BPC (as its script editor does); returns
    "! the first error, or nothing if the script is valid.
    METHODS validate_script
      IMPORTING iv_environment TYPE uj_appset_id
                iv_model TYPE string
                iv_docname TYPE uj_docname
                iv_content TYPE xstring
      RETURNING VALUE(rv_error) TYPE string.
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

  METHOD available_models.
    check_environment( iv_environment ).
    rt_models = get_models( iv_environment ).
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
    DATA lv_start TYPE i.
    DATA lv_end TYPE i.
    GET RUN TIME FIELD lv_start.
    DATA(lt_bpc) = list_workbooks( iv_environment = iv_environment iv_kind = iv_kind iv_model = iv_model ).
    GET RUN TIME FIELD lv_end.
    rs_overview-bpc_ms = ( lv_end - lv_start ) / 1000.
    GET RUN TIME FIELD lv_start.
    DATA(ls_branch) = io_remote->read_branch( iv_branch = ls_config-branch
      iv_metadata_only = xsdbool( iv_individual = abap_false ) ).
    GET RUN TIME FIELD lv_end.
    rs_overview-git_ms = ( lv_end - lv_start ) / 1000.
    GET RUN TIME FIELD lv_start.
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
        kind       = ls_bpc-kind
        model      = ls_bpc-model
        team       = get_team( ls_bpc-path )
        in_bpc     = abap_true
        changed_at = COND #( WHEN ls_bpc-lstmod_date IS NOT INITIAL
                             THEN |{ ls_bpc-lstmod_date DATE = ISO } { ls_bpc-lstmod_time TIME = ISO }| )
        changed_by = ls_bpc-lstmod_user
        size       = ls_bpc-size
        docname     = ls_bpc-docname
        lstmod_date = ls_bpc-lstmod_date
        lstmod_time = ls_bpc-lstmod_time
        generated   = ls_bpc-generated
        content     = ls_bpc-content ).
      CLEAR ls_state.
      READ TABLE lt_states INTO ls_state WITH TABLE KEY docname = ls_bpc-docname.
      lv_synced = boolc( sy-subrc = 0 ).
      READ TABLE ls_branch-files INTO DATA(ls_git) WITH TABLE KEY path = ls_bpc-path.
      ls_row-git_sha1 = COND #( WHEN sy-subrc = 0 THEN ls_git-sha1 ).
      IF ls_row-git_sha1 IS INITIAL.
        ls_row-status = COND #( WHEN lv_synced = abap_true THEN c_status-deleted_git
                                ELSE c_status-new_bpc ).
      ELSE.
        ls_row-status = compare( io_files = lo_files is_bpc = ls_bpc iv_git_sha1 = ls_git-sha1
                                 is_state = ls_state iv_synced = lv_synced ).
      ENDIF.
      APPEND ls_row TO rs_overview-workbooks.
    ENDLOOP.

    DATA(lv_security_allowed) = zcl_bpc_git_security=>can_read( ).
    DATA(lv_bpf_allowed) = zcl_bpc_git_bpf=>can_read( ).
    " Files only in Git; untracked ones (README.md) are not ours
    LOOP AT ls_branch-files INTO ls_git.
      DATA(lv_kind) = get_kind( ls_git-path ).
      IF ( ls_git-path CP 'SECURITY/*' AND lv_security_allowed = abap_false )
          OR ( lv_kind = c_kind-bpf AND lv_bpf_allowed = abap_false ).
        CONTINUE.
      ENDIF.
      IF lv_kind IS INITIAL OR matches_scope( iv_path = ls_git-path iv_kind = iv_kind ) = abap_false
          OR ( iv_model IS NOT INITIAL AND get_model( ls_git-path ) <> iv_model )
          OR line_exists( lt_bpc[ path = ls_git-path ] ).
        CONTINUE.
      ENDIF.
      DATA(lv_docname) = to_docname( iv_environment = iv_environment iv_path = ls_git-path ).
      APPEND VALUE #(
        path    = ls_git-path
        kind    = lv_kind
        generated = xsdbool( ls_git-path CP 'SECURITY/*' OR lv_kind = c_kind-bpf )
        model   = get_model( ls_git-path )
        team    = get_team( ls_git-path )
        docname = lv_docname
        git_sha1 = ls_git-sha1
        status  = COND #( WHEN line_exists( lt_states[ docname = lv_docname ] )
                          THEN c_status-deleted_bpc ELSE c_status-new_git ) )
        TO rs_overview-workbooks.
    ENDLOOP.
    SORT rs_overview-workbooks BY path.
    IF iv_individual = abap_false.
      rs_overview-workbooks = group_files( rs_overview-workbooks ).
    ENDIF.
    GET RUN TIME FIELD lv_end.
    rs_overview-compare_ms = ( lv_end - lv_start ) / 1000.
  ENDMETHOD.

  METHOD matches_scope.
    DATA(lv_kind) = get_kind( iv_path ).
    IF lv_kind IS INITIAL.
      RETURN.
    ENDIF.
    IF iv_kind <> 'REPORT' AND iv_kind <> 'SCHEDULE' AND iv_kind <> 'OTHER'.
      rv_matches = xsdbool( iv_kind IS INITIAL OR iv_kind = lv_kind ).
      RETURN.
    ENDIF.
    IF lv_kind <> c_kind-workbook.
      RETURN.
    ENDIF.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    DATA(lv_library) = COND i( WHEN lt_parts[ 2 ] = c_team_folder THEN 5 ELSE 3 ).
    DATA(lv_subtype) = CONV string( 'OTHER' ).
    IF lines( lt_parts ) > lv_library.
      lv_subtype = SWITCH #( lt_parts[ lv_library ]
        WHEN 'REPORTS' THEN 'REPORT' WHEN 'INPUT SCHEDULES' THEN 'SCHEDULE' ELSE 'OTHER' ).
    ENDIF.
    rv_matches = xsdbool( iv_kind = lv_subtype ).
  ENDMETHOD.

  METHOD selection_scope.
    CLEAR: ev_kind, ev_model.
    DATA lv_first TYPE abap_bool VALUE abap_true.
    DATA lv_mixed_kind TYPE abap_bool.
    DATA lv_mixed_model TYPE abap_bool.
    LOOP AT it_paths INTO DATA(lv_path).
      DATA(lv_kind) = get_kind( lv_path ).
      DATA(lv_model) = get_model( lv_path ).
      IF lv_first = abap_true.
        ev_kind = lv_kind.
        ev_model = lv_model.
        lv_first = abap_false.
      ELSE.
        IF ev_kind <> lv_kind.
          lv_mixed_kind = abap_true.
        ENDIF.
        IF ev_model <> lv_model.
          lv_mixed_model = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.
    IF lv_mixed_kind = abap_true.
      CLEAR ev_kind.
    ENDIF.
    IF lv_mixed_model = abap_true.
      CLEAR ev_model.
    ENDIF.
  ENDMETHOD.

  METHOD history_paths.
    APPEND iv_path TO rt_paths.
    DATA(lv_kind) = get_kind( iv_path ).
    DATA(lv_ext) = to_upper( substring_after( val = iv_path sub = '.' occ = -1 ) ).
    IF ( lv_kind = c_kind-transformation OR lv_kind = c_kind-conversion )
        AND ( lv_ext = 'XLS' OR lv_ext = 'XLSX' ).
      DATA(lv_stem) = substring_before( val = iv_path sub = '.' occ = -1 ).
      APPEND lv_stem && COND string( WHEN lv_kind = c_kind-transformation THEN '.TDM' ELSE '.CDM' ) TO rt_paths.
    ENDIF.
  ENDMETHOD.

  METHOD get_history.
    DATA(ls_config) = get_config( iv_environment ).
    DATA(ls_overview) = get_overview( iv_environment = iv_environment io_remote = io_remote
      iv_kind = get_kind( iv_path ) iv_model = get_model( iv_path ) ).
    IF NOT line_exists( ls_overview-workbooks[ path = iv_path ] ).
      zcx_abapgit_exception=>raise( 'The selected item is no longer listed; reload the overview' ).
    ENDIF.
    rs_history = io_remote->history( iv_branch = ls_config-branch it_paths = history_paths( iv_path ) iv_depth = iv_depth ).
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
    selection_scope( EXPORTING it_paths = it_paths IMPORTING ev_kind = DATA(lv_scope_kind) ev_model = DATA(lv_scope_model) ).
    DATA(ls_overview) = get_overview( iv_environment = iv_environment io_remote = io_remote
      iv_individual = abap_true iv_kind = lv_scope_kind iv_model = lv_scope_model ).
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

    DATA lt_paths TYPE string_table.
    expand_selection( EXPORTING it_paths = it_paths it_files = ls_overview-workbooks iv_restore = abap_false
                       IMPORTING et_paths = lt_paths ev_error = ev_error ).
    IF ev_error IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(lo_files) = get_file_service( iv_environment ).
    LOOP AT lt_paths INTO DATA(lv_path).
      READ TABLE ls_overview-workbooks INTO DATA(ls_workbook) WITH KEY path = lv_path.
      IF ls_workbook-status = c_status-deleted_bpc.
        APPEND VALUE #( path = lv_path delete = abap_true ) TO lt_changes.
        APPEND ls_workbook-docname TO lt_unsynced.
      ELSE.
        CLEAR lv_document.
        IF ls_workbook-generated = abap_true.
          lv_document = ls_workbook-content.
        ELSE.
          lo_files->get_document( EXPORTING i_docname = ls_workbook-docname i_retzip = abap_false
                                  IMPORTING e_document_content = lv_document ).
        ENDIF.
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

  METHOD restore_files.
    CLEAR: ev_error, et_results.
    IF it_paths IS INITIAL.
      ev_error = 'Select at least one file'.
      RETURN.
    ENDIF.

    " Statuses as of now, from the head whose content is restored
    DATA(ls_config) = get_config( iv_environment ).
    selection_scope( EXPORTING it_paths = it_paths IMPORTING ev_kind = DATA(lv_scope_kind) ev_model = DATA(lv_scope_model) ).
    DATA(ls_overview) = get_overview( iv_environment = iv_environment io_remote = io_remote
      iv_individual = abap_true iv_kind = lv_scope_kind iv_model = lv_scope_model ).
    IF ls_overview-branch_found = abap_false.
      ev_error = |Branch { ls_config-branch } does not exist in the repository.|.
      RETURN.
    ENDIF.
    IF ls_overview-commit <> to_lower( iv_expected_commit ).
      ev_error = |Branch { ls_config-branch } has new commits since you loaded the list. | &&
                 |Reload it and check the changes before restoring.|.
      RETURN.
    ENDIF.

    DATA(lt_head_files) = ls_overview-workbooks.
    IF iv_version IS NOT INITIAL.
      IF lines( it_paths ) <> 1.
        ev_error = 'Select one item to restore from history'.
        RETURN.
      ENDIF.
      DATA(lv_history_path) = logical_path( iv_path = it_paths[ 1 ] it_files = ls_overview-workbooks ).
      DATA(lt_current_groups) = group_files( ls_overview-workbooks ).
      IF NOT line_exists( lt_current_groups[ path = lv_history_path ] ).
        ev_error = 'The selected item is no longer listed; reload the overview'.
        RETURN.
      ENDIF.
      DATA(lt_history_paths) = history_paths( lv_history_path ).
      DATA(ls_history) = io_remote->history( iv_branch = ls_config-branch it_paths = lt_history_paths iv_depth = iv_depth ).
      IF ls_history-head <> ls_overview-commit.
        ev_error = 'The branch changed; reload history before restoring'.
        RETURN.
      ENDIF.
      READ TABLE ls_history-versions INTO DATA(ls_version) WITH KEY commit = iv_version.
      IF sy-subrc <> 0 OR ls_version-complete = abap_false.
        ev_error = 'This version is unavailable or lacks a companion workbook/definition; choose a complete version'.
        RETURN.
      ENDIF.
      DATA(ls_snapshot) = io_remote->read_version( iv_version ).
      DATA lt_snapshot_files TYPE ty_workbooks.
      DATA lv_operations TYPE i.
      LOOP AT lt_history_paths INTO DATA(lv_snapshot_path).
        READ TABLE ls_overview-workbooks INTO DATA(ls_snapshot_file) WITH KEY path = lv_snapshot_path.
        IF sy-subrc <> 0.
          ls_snapshot_file = VALUE #( path = lv_snapshot_path kind = get_kind( lv_snapshot_path )
            model = get_model( lv_snapshot_path ) team = get_team( lv_snapshot_path )
            docname = to_docname( iv_environment = iv_environment iv_path = lv_snapshot_path ) ).
        ENDIF.
        READ TABLE ls_snapshot-files INTO DATA(ls_snapshot_git) WITH KEY path = lv_snapshot_path.
        IF sy-subrc = 0.
          ls_snapshot_file-git_sha1 = ls_snapshot_git-sha1.
          ls_snapshot_file-status = COND #( WHEN ls_snapshot_file-in_bpc = abap_true
            THEN c_status-modified_git ELSE c_status-new_git ).
        ELSEIF ls_snapshot_file-in_bpc = abap_true.
          CLEAR ls_snapshot_file-git_sha1.
          ls_snapshot_file-status = c_status-deleted_git.
        ELSE.
          ls_snapshot_file-status = c_status-unchanged.
        ENDIF.
        IF lv_snapshot_path CP 'SECURITY/*' OR get_kind( lv_snapshot_path ) = c_kind-bpf.
          ls_snapshot_file-generated = abap_true.
        ENDIF.
        IF ls_snapshot_file-status <> c_status-unchanged.
          lv_operations = lv_operations + 1.
        ENDIF.
        APPEND ls_snapshot_file TO lt_snapshot_files.
      ENDLOOP.
      ls_overview-workbooks = lt_snapshot_files.
      IF lv_operations = 0.
        APPEND VALUE #( path = lv_history_path ok = abap_true ) TO et_results.
        RETURN.
      ENDIF.
    ENDIF.

    DATA lt_paths TYPE string_table.
    expand_selection( EXPORTING it_paths = it_paths it_files = ls_overview-workbooks iv_restore = abap_true
                       IMPORTING et_paths = lt_paths ev_error = ev_error ).
    IF ev_error IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(lt_groups) = group_files( ls_overview-workbooks ).
    DATA(lo_files) = get_file_service( iv_environment ).
    IF line_exists( ls_overview-workbooks[ kind = c_kind-script ] ).
      LOOP AT lt_paths INTO DATA(lv_check_path).
        READ TABLE ls_overview-workbooks INTO DATA(ls_check) WITH KEY path = lv_check_path.
        IF ls_check-kind = c_kind-script.
          cl_uj_context=>get_cur_context( )->check_task_access( i_task_name = uje0_cs_task_id-p0008 ).
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
    DATA lt_done TYPE string_table.
    LOOP AT it_paths INTO DATA(lv_path).
      DATA(lv_logical) = logical_path( iv_path = lv_path it_files = ls_overview-workbooks ).
      IF line_exists( lt_done[ table_line = lv_logical ] ).
        CONTINUE.
      ENDIF.
      APPEND lv_logical TO lt_done.
      READ TABLE lt_groups INTO DATA(ls_group) WITH KEY path = lv_logical.
      DATA(lv_message) = ``.
      TRY.
          " Check every affected lock before writing either member of a pair.
          LOOP AT ls_group-members INTO DATA(lv_member).
            READ TABLE ls_overview-workbooks INTO DATA(ls_file) WITH KEY path = lv_member.
            IF ls_file-status = c_status-unchanged.
              CONTINUE.
            ENDIF.
            IF ls_file-in_bpc = abap_true AND ls_file-generated = abap_false.
              IF lo_files->check_document_lock( ls_file-docname ) = abap_true.
                lv_message = |{ lv_member } is locked in BPC. Close it and try again.|.
                EXIT.
              ENDIF.
            ENDIF.
          ENDLOOP.
          IF lv_message IS INITIAL.
            LOOP AT ls_group-members INTO lv_member.
              READ TABLE ls_overview-workbooks INTO ls_file WITH KEY path = lv_member.
              IF ls_file-status = c_status-unchanged.
                CONTINUE.
              ENDIF.
              lv_message = restore_file( io_files = lo_files io_remote = io_remote
                                         iv_environment = iv_environment is_file = ls_file ).
              IF lv_message IS NOT INITIAL.
                lv_message = |{ lv_member }: { lv_message }|.
                EXIT.
              ENDIF.
              IF ls_file-status = c_status-deleted_git AND iv_version IS INITIAL.
                DELETE FROM zbpc_git_state WHERE appset = @iv_environment AND docname = @ls_file-docname.
              ELSE.
                DATA ls_attributes TYPE ujf_doc.
                CLEAR ls_attributes.
                IF ls_file-status <> c_status-deleted_git AND ls_file-generated = abap_false
                    AND ls_file-kind <> c_kind-package AND ls_file-kind <> c_kind-link.
                  IF ls_file-kind = c_kind-transformation OR ls_file-kind = c_kind-conversion.
                    DATA lv_actual TYPE xstring.
                    lo_files->get_document( EXPORTING i_docname = ls_file-docname i_retzip = abap_false
                                            IMPORTING e_document_content = lv_actual ).
                    IF zcl_bpc_git_remote=>blob_sha1( lv_actual ) <> ls_file-git_sha1.
                      lv_message = |{ lv_member }: BPC content does not match Git after restore.|.
                      EXIT.
                    ENDIF.
                  ENDIF.
                  lo_files->get_document_attributes( EXPORTING i_docname = ls_file-docname
                                                     IMPORTING es_document_attributes = ls_attributes ).
                ENDIF.
                DATA(ls_state) = VALUE zbpc_git_state( appset = iv_environment docname = ls_file-docname
                  blob_sha1 = ls_file-git_sha1 commit_sha1 = ls_overview-commit
                  lstmod_date = ls_attributes-lstmod_date lstmod_time = ls_attributes-lstmod_time synced_by = sy-uname ).
                GET TIME STAMP FIELD ls_state-synced_at.
                IF iv_version IS NOT INITIAL.
                  " History restore changes BPC relative to the current Git head.
                  " Do not mark the older snapshot as synchronized with that head.
                  DATA ls_head_file TYPE ty_workbook.
                  CLEAR ls_head_file.
                  READ TABLE lt_head_files INTO ls_head_file WITH KEY path = ls_file-path.
                  ls_state-blob_sha1 = ls_head_file-git_sha1.
                  CLEAR: ls_state-lstmod_date, ls_state-lstmod_time.
                ENDIF.
                IF ls_state-blob_sha1 IS INITIAL.
                  DELETE FROM zbpc_git_state WHERE appset = @iv_environment AND docname = @ls_file-docname.
                ELSE.
                  MODIFY zbpc_git_state FROM ls_state.
                ENDIF.
              ENDIF.
            ENDLOOP.
          ENDIF.
        CATCH cx_root INTO DATA(lx_restore).
          lv_message = lx_restore->get_text( ).
      ENDTRY.
      IF lv_message IS INITIAL.
        COMMIT WORK.
      ELSE.
        " Workbook, definition, and sync records succeed or roll back together.
        ROLLBACK WORK.
      ENDIF.
      APPEND VALUE #( path = lv_logical ok = xsdbool( lv_message IS INITIAL ) message = lv_message ) TO et_results.
    ENDLOOP.
  ENDMETHOD.

  METHOD restore_file.
    DATA lv_locked TYPE uj_flg.
    DATA lv_content TYPE xstring.

    IF is_file-kind = c_kind-bpf.
      DATA(lv_bpf_delete) = xsdbool( is_file-status = c_status-deleted_git ).
      DATA(lv_bpf_xml) = COND xstring( WHEN lv_bpf_delete = abap_true THEN is_file-content
        ELSE io_remote->get_content( is_file-git_sha1 ) ).
      rv_message = zcl_bpc_git_bpf=>restore( iv_environment = iv_environment iv_path = is_file-path
        iv_xml = lv_bpf_xml iv_delete = lv_bpf_delete ).
      RETURN.
    ENDIF.
    IF is_file-path CP 'SECURITY/*'.
      DATA(lv_security_delete) = xsdbool( is_file-status = c_status-deleted_git ).
      DATA(lv_security_xml) = COND xstring( WHEN lv_security_delete = abap_true THEN is_file-content
        ELSE io_remote->get_content( is_file-path ) ).
      rv_message = zcl_bpc_git_security=>restore( iv_environment = iv_environment iv_path = is_file-path
        iv_xml = lv_security_xml iv_delete = lv_security_delete ).
      RETURN.
    ENDIF.
    IF is_file-kind = c_kind-package OR is_file-kind = c_kind-link.
      " To delete, the BPC version tells what; otherwise the Git version is written
      DATA(lv_delete) = xsdbool( is_file-status = c_status-deleted_git ).
      DATA(lv_xml) = COND xstring( WHEN lv_delete = abap_true THEN is_file-content
                                   ELSE io_remote->get_content( is_file-path ) ).
      IF is_file-kind = c_kind-package.
        rv_message = restore_package( iv_environment = iv_environment iv_model = is_file-model
                                      iv_xml = lv_xml iv_delete = lv_delete iv_path = is_file-path ).
      ELSE.
        rv_message = restore_link( iv_environment = iv_environment iv_model = is_file-model
                                   iv_xml = lv_xml iv_delete = lv_delete iv_path = is_file-path ).
      ENDIF.
      RETURN.
    ENDIF.

    TRY.
        " Never overwrite a document whose lock flag is set (e.g. open for editing)
        IF is_file-in_bpc = abap_true.
          lv_locked = io_files->check_document_lock( is_file-docname ).
          IF lv_locked = abap_true.
            rv_message = 'Locked in BPC, e.g. open for editing. Try again later.'.
            RETURN.
          ENDIF.
        ENDIF.

        IF is_file-status = c_status-deleted_git.
          io_files->delete_document( is_file-docname ).
          RETURN.
        ENDIF.

        lv_content = io_remote->get_content( is_file-path ).
        IF is_file-kind = c_kind-script.
          " BPC reads scripts as lines split at CRLF; files edited elsewhere may use LF
          DATA(lv_text) = cl_abap_codepage=>convert_from( lv_content ).
          REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_text
            WITH cl_abap_char_utilities=>newline.
          REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_text
            WITH cl_abap_char_utilities=>cr_lf.
          lv_content = cl_abap_codepage=>convert_to( lv_text ).
          rv_message = validate_script( iv_environment = iv_environment iv_model = is_file-model
                                        iv_docname = is_file-docname iv_content = lv_content ).
          IF rv_message IS NOT INITIAL.
            rv_message = |Not valid in BPC: { rv_message }|.
            RETURN.
          ENDIF.
        ENDIF.

        IF is_file-in_bpc = abap_false.
          ensure_folder( io_files = io_files iv_environment = iv_environment iv_docname = is_file-docname ).
        ENDIF.
        " No LOCK_DOCUMENT around the write: BPC's lock is only the flag
        " UJF_DOC-LOCK_IND, and PUT_DOCUMENT refuses any set flag, including
        " the caller's own. Locking also rewrites the last-change stamp.
        io_files->put_document( i_docname = is_file-docname i_doc_content = lv_content
                                i_compression = abap_false i_splice_zip = abap_false ).
      CATCH cx_ujf_file_service_error INTO DATA(lx_file).
        rv_message = lx_file->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD ensure_folder.
    DATA lv_exists TYPE uj_flg.
    DATA lv_folder TYPE ujf_doctree-docname.
    DATA lt_parts TYPE string_table.
    " \ROOT\WEBFOLDERS\<env>\ exists; create each level below it that is missing
    DATA(lv_root) = |\\ROOT\\WEBFOLDERS\\{ iv_environment }\\|.
    DATA(lv_relative) = substring( val = iv_docname off = strlen( lv_root ) ).
    SPLIT lv_relative AT '\' INTO TABLE lt_parts.
    DELETE lt_parts INDEX lines( lt_parts ).  " the file name
    DATA(lv_path) = lv_root.
    LOOP AT lt_parts INTO DATA(lv_part).
      lv_path = |{ lv_path }{ lv_part }\\|.
      lv_folder = lv_path.
      io_files->check_directory_exist( EXPORTING i_dirname = lv_folder i_appset_id = iv_environment
                                       IMPORTING e_result = lv_exists ).
      IF lv_exists = abap_false.
        io_files->create_directory( lv_folder ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validate_script.
    DATA lt_logic TYPE ujk_t_script_logic_scripttable.
    DATA lt_lines TYPE string_table.
    DATA lt_messages TYPE uj0_t_message.
    DATA lv_fm_error TYPE string.
    SPLIT cl_abap_codepage=>convert_from( iv_content ) AT cl_abap_char_utilities=>cr_lf INTO TABLE lt_lines.
    LOOP AT lt_lines INTO DATA(lv_line).
      APPEND VALUE #( original_line = sy-tabix original_file = iv_docname content = lv_line ) TO lt_logic.
    ENDLOOP.
    cl_ujk_script_logic=>validate( EXPORTING i_appset = iv_environment
                                             i_application = CONV uj_appl_id( iv_model )
                                             i_user = CONV uj_user_id( sy-uname )
                                             i_logic = lt_logic
                                             i_lgf = iv_docname
                                   IMPORTING e_fm_error_message = lv_fm_error
                                             et_message = lt_messages ).
    LOOP AT lt_messages INTO DATA(ls_message) WHERE msgty CA 'EAX'.
      rv_error = ls_message-message.
      RETURN.
    ENDLOOP.
    rv_error = lv_fm_error.
  ENDMETHOD.

  METHOD is_restorable.
    rv_restorable = xsdbool( iv_status = c_status-modified_git
                          OR iv_status = c_status-new_git
                          OR iv_status = c_status-differs
                          OR iv_status = c_status-deleted_git
                          OR iv_status = c_status-modified_bpc
                          OR iv_status = c_status-deleted_bpc
                          OR iv_status = c_status-conflict ).
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
    IF is_bpc-generated = abap_true.
      " No BPC timestamp to rely on; the generated file is at hand
      lv_bpc_sha1 = zcl_bpc_git_remote=>blob_sha1( is_bpc-content ).
    ELSEIF iv_synced = abap_true
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
    DATA lt_types TYPE string_table.
    DATA lv_directory TYPE ujf_doctree-docname.
    DATA lv_doctype TYPE ujf_doc-doctype.

    DATA(lt_models) = get_models( iv_environment ).
    DATA(lv_security_scope) = xsdbool( iv_kind = c_kind-team OR iv_kind = c_kind-taskprofile
      OR iv_kind = c_kind-dataprofile ).
    IF lv_security_scope = abap_true AND iv_model IS NOT INITIAL.
      RAISE EXCEPTION TYPE cx_uj_static_check.
    ENDIF.
    IF iv_model IS INITIAL AND ( iv_kind IS INITIAL OR lv_security_scope = abap_true ).
      DATA(lt_security) = zcl_bpc_git_security=>list( iv_environment = iv_environment iv_kind = iv_kind ).
      LOOP AT lt_security INTO DATA(ls_security).
        INSERT VALUE #( path = ls_security-path kind = ls_security-kind
          docname = to_docname( iv_environment = iv_environment iv_path = ls_security-path )
          generated = abap_true content = ls_security-content size = xstrlen( ls_security-content ) ) INTO TABLE rt_workbooks.
      ENDLOOP.
    ENDIF.
    IF lv_security_scope = abap_true.
      RETURN.
    ENDIF.
    IF iv_model IS NOT INITIAL.
      IF NOT line_exists( lt_models[ table_line = iv_model ] ).
        RAISE EXCEPTION TYPE cx_uj_no_auth.
      ENDIF.
      DELETE lt_models WHERE table_line <> iv_model.
    ENDIF.
    IF iv_kind IS INITIAL OR iv_kind = c_kind-bpf.
      IF zcl_bpc_git_bpf=>can_read( ) = abap_true.
        DATA(lt_bpf) = zcl_bpc_git_bpf=>list( iv_environment = iv_environment iv_model = iv_model ).
        LOOP AT lt_bpf INTO DATA(ls_bpf).
          IF NOT line_exists( lt_models[ table_line = ls_bpf-model ] ).
            CONTINUE.
          ENDIF.
          INSERT VALUE #( path = ls_bpf-path kind = c_kind-bpf model = ls_bpf-model
            docname = to_docname( iv_environment = iv_environment iv_path = ls_bpf-path )
            generated = abap_true content = ls_bpf-content size = xstrlen( ls_bpf-content ) ) INTO TABLE rt_workbooks.
        ENDLOOP.
      ELSEIF iv_kind = c_kind-bpf.
        RAISE EXCEPTION TYPE cx_uj_no_auth.
      ENDIF.
    ENDIF.
    IF iv_kind = c_kind-bpf.
      RETURN.
    ENDIF.
    DATA(lo_files) = get_file_service( iv_environment ).
    LOOP AT lt_models INTO DATA(lv_model).
      " Folders to list; get_kind decides what in them is tracked. Team folders
      " are listed as a whole, as their libraries sit one level down.
      DATA(lv_model_folder) = |{ lv_model }\\|.
      DATA lt_folders TYPE ty_folders.
      CLEAR lt_folders.
      DATA(lv_workbook_scope) = xsdbool( iv_kind = c_kind-workbook OR iv_kind = 'REPORT'
        OR iv_kind = 'SCHEDULE' OR iv_kind = 'OTHER' ).
      IF iv_kind IS INITIAL OR lv_workbook_scope = abap_true.
        APPEND VALUE #( folder = lv_model_folder && c_webexcel_folder && `\` &&
          COND string( WHEN iv_kind = 'REPORT' THEN `REPORTS\`
            WHEN iv_kind = 'SCHEDULE' THEN `INPUT SCHEDULES\` )
          types = c_workbook_types subfolders = abap_true ) TO lt_folders.
      ENDIF.
      DATA(lv_team_types) = COND string( WHEN lv_workbook_scope = abap_true THEN c_workbook_types
        WHEN iv_kind = c_kind-transformation THEN c_transformation_types
        WHEN iv_kind = c_kind-conversion THEN c_conversion_types
        WHEN iv_kind IS INITIAL THEN |{ c_workbook_types } { c_transformation_types } { c_conversion_types }| ).
      IF lv_team_types IS NOT INITIAL.
        APPEND VALUE #( folder = lv_model_folder && c_team_folder && `\`
          types = lv_team_types subfolders = abap_true ) TO lt_folders.
      ENDIF.
      IF iv_kind IS INITIAL OR iv_kind = c_kind-transformation.
        APPEND VALUE #( folder = lv_model_folder && c_dm_folder && `\` && c_transformation_folder && `\`
          types = c_transformation_types subfolders = abap_true ) TO lt_folders.
      ENDIF.
      IF iv_kind IS INITIAL OR iv_kind = c_kind-conversion.
        APPEND VALUE #( folder = lv_model_folder && c_dm_folder && `\` && c_conversion_folder && `\`
          types = c_conversion_types subfolders = abap_true ) TO lt_folders.
      ENDIF.
      IF iv_kind IS INITIAL OR iv_kind = c_kind-script.
        APPEND VALUE #( folder = |{ c_script_folder }\\{ lv_model }\\|
          types = c_script_type subfolders = abap_false ) TO lt_folders.
      ENDIF.

      LOOP AT lt_folders INTO DATA(ls_folder).
        lv_directory = |\\ROOT\\WEBFOLDERS\\{ iv_environment }\\{ ls_folder-folder }|.
        SPLIT ls_folder-types AT space INTO TABLE lt_types.
        SORT lt_types.
        DELETE ADJACENT DUPLICATES FROM lt_types.
        " The file service lists one document type at a time
        LOOP AT lt_types INTO DATA(lv_type).
          lv_doctype = lv_type.
          CLEAR lt_documents.
          TRY.
              lo_files->list_directory(
                EXPORTING i_dirname = lv_directory i_doctype = lv_doctype
                          i_sort = abap_false i_include_subfldrs = ls_folder-subfolders
                IMPORTING et_document_list = lt_documents ).
            CATCH cx_ujf_file_service_error.
              " A model without such files has no such folder
              CLEAR lt_documents.
          ENDTRY.
          LOOP AT lt_documents INTO DATA(ls_document).
            DATA(lv_path) = to_path( iv_environment = iv_environment iv_docname = ls_document-docname ).
            DATA(lv_kind) = get_kind( lv_path ).
            IF lv_kind IS INITIAL OR matches_scope( iv_path = lv_path iv_kind = iv_kind ) = abap_false.
              CONTINUE.
            ENDIF.
            INSERT VALUE #( path        = lv_path
                            kind        = lv_kind
                            docname     = ls_document-docname
                            model       = lv_model
                            lstmod_date = ls_document-lstmod_date
                            lstmod_time = ls_document-lstmod_time
                            lstmod_user = ls_document-lstmod_user
                            size        = ls_document-doc_length ) INTO TABLE rt_workbooks.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.

      IF iv_kind IS INITIAL OR iv_kind = c_kind-package.
        list_packages( EXPORTING iv_environment = iv_environment iv_model = lv_model
                       CHANGING ct_workbooks = rt_workbooks ).
      ENDIF.
      IF iv_kind IS INITIAL OR iv_kind = c_kind-link.
        list_links( EXPORTING iv_environment = iv_environment iv_model = lv_model
                    CHANGING ct_workbooks = rt_workbooks ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD logical_path.
    rv_path = iv_path.
    DATA(lv_kind) = get_kind( iv_path ).
    IF lv_kind <> c_kind-transformation AND lv_kind <> c_kind-conversion.
      RETURN.
    ENDIF.
    DATA(lv_ext) = to_upper( substring_after( val = iv_path sub = '.' occ = -1 ) ).
    IF lv_ext <> 'TDM' AND lv_ext <> 'CDM'.
      RETURN.
    ENDIF.
    DATA(lv_stem) = substring_before( val = iv_path sub = '.' occ = -1 ).
    DATA(lv_xls) = lv_stem && '.XLS'.
    DATA(lv_xlsx) = lv_stem && '.XLSX'.
    IF line_exists( it_files[ path = lv_xls ] ).
      rv_path = lv_xls.
    ELSEIF line_exists( it_files[ path = lv_xlsx ] ).
      rv_path = lv_xlsx.
    ENDIF.
    " Keep an orphan definition visible when no workbook exists on either side.
  ENDMETHOD.

  METHOD group_files.
    LOOP AT it_files INTO DATA(ls_file).
      DATA(lv_path) = logical_path( iv_path = ls_file-path it_files = it_files ).
      READ TABLE rt_files ASSIGNING FIELD-SYMBOL(<ls_group>) WITH KEY path = lv_path.
      IF sy-subrc <> 0.
        READ TABLE it_files INTO DATA(ls_primary) WITH KEY path = lv_path.
        APPEND ls_primary TO rt_files ASSIGNING <ls_group>.
        CLEAR <ls_group>-members.
      ENDIF.
      APPEND ls_file-path TO <ls_group>-members.
    ENDLOOP.
    LOOP AT rt_files ASSIGNING <ls_group>.
      DATA(lv_bpc) = abap_false.
      DATA(lv_git) = abap_false.
      DATA(lv_differs) = abap_false.
      DATA(lv_first) = ``.
      DATA(lv_mixed) = abap_false.
      DATA(lv_unchanged) = abap_false.
      LOOP AT <ls_group>-members INTO DATA(lv_member).
        READ TABLE it_files INTO ls_file WITH KEY path = lv_member.
        IF ls_file-status = c_status-unchanged.
          lv_unchanged = abap_true.
          CONTINUE.
        ENDIF.
        IF lv_first IS INITIAL.
          lv_first = ls_file-status.
        ELSEIF lv_first <> ls_file-status.
          lv_mixed = abap_true.
        ENDIF.
        CASE ls_file-status.
          WHEN c_status-modified_bpc OR c_status-new_bpc OR c_status-deleted_bpc.
            lv_bpc = abap_true.
          WHEN c_status-modified_git OR c_status-new_git OR c_status-deleted_git.
            lv_git = abap_true.
          WHEN c_status-conflict.
            lv_bpc = abap_true.
            lv_git = abap_true.
          WHEN c_status-differs.
            lv_differs = abap_true.
        ENDCASE.
      ENDLOOP.
      <ls_group>-status = COND #( WHEN lv_bpc = abap_true AND lv_git = abap_true THEN c_status-conflict
        WHEN lv_differs = abap_true AND lv_git = abap_true THEN c_status-conflict
        WHEN lv_differs = abap_true THEN c_status-differs
        WHEN lv_first IS INITIAL THEN c_status-unchanged
        WHEN lv_mixed = abap_false AND lv_unchanged = abap_false THEN lv_first
        WHEN lv_bpc = abap_true THEN c_status-modified_bpc ELSE c_status-modified_git ).
    ENDLOOP.
    SORT rt_files BY path.
  ENDMETHOD.

  METHOD expand_selection.
    CLEAR: et_paths, ev_error.
    DATA(lt_groups) = group_files( it_files ).
    LOOP AT it_paths INTO DATA(lv_path).
      DATA(lv_logical) = logical_path( iv_path = lv_path it_files = it_files ).
      READ TABLE lt_groups INTO DATA(ls_group) WITH KEY path = lv_logical.
      IF sy-subrc <> 0.
        ev_error = |{ lv_path } is no longer in BPC or Git. Reload the list.|.
        RETURN.
      ENDIF.
      DATA(lv_allowed) = COND abap_bool( WHEN iv_restore = abap_true THEN is_restorable( ls_group-status )
                                        ELSE is_committable( ls_group-status ) ).
      IF lv_allowed = abap_false.
        ev_error = |{ lv_logical } cannot be processed in its current status ({ ls_group-status }). Reload the list.|.
        RETURN.
      ENDIF.
      LOOP AT ls_group-members INTO DATA(lv_member).
        READ TABLE it_files INTO DATA(ls_file) WITH KEY path = lv_member.
        IF ls_file-status = c_status-unchanged OR line_exists( et_paths[ table_line = lv_member ] ).
          CONTINUE.
        ENDIF.
        lv_allowed = COND #( WHEN iv_restore = abap_true THEN is_restorable( ls_file-status )
                             ELSE is_committable( ls_file-status ) ).
        IF lv_allowed = abap_false.
          ev_error = |{ lv_logical }: its companion cannot be processed ({ ls_file-status }). Reload the list.|.
          RETURN.
        ENDIF.
        APPEND lv_member TO et_paths.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_kind.
    rv_kind = zcl_bpc_git_bpf=>get_kind( iv_path ).
    IF rv_kind IS NOT INITIAL.
      RETURN.
    ENDIF.
    IF iv_path CP 'SECURITY/*'.
      rv_kind = zcl_bpc_git_security=>get_kind( iv_path ).
      RETURN.
    ENDIF.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    DATA(lv_count) = lines( lt_parts ).
    DATA(lv_type) = to_upper( substring_after( val = iv_path sub = '.' occ = -1 ) ).
    IF lv_count < 3 OR lv_type IS INITIAL.
      RETURN.
    ENDIF.

    IF lt_parts[ 1 ] = c_script_folder.
      rv_kind = COND #( WHEN lv_count = 3 AND lv_type = c_script_type THEN c_kind-script ).
      RETURN.
    ENDIF.

    " Index of the area folder (EEXCEL, DATAMANAGER): 2 for <model>/..., 4 for
    " <model>/TEAM FILES/<team>/...; a file name must follow it
    DATA(lv_area) = COND i( WHEN lt_parts[ 2 ] = c_team_folder THEN 4 ELSE 2 ).
    IF lv_count <= lv_area.
      RETURN.
    ENDIF.
    IF lt_parts[ lv_area ] = c_webexcel_folder AND has_type( iv_types = c_workbook_types iv_type = lv_type ) = abap_true.
      rv_kind = c_kind-workbook.
    ELSEIF lt_parts[ lv_area ] = c_dm_folder AND lv_count > lv_area + 1.
      DATA(lv_dm_folder) = lt_parts[ lv_area + 1 ].
      IF lv_dm_folder = c_transformation_folder
          AND has_type( iv_types = c_transformation_types iv_type = lv_type ) = abap_true.
        rv_kind = c_kind-transformation.
      ELSEIF lv_dm_folder = c_conversion_folder
          AND has_type( iv_types = c_conversion_types iv_type = lv_type ) = abap_true.
        rv_kind = c_kind-conversion.
      ELSEIF lv_dm_folder = c_package_folder AND lv_type = c_xml_type AND lv_count = lv_area + 3.
        rv_kind = c_kind-package.
      ELSEIF lv_dm_folder = c_link_folder AND lv_type = c_xml_type AND lv_count = lv_area + 2
          AND lv_area = 2.
        " Package links belong to a model, never to a team
        rv_kind = c_kind-link.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD list_packages.
    TYPES:
      BEGIN OF ty_row,
        guid         TYPE ujd_packages2-guid,
        group_id     TYPE ujd_packages2-group_id,
        package_id   TYPE ujd_packages2-package_id,
        team_id      TYPE ujd_packages2-team_id,
        package_type TYPE ujd_packages2-package_type,
        user_group   TYPE ujd_packages2-user_group,
        chain_id     TYPE ujd_packages2-chain_id,
      END OF ty_row.
    DATA lt_rows TYPE STANDARD TABLE OF ty_row WITH DEFAULT KEY.
    DATA lv_script TYPE string.
    DATA lv_offset TYPE i.
    DATA lv_next TYPE i.

    " Rows without a package ID are package groups
    SELECT guid, group_id, package_id, team_id, package_type, user_group, chain_id
      FROM ujd_packages2
      WHERE appset_id = @iv_environment AND app_id = @iv_model AND package_id <> @space
      INTO TABLE @lt_rows.
    LOOP AT lt_rows INTO DATA(ls_row).
      DATA(ls_package) = VALUE ty_package( group = ls_row-group_id id = ls_row-package_id
                                           team = ls_row-team_id type = ls_row-package_type
                                           user_group = ls_row-user_group chain = ls_row-chain_id ).
      " Description in the logon language, else in any
      SELECT SINGLE package_desc FROM ujd_packagest2
        WHERE guid = @ls_row-guid AND langu = @sy-langu
        INTO @ls_package-descr.
      IF sy-subrc <> 0.
        SELECT SINGLE package_desc FROM ujd_packagest2
          WHERE guid = @ls_row-guid
          INTO @ls_package-descr.
      ENDIF.
      " Without a row the package runs its process chain's default script
      CLEAR lv_script.
      SELECT SINGLE content FROM ujd_instruction2
        WHERE guid = @ls_row-guid
        INTO @lv_script.
      IF sy-subrc = 0.
        ls_package-has_script = abap_true.
        " Consume separators explicitly: the final <BR> terminates the last
        " step; earlier adjacent separators represent intentional empty steps.
        WHILE lv_script IS NOT INITIAL.
          FIND FIRST OCCURRENCE OF c_script_separator IN lv_script MATCH OFFSET lv_offset.
          IF sy-subrc <> 0.
            APPEND lv_script TO ls_package-script.
            EXIT.
          ENDIF.
          APPEND substring( val = lv_script len = lv_offset ) TO ls_package-script.
          lv_next = lv_offset + strlen( c_script_separator ).
          lv_script = substring( val = lv_script off = lv_next ).
        ENDWHILE.
      ENDIF.

      DATA(lv_base) = COND string( WHEN ls_row-team_id IS INITIAL THEN |{ iv_model }/|
                                   ELSE |{ iv_model }/{ c_team_folder }/{ to_file_name( ls_row-team_id ) }/| ).
      DATA(lv_path) = |{ lv_base }{ c_dm_folder }/{ c_package_folder }/{ to_file_name( ls_row-group_id ) }/| &&
                      |{ to_file_name( ls_row-package_id ) }.xml|.
      DATA(lv_content) = package_to_xml( ls_package ).
      INSERT VALUE #( path      = lv_path
                      kind      = c_kind-package
                      model     = iv_model
                      docname   = to_docname( iv_environment = iv_environment iv_path = lv_path )
                      generated = abap_true
                      content   = lv_content
                      size      = xstrlen( lv_content ) ) INTO TABLE ct_workbooks.
    ENDLOOP.
  ENDMETHOD.

  METHOD list_links.
    DATA lv_content TYPE string.
    SELECT link_id, service_link_id FROM ujd_package_link
      WHERE appset_id = @iv_environment AND app_id = @iv_model
      INTO TABLE @DATA(lt_links).
    LOOP AT lt_links INTO DATA(ls_link).
      " The definition is stored under the service link ID if there is one
      DATA(lv_id) = COND uj_dms_id( WHEN ls_link-service_link_id IS NOT INITIAL
                                    THEN ls_link-service_link_id ELSE ls_link-link_id ).
      CLEAR lv_content.
      SELECT SINGLE content FROM ujd_link
        WHERE link_id = @lv_id
        INTO @lv_content.
      DATA(lv_name) = get_link_name( lv_content ).
      IF lv_name IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(lv_path) = |{ iv_model }/{ c_dm_folder }/{ c_link_folder }/{ to_file_name( lv_name ) }.xml|.
      " The ID differs per system, so Git holds the link without it
      DATA(lv_file) = cl_abap_codepage=>convert_to( set_link_id( iv_xml = lv_content iv_id = `` ) ).
      INSERT VALUE #( path      = lv_path
                      kind      = c_kind-link
                      model     = iv_model
                      docname   = to_docname( iv_environment = iv_environment iv_path = lv_path )
                      generated = abap_true
                      content   = lv_file
                      size      = xstrlen( lv_file ) ) INTO TABLE ct_workbooks.
    ENDLOOP.
  ENDMETHOD.

  METHOD package_to_xml.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    DATA(lv_xml) = |<?xml version="1.0" encoding="utf-8"?>{ lv_nl }<package>{ lv_nl }| &&
      xml_element( iv_name = `group` iv_value = is_package-group ) &&
      xml_element( iv_name = `id` iv_value = is_package-id ) &&
      xml_element( iv_name = `team` iv_value = is_package-team ) &&
      xml_element( iv_name = `description` iv_value = is_package-descr ) &&
      xml_element( iv_name = `type` iv_value = is_package-type ) &&
      xml_element( iv_name = `userGroup` iv_value = |{ CONV i( is_package-user_group ) }| ) &&
      xml_element( iv_name = `chain` iv_value = is_package-chain ).
    IF is_package-has_script = abap_true.
      lv_xml = lv_xml && |  <script>{ lv_nl }|.
      LOOP AT is_package-script INTO DATA(lv_line).
        lv_xml = lv_xml && `  ` && xml_element( iv_name = `line` iv_value = lv_line ).
      ENDLOOP.
      lv_xml = lv_xml && |  </script>{ lv_nl }|.
    ENDIF.
    lv_xml = lv_xml && |</package>{ lv_nl }|.
    rv_xml = cl_abap_codepage=>convert_to( lv_xml ).
  ENDMETHOD.

  METHOD xml_element.
    DATA(lv_value) = |{ iv_value }|.
    rv_xml = |  <{ iv_name }>{ escape( val = lv_value format = cl_abap_format=>e_xml_text ) }</{ iv_name }>| &&
             cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD parse_package.
    DATA lv_element TYPE string.
    DATA lv_root TYPE string.
    CLEAR: es_package, ev_error.
    TRY.
        DATA(lo_reader) = cl_sxml_string_reader=>create( iv_xml ).
        DO.
          DATA(lo_node) = lo_reader->read_next_node( ).
          IF lo_node IS NOT BOUND.
            EXIT.
          ENDIF.
          CASE lo_node->type.
            WHEN if_sxml_node=>co_nt_element_open.
              lv_element = CAST if_sxml_open_element( lo_node )->qname-name.
              IF lv_root IS INITIAL.
                lv_root = lv_element.
                IF lv_root <> `package`.
                  ev_error = 'The package file must have a package root element'.
                  RETURN.
                ENDIF.
              ENDIF.
              IF lv_element = `script`.
                es_package-has_script = abap_true.
              ELSEIF lv_element = `line`.
                " An empty <line/> has no value node
                APPEND INITIAL LINE TO es_package-script.
              ENDIF.
            WHEN if_sxml_node=>co_nt_element_close.
              CLEAR lv_element.
            WHEN if_sxml_node=>co_nt_value.
              DATA(lv_value) = CAST if_sxml_value_node( lo_node )->get_value( ).
              CASE lv_element.
                WHEN `group`.
                  es_package-group = lv_value.
                WHEN `id`.
                  es_package-id = lv_value.
                WHEN `team`.
                  es_package-team = lv_value.
                WHEN `description`.
                  es_package-descr = lv_value.
                WHEN `type`.
                  es_package-type = lv_value.
                WHEN `userGroup`.
                  es_package-user_group = lv_value.
                WHEN `chain`.
                  es_package-chain = lv_value.
                WHEN `line`.
                  es_package-script[ lines( es_package-script ) ] = lv_value.
              ENDCASE.
          ENDCASE.
        ENDDO.
      CATCH cx_root INTO DATA(lx_error).
        ev_error = |Not a valid package file: { lx_error->get_text( ) }|.
        RETURN.
    ENDTRY.
    IF es_package-group IS INITIAL OR es_package-id IS INITIAL.
      ev_error = 'The package file has no group or id'.
    ENDIF.
  ENDMETHOD.

  METHOD get_link_name.
    FIND FIRST OCCURRENCE OF REGEX '<PROPERTY NAME="NAME">([^<]*)</PROPERTY>' IN iv_xml SUBMATCHES rv_name.
    REPLACE ALL OCCURRENCES OF '&lt;' IN rv_name WITH '<'.
    REPLACE ALL OCCURRENCES OF '&gt;' IN rv_name WITH '>'.
    REPLACE ALL OCCURRENCES OF '&quot;' IN rv_name WITH '"'.
    REPLACE ALL OCCURRENCES OF '&apos;' IN rv_name WITH ''''.
    REPLACE ALL OCCURRENCES OF '&amp;' IN rv_name WITH '&'.
  ENDMETHOD.

  METHOD set_link_id.
    " The link's own ID is its first ID property; the steps' IDs follow it
    rv_xml = iv_xml.
    REPLACE FIRST OCCURRENCE OF REGEX '<PROPERTY NAME="ID">[^<]*</PROPERTY>|<PROPERTY NAME="ID"\s*/>'
      IN rv_xml WITH |<PROPERTY NAME="ID">{ iv_id }</PROPERTY>|.
  ENDMETHOD.

  METHOD to_file_name.
    rv_name = iv_name.
    REPLACE ALL OCCURRENCES OF REGEX '[/\\:*?"<>|]' IN rv_name WITH '_'.
  ENDMETHOD.

  METHOD restore_package.
    DATA ls_package TYPE ty_package.
    parse_package( EXPORTING iv_xml = iv_xml IMPORTING es_package = ls_package ev_error = rv_message ).
    IF rv_message IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_base) = COND string( WHEN ls_package-team IS INITIAL THEN |{ iv_model }/|
      ELSE |{ iv_model }/{ c_team_folder }/{ to_file_name( ls_package-team ) }/| ).
    DATA(lv_expected) = |{ lv_base }{ c_dm_folder }/{ c_package_folder }/{ to_file_name( ls_package-group ) }/| &&
      |{ to_file_name( ls_package-id ) }.xml|.
    IF iv_path <> lv_expected.
      rv_message = 'The package identity does not match the selected Git path'.
      RETURN.
    ENDIF.
    DATA(lv_model) = CONV uj_appl_id( iv_model ).
    IF iv_delete = abap_false AND ls_package-has_script = abap_false.
      SELECT SINGLE guid FROM ujd_packages2
        WHERE appset_id = @iv_environment AND app_id = @lv_model AND team_id = @ls_package-team
          AND group_id = @ls_package-group AND package_id = @ls_package-id
        INTO @DATA(lv_guid).
      IF sy-subrc = 0.
        SELECT SINGLE guid FROM ujd_instruction2 WHERE guid = @lv_guid INTO @DATA(lv_instruction).
        IF sy-subrc = 0.
          rv_message = 'Cannot restore a default-script package over a custom script; reset it in BPC first'.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.
    TRY.
        DATA(lo_package) = NEW cl_ujd_package( ).
        IF iv_delete = abap_true.
          lo_package->delete_package( i_appset = iv_environment i_appl = lv_model i_team = ls_package-team
                                      i_group = ls_package-group i_package = ls_package-id ).
          RETURN.
        ENDIF.
        IF lo_package->check_package_exist( i_appset = iv_environment i_appl = lv_model
                                            i_team = ls_package-team i_group = ls_package-group
                                            i_package = ls_package-id ) = abap_true.
          lo_package->modify_package( i_appset = iv_environment i_appl = lv_model i_team = ls_package-team
                                      i_group = ls_package-group i_package = ls_package-id
                                      i_package_desc = ls_package-descr i_package_type = ls_package-type
                                      i_user_group = ls_package-user_group i_chain = ls_package-chain
                                      i_original_group = ls_package-group
                                      i_original_package = ls_package-id ).
        ELSE.
          lo_package->add_package( i_appset = iv_environment i_appl = lv_model i_team = ls_package-team
                                   i_group = ls_package-group i_package = ls_package-id
                                   i_package_desc = ls_package-descr i_package_type = ls_package-type
                                   i_user_group = ls_package-user_group i_chain = ls_package-chain ).
        ENDIF.
        " Without a script element the package keeps its chain's default script
        IF ls_package-has_script = abap_true.
          DATA(lv_script) = COND string( WHEN ls_package-script IS NOT INITIAL
            THEN concat_lines_of( table = ls_package-script sep = c_script_separator ) && c_script_separator ).
          lo_package->save_package_info( i_appset = iv_environment i_appl = lv_model i_team = ls_package-team
                                         i_group = ls_package-group i_package = ls_package-id
                                         i_script = lv_script ).
        ENDIF.
      CATCH cx_static_check INTO DATA(lx_error).
        rv_message = lx_error->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD restore_link.
    DATA lo_link TYPE REF TO cl_ujd_link.
    DATA lv_plink_id TYPE uj_dms_id.
    DATA lv_success TYPE uj_flg.
    DATA lt_messages TYPE uj0_t_message.

    DATA(lv_xml) = cl_abap_codepage=>convert_from( iv_xml ).
    DATA(lv_name) = get_link_name( lv_xml ).
    IF lv_name IS INITIAL.
      rv_message = 'The package link file has no NAME property'.
      RETURN.
    ENDIF.
    DATA(lv_expected) = |{ iv_model }/{ c_dm_folder }/{ c_link_folder }/{ to_file_name( lv_name ) }.xml|.
    IF iv_path <> lv_expected.
      rv_message = 'The package link name does not match the selected Git path'.
      RETURN.
    ENDIF.
    DATA(lv_model) = CONV uj_appl_id( iv_model ).
    DATA(ls_user) = VALUE uj0_s_user( user_id = sy-uname langu = sy-langu ).
    TRY.
        " SAVE_PLINK would add a second link of the same name; update in place
        cl_ujd_package_link=>get_link_with_name( EXPORTING i_appset_id = iv_environment
                                                           i_appl_id = lv_model
                                                           i_link_name = CONV uj_fullname( lv_name )
                                                 IMPORTING eo_link = lo_link
                                                           e_plink_id = lv_plink_id ).
        DATA(lo_plink) = NEW cl_ujd_package_link( ).
        IF iv_delete = abap_true.
          IF lv_plink_id IS NOT INITIAL.
            lo_plink->delete_plink( i_appset_id = iv_environment i_appl_id = lv_model i_link_id = lv_plink_id ).
          ENDIF.
          RETURN.
        ENDIF.
        IF lv_plink_id IS INITIAL.
          lo_plink->save_plink( EXPORTING i_appset_id = iv_environment i_appl_id = lv_model
                                          i_link_content = lv_xml is_user = ls_user
                                IMPORTING e_link_id = lv_plink_id ef_success = lv_success
                                          et_message = lt_messages ).
        ELSE.
          lv_success = abap_true.
        ENDIF.
        IF lv_success = abap_true.
          " Store the link with this system's ID, as BPC does
          lo_plink->update_plink( EXPORTING i_appset_id = iv_environment i_appl_id = lv_model
                                            is_user = ls_user i_link_id = lv_plink_id
                                            i_link_detail = set_link_id( iv_xml = lv_xml iv_id = lv_plink_id )
                                  IMPORTING ef_success = lv_success et_message = lt_messages ).
        ENDIF.
        IF lv_success = abap_false.
          LOOP AT lt_messages INTO DATA(ls_message) WHERE msgty CA 'EAX'.
            rv_message = ls_message-message.
            EXIT.
          ENDLOOP.
          IF rv_message IS INITIAL.
            rv_message = 'BPC did not accept the package link'.
          ENDIF.
        ENDIF.
      CATCH cx_static_check INTO DATA(lx_error).
        rv_message = lx_error->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD has_type.
    DATA lt_types TYPE string_table.
    SPLIT iv_types AT space INTO TABLE lt_types.
    rv_found = xsdbool( line_exists( lt_types[ table_line = iv_type ] ) ).
  ENDMETHOD.

  METHOD get_model.
    IF iv_path CP 'SECURITY/*'.
      RETURN.
    ENDIF.
    rv_model = COND #( WHEN get_kind( iv_path ) = c_kind-script
                       THEN segment( val = iv_path index = 2 sep = '/' )
                       ELSE substring_before( val = iv_path sub = '/' ) ).
  ENDMETHOD.

  METHOD get_team.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    IF lines( lt_parts ) >= 3 AND lt_parts[ 2 ] = c_team_folder.
      rv_team = lt_parts[ 3 ].
    ENDIF.
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
