CLASS zcl_abapgit_user_exit DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zif_abapgit_exit.

  PROTECTED SECTION.

  PRIVATE SECTION.

    "! Hard-coded scope for the first cut: only the DEMREVID logic script
    "! model under the CH_PLANNING appset. When more models are needed,
    "! this is the single place to extend (or replace with a config table).
    CONSTANTS c_appset TYPE uj_appset_id VALUE 'CH_PLANNING'.
    CONSTANTS c_appl   TYPE uj_appl_id   VALUE 'DEMREVID'.
    "! abapGit repo sub-folder the scripts are serialized into.
    CONSTANTS c_root   TYPE string       VALUE 'logic_scripts'.
    "! Only the human-authored source scripts are tracked, never the
    "! generated .LGX compiled artifacts.
    CONSTANTS c_doctype_lgf TYPE uj_doctype VALUE 'LGF'.
    "! Object metadata for the serialized script items. Logic scripts are
    "! TADIR object type ASPR; the rest is hard-coded for the first cut.
    CONSTANTS c_obj_type  TYPE tadir-object     VALUE 'ASPR'.
    CONSTANTS c_devclass  TYPE devclass         VALUE 'ZCHORUS_BPC'.
    CONSTANTS c_srcsystem TYPE tadir-srcsystem  VALUE 'CWD'.
    CONSTANTS c_origlang  TYPE tadir-masterlang VALUE 'E'.

    "! List all .LGF logic scripts for the configured appset/appl and
    "! return them as ready-to-commit abapGit file items.
    METHODS serialize_logic_scripts
      RETURNING
        VALUE(rt_files) TYPE zif_abapgit_definitions=>ty_files_item_tt
      RAISING
        cx_static_check.

    "! Read a single document's content from the BPC file service and
    "! convert it from the stored codepage into a readable string.
    "! Mirrors the read path used by CL_UJK_DISPATCH=>GET_FILE, but
    "! without the audit-log side effect.
    METHODS read_script_content
      IMPORTING
        !io_file_mgr      TYPE REF TO cl_ujf_file_service_mgr
        !iv_docname       TYPE ujf_doc-docname
      RETURNING
        VALUE(rv_content) TYPE string
      RAISING
        cx_static_check.

ENDCLASS.



CLASS zcl_abapgit_user_exit IMPLEMENTATION.


  METHOD zif_abapgit_exit~serialize_postprocess.

    DATA lt_scripts TYPE zif_abapgit_definitions=>ty_files_item_tt.

    " Only contribute our logic-script files; leave everything abapGit
    " already serialized untouched. Any failure here must never break a
    " normal serialize run, so swallow exceptions and just skip.
    TRY.
        lt_scripts = serialize_logic_scripts( ).
        INSERT LINES OF lt_scripts INTO TABLE ct_files.
      CATCH cx_root ##CATCH_ALL.
        " intentionally ignored - script export is best-effort
    ENDTRY.

  ENDMETHOD.


  METHOD serialize_logic_scripts.

    DATA lo_file_mgr TYPE REF TO cl_ujf_file_service_mgr.
    DATA ls_user     TYPE uj0_s_user.
    DATA lv_dir      TYPE ujf_doctree-docname.
    DATA lt_doc      TYPE ujf_t_doc.
    DATA lv_content  TYPE string.
    DATA lv_name     TYPE uj_docname.
    DATA ls_file     TYPE zif_abapgit_definitions=>ty_file_item.

    FIELD-SYMBOLS <ls_doc> TYPE ujf_doc.

    ls_user-user_id = sy-uname.
    ls_user-langu   = sy-langu.

    " Build the file-service manager for the appset, then list the
    " logic-script directory for the model - same path the standard
    " CL_UJXK_SCRIPT_RES=>GET_SCRIPT_LIST builds.
    lo_file_mgr = cl_ujf_file_service_mgr=>factory(
                    is_user  = ls_user
                    i_appset = c_appset ).

    CONCATENATE '\ROOT\WEBFOLDERS\' c_appset '\ADMINAPP\' c_appl '\'
      INTO lv_dir.
    TRANSLATE lv_dir TO UPPER CASE.

    lo_file_mgr->list_directory(
      EXPORTING
        i_dirname          = lv_dir
        i_doctype          = c_doctype_lgf
        i_sort             = abap_true
      IMPORTING
        et_document_list   = lt_doc ).

    LOOP AT lt_doc ASSIGNING <ls_doc>.

      " Defensive: skip anything that isn't an LGF source script.
      IF <ls_doc>-doctype <> c_doctype_lgf.
        CONTINUE.
      ENDIF.

      lv_content = read_script_content(
                     io_file_mgr = lo_file_mgr
                     iv_docname  = <ls_doc>-docname ).

      " Reduce the full document path to just the file name, e.g.
      " \ROOT\WEBFOLDERS\CH_PLANNING\ADMINAPP\DEMREVID\FOO.LGF -> FOO.LGF
      CALL FUNCTION 'UJ0_CRACK_FILEPATH'
        EXPORTING
          i_file_path = <ls_doc>-docname
        IMPORTING
          e_file_name = lv_name.

      CLEAR ls_file.
      " Path drives the folder tree shown in the abapGit repo view:
      " /<appset>/<app>/logic_scripts/. Lower-cased to match abapGit's
      " on-disk conventions.
      ls_file-file-path     = |/{ to_lower( c_appset ) }/{ to_lower( c_appl ) }/{ c_root }/|.
      ls_file-file-filename = to_lower( lv_name ).
      ls_file-file-data     = zcl_abapgit_convert=>string_to_xstring_utf8( lv_content ).

      " Identify the file as a BPC logic-script object so abapGit tracks
      " it with a proper item (type ASPR), rather than an orphan file.
      ls_file-item-obj_type  = c_obj_type.
      ls_file-item-obj_name  = lv_name.
      ls_file-item-devclass  = c_devclass.
      ls_file-item-srcsystem = c_srcsystem.
      ls_file-item-origlang  = c_origlang.

      APPEND ls_file TO rt_files.

    ENDLOOP.

  ENDMETHOD.


  METHOD read_script_content.

    DATA lv_doctype   TYPE ujf_doc-doctype.
    DATA lv_raw       TYPE ujf_doc-doc_content.

    " Read the raw stored content...
    io_file_mgr->get_document(
      EXPORTING
        i_docname          = iv_docname
        i_retzip           = abap_false
      IMPORTING
        e_document_type    = lv_doctype
        e_document_content = lv_raw ).

    " ...then convert from the BPC storage codepage (4110) to a plain
    " string, the same conversion CL_UJK_DISPATCH=>GET_FILE performs.
    CALL FUNCTION 'SCP_TRANSLATE_CHARS_46'
      EXPORTING
        inbuff           = lv_raw
        incode           = '4110'
        outcode          = '0000'
        ctrlcode         = 'T'
      IMPORTING
        outbuff          = rv_content
      EXCEPTIONS
        invalid_codepage = 1
        internal_error   = 2
        cannot_convert   = 3
        fields_bad_type  = 4
        OTHERS           = 5.
    IF sy-subrc <> 0.
      CLEAR rv_content.
    ENDIF.

  ENDMETHOD.


  METHOD zif_abapgit_exit~adjust_commit_message.
  ENDMETHOD.

  METHOD zif_abapgit_exit~adjust_display_commit_url.
  ENDMETHOD.

  METHOD zif_abapgit_exit~adjust_display_filename.
    rv_filename = iv_filename.
  ENDMETHOD.

  METHOD zif_abapgit_exit~allow_sap_objects.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_committer_info.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_password_popup_username.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_local_host.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_max_parallel_processes.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_proxy_authentication.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_proxy_port.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_proxy_url.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_rfc_server_group.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_supported_data_objects.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_supported_object_types.
  ENDMETHOD.

  METHOD zif_abapgit_exit~change_tadir.
  ENDMETHOD.

  METHOD zif_abapgit_exit~create_http_client.
  ENDMETHOD.

  METHOD zif_abapgit_exit~custom_serialize_abap_clif.
    rt_source = it_source.
  ENDMETHOD.

  METHOD zif_abapgit_exit~deserialize_postprocess.
  ENDMETHOD.

  METHOD zif_abapgit_exit~determine_transport_request.
  ENDMETHOD.

  METHOD zif_abapgit_exit~enable_adjust_commit_message.
  ENDMETHOD.

  METHOD zif_abapgit_exit~enhance_any_toolbar.
  ENDMETHOD.

  METHOD zif_abapgit_exit~enhance_repo_toolbar.
  ENDMETHOD.

  METHOD zif_abapgit_exit~get_ci_tests.
  ENDMETHOD.

  METHOD zif_abapgit_exit~get_ssl_id.
  ENDMETHOD.

  METHOD zif_abapgit_exit~http_client.
  ENDMETHOD.

  METHOD zif_abapgit_exit~on_event.
  ENDMETHOD.

  METHOD zif_abapgit_exit~pre_calculate_repo_status.
  ENDMETHOD.

  METHOD zif_abapgit_exit~validate_before_push.
  ENDMETHOD.

  METHOD zif_abapgit_exit~validate_after_push.
  ENDMETHOD.

  METHOD zif_abapgit_exit~wall_message_list.
  ENDMETHOD.

  METHOD zif_abapgit_exit~wall_message_repo.
  ENDMETHOD.

ENDCLASS.
