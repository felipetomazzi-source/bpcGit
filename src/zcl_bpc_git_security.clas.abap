"! Portable BPC security definitions. Users and assignments stay local.
CLASS zcl_bpc_git_security DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPE-POOLS uje0.
    TYPES:
      BEGIN OF ty_definition,
        version TYPE i,
        kind TYPE string,
        id TYPE string,
        description TYPE uj_desc,
        tasks TYPE uje_t_task_id,
        access TYPE uje_s_mbr_prof_det,
      END OF ty_definition,
      BEGIN OF ty_file,
        path TYPE string,
        kind TYPE string,
        content TYPE xstring,
      END OF ty_file,
      ty_files TYPE STANDARD TABLE OF ty_file WITH DEFAULT KEY.
    CLASS-METHODS can_read RETURNING VALUE(rv_allowed) TYPE abap_bool.
    CLASS-METHODS get_kind IMPORTING iv_path TYPE string RETURNING VALUE(rv_kind) TYPE string.
    CLASS-METHODS list
      IMPORTING iv_environment TYPE uj_appset_id iv_kind TYPE string OPTIONAL
      RETURNING VALUE(rt_files) TYPE ty_files
      RAISING cx_uj_static_check.
    CLASS-METHODS restore
      IMPORTING iv_environment TYPE uj_appset_id iv_path TYPE string iv_xml TYPE xstring iv_delete TYPE abap_bool
      RETURNING VALUE(rv_message) TYPE string.
  PRIVATE SECTION.
    CLASS-METHODS path
      IMPORTING iv_kind TYPE string iv_id TYPE string RETURNING VALUE(rv_path) TYPE string.
    CLASS-METHODS read
      IMPORTING iv_environment TYPE uj_appset_id iv_kind TYPE string iv_id TYPE string
      RETURNING VALUE(rs_definition) TYPE ty_definition RAISING cx_uj_static_check.
    CLASS-METHODS encode
      IMPORTING is_definition TYPE ty_definition RETURNING VALUE(rv_xml) TYPE xstring.
    CLASS-METHODS normalize
      IMPORTING iv_ordered TYPE abap_bool DEFAULT abap_false CHANGING cs_data TYPE any.
ENDCLASS.

CLASS zcl_bpc_git_security IMPLEMENTATION.
  METHOD can_read.
    TRY.
        cl_uje_common=>ensure_has_manage_authority( ).
        rv_allowed = abap_true.
      CATCH cx_uj_no_auth.
        rv_allowed = abap_false.
    ENDTRY.
  ENDMETHOD.

  METHOD get_kind.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    IF lines( lt_parts ) <> 3 OR lt_parts[ 1 ] <> 'SECURITY' OR lt_parts[ 3 ] = '.xml'.
      RETURN.
    ENDIF.
    IF substring_after( val = lt_parts[ 3 ] sub = '.' occ = -1 ) <> 'xml'.
      RETURN.
    ENDIF.
    rv_kind = SWITCH #( lt_parts[ 2 ] WHEN 'TEAMS' THEN 'TEAM'
      WHEN 'TASKPROFILES' THEN 'TASKPROFILE' WHEN 'DATAACCESSPROFILES' THEN 'DATAPROFILE' ).
  ENDMETHOD.

  METHOD path.
    DATA(lv_folder) = SWITCH string( iv_kind WHEN 'TEAM' THEN 'TEAMS'
      WHEN 'TASKPROFILE' THEN 'TASKPROFILES' WHEN 'DATAPROFILE' THEN 'DATAACCESSPROFILES' ).
    rv_path = |SECURITY/{ lv_folder }/{ cl_http_utility=>escape_url( iv_id ) }.xml|.
  ENDMETHOD.

  METHOD read.
    rs_definition = VALUE #( version = 1 kind = iv_kind id = iv_id ).
    CASE iv_kind.
      WHEN 'TEAM'.
        DATA(lo_team) = NEW cl_uje_team( i_appset_id = iv_environment i_object_id = iv_id ).
        lo_team->get_team_info( IMPORTING es_team_info = DATA(ls_team) ).
        rs_definition-description = ls_team-description.
      WHEN 'TASKPROFILE'.
        DATA lo_task TYPE REF TO cl_uje_profile_task.
        lo_task ?= cl_uje_user_mgr=>create_obj( i_appset_id = iv_environment i_object_id = iv_id
          i_object_type = 'CL_UJE_PROFILE_TASK' ).
        rs_definition-description = lo_task->get_desc( ).
        lo_task->get_task_list( IMPORTING et_task_id = rs_definition-tasks ).
      WHEN 'DATAPROFILE'.
        DATA(lo_access) = NEW cl_uje_memaccess_dao( i_appset_id = iv_environment ).
        lo_access->get_prof_det( EXPORTING i_profile_id = CONV #( iv_id )
          IMPORTING et_mbr_prof_dets = DATA(lt_access) ).
        IF lines( lt_access ) <> 1.
          RAISE EXCEPTION TYPE cx_uj_static_check.
        ENDIF.
        rs_definition-access = lt_access[ 1 ].
        " PROFILE_AGR_NAME is the logical profile caption, not a generated role.
        rs_definition-access-profile_agr_name = iv_id.
    ENDCASE.
    normalize( CHANGING cs_data = rs_definition ).
  ENDMETHOD.

  METHOD encode.
    DATA(lo_writer) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_xml10 ).
    lo_writer->if_sxml_writer~set_option( option = if_sxml_writer=>co_opt_linebreaks value = abap_true ).
    lo_writer->if_sxml_writer~set_option( option = if_sxml_writer=>co_opt_indent value = abap_true ).
    CALL TRANSFORMATION id SOURCE definition = is_definition RESULT XML lo_writer.
    rv_xml = lo_writer->get_output( ).
  ENDMETHOD.

  METHOD normalize.
    " Sort sets by their serialized rows, including deep values. Matrix column
    " order is positional: preserve DIMENSIONS and the outer MEMBERS table.
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( cs_data ).
    CASE lo_type->kind.
      WHEN cl_abap_typedescr=>kind_struct.
        DATA lo_struct TYPE REF TO cl_abap_structdescr.
        lo_struct ?= lo_type.
        LOOP AT lo_struct->components INTO DATA(ls_component).
          ASSIGN COMPONENT ls_component-name OF STRUCTURE cs_data TO FIELD-SYMBOL(<lv_value>).
          IF ls_component-name = 'MEMBERDESC'.
            CLEAR <lv_value>.
          ELSE.
            normalize( EXPORTING iv_ordered = xsdbool( ls_component-name = 'DIMENSIONS'
              OR ls_component-name = 'MEMBERS' ) CHANGING cs_data = <lv_value> ).
          ENDIF.
        ENDLOOP.
      WHEN cl_abap_typedescr=>kind_table.
        FIELD-SYMBOLS <lt_table> TYPE ANY TABLE.
        ASSIGN cs_data TO <lt_table>.
        TYPES: BEGIN OF ty_row, key TYPE xstring, data TYPE REF TO data, END OF ty_row.
        DATA lt_rows TYPE STANDARD TABLE OF ty_row WITH DEFAULT KEY.
        LOOP AT <lt_table> ASSIGNING FIELD-SYMBOL(<ls_row>).
          normalize( CHANGING cs_data = <ls_row> ).
          IF iv_ordered = abap_false.
            DATA ls_row TYPE ty_row.
            CREATE DATA ls_row-data LIKE <ls_row>.
            ASSIGN ls_row-data->* TO FIELD-SYMBOL(<ls_copy>).
            <ls_copy> = <ls_row>.
            CALL TRANSFORMATION id SOURCE row = <ls_copy> RESULT XML ls_row-key.
            APPEND ls_row TO lt_rows.
          ENDIF.
        ENDLOOP.
        IF iv_ordered = abap_false.
          SORT lt_rows BY key.
          CLEAR <lt_table>.
          LOOP AT lt_rows INTO ls_row.
            ASSIGN ls_row-data->* TO <ls_copy>.
            INSERT <ls_copy> INTO TABLE <lt_table>.
          ENDLOOP.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD list.
    IF iv_kind IS INITIAL AND can_read( ) = abap_false.
      RETURN.
    ENDIF.
    cl_uje_common=>ensure_has_manage_authority( ).
    DATA lt_ids TYPE string_table.
    DATA lt_kinds TYPE string_table.
    lt_kinds = VALUE #( ( `TEAM` ) ( `TASKPROFILE` ) ( `DATAPROFILE` ) ).
    LOOP AT lt_kinds INTO DATA(lv_kind).
      IF iv_kind IS NOT INITIAL AND iv_kind <> lv_kind.
        CONTINUE.
      ENDIF.
      CLEAR lt_ids.
      IF lv_kind = 'TEAM'.
        cl_uje_team=>get_all_team_id( EXPORTING i_appset_id = iv_environment IMPORTING et_team_id = DATA(lt_teams) ).
        LOOP AT lt_teams INTO DATA(lv_team).
          APPEND CONV string( lv_team ) TO lt_ids.
        ENDLOOP.
      ELSE.
        cl_uje_profile=>get_profile_by_class( EXPORTING i_appset_id = iv_environment
          i_profile_class = COND #( WHEN lv_kind = 'TASKPROFILE' THEN uje0_cs_profile_class-tsk ELSE uje0_cs_profile_class-mbr )
          IMPORTING et_profile_id = DATA(lt_profiles) ).
        LOOP AT lt_profiles INTO DATA(lv_profile).
          APPEND CONV string( lv_profile ) TO lt_ids.
        ENDLOOP.
      ENDIF.
      SORT lt_ids.
      LOOP AT lt_ids INTO DATA(lv_id).
        DATA(ls_definition) = read( iv_environment = iv_environment iv_kind = lv_kind iv_id = lv_id ).
        APPEND VALUE #( path = path( iv_kind = lv_kind iv_id = lv_id ) kind = lv_kind
          content = encode( ls_definition ) ) TO rt_files.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD restore.
    TRY.
        cl_uje_common=>ensure_has_manage_authority( ).
        IF iv_delete = abap_true.
          rv_message = 'Remove security definitions in BPC; Git restore does not delete local assignments or team folders'.
          RETURN.
        ENDIF.
        DATA ls_definition TYPE ty_definition.
        CALL TRANSFORMATION id SOURCE XML iv_xml RESULT definition = ls_definition.
        IF ls_definition-version <> 1 OR ls_definition-id IS INITIAL
            OR ls_definition-kind <> get_kind( iv_path )
            OR path( iv_kind = ls_definition-kind iv_id = ls_definition-id ) <> iv_path.
          rv_message = 'Security XML identity or version does not match the selected path'.
          RETURN.
        ENDIF.
        IF ls_definition-kind <> 'DATAPROFILE' AND ls_definition-access IS NOT INITIAL
            OR ls_definition-kind <> 'TASKPROFILE' AND ls_definition-tasks IS NOT INITIAL.
          rv_message = 'Security XML contains fields for a different object type'.
          RETURN.
        ENDIF.
        IF ls_definition-kind = 'TEAM' AND CONV string( CONV uj_team_id( ls_definition-id ) ) <> ls_definition-id
            OR ls_definition-kind <> 'TEAM' AND CONV string( CONV uj_profile_id( ls_definition-id ) ) <> ls_definition-id.
          rv_message = 'Security object ID exceeds the BPC field length or has trailing spaces'.
          RETURN.
        ENDIF.
        CASE ls_definition-kind.
          WHEN 'TEAM'.
            DATA lt_teams TYPE uje_t_team.
            lt_teams = VALUE #( ( team_id = CONV #( ls_definition-id ) description = ls_definition-description ) ).
            IF cl_uje_team=>is_team_exist( i_appset_id = iv_environment i_team_id = CONV #( ls_definition-id ) ) = abap_false.
              cl_uje_team=>create_teams( i_appset_id = iv_environment it_teams = lt_teams ).
            ENDIF.
            " Omit all assignment parameters: native API preserves memberships.
            cl_uje_team=>update_teams( i_appset_id = iv_environment it_teams = lt_teams ).
          WHEN 'TASKPROFILE'.
            DATA lo_task TYPE REF TO cl_uje_profile_task.
            lo_task ?= cl_uje_user_mgr=>create_obj( i_appset_id = iv_environment i_object_id = ls_definition-id
              i_object_type = 'CL_UJE_PROFILE_TASK' ).
            IF lo_task->is_default_profile( ) = abap_true.
              rv_message = 'BPC default task profiles cannot be restored'.
              RETURN.
            ENDIF.
            IF cl_uje_profile=>is_profile_exist( i_appset_id = iv_environment i_profile_id = CONV #( ls_definition-id )
                i_profile_class = uje0_cs_profile_class-tsk ) = abap_true.
              lo_task->update( i_task_prof_desc = ls_definition-description it_tasks = ls_definition-tasks ).
            ELSE.
              lo_task->create( i_task_prof_desc = ls_definition-description it_tasks = ls_definition-tasks ).
            ENDIF.
          WHEN 'DATAPROFILE'.
            IF ls_definition-access-profile_agr_name <> ls_definition-id OR ls_definition-description IS NOT INITIAL.
              rv_message = 'Data access profile identity is inconsistent'.
              RETURN.
            ENDIF.
            DATA(lo_profile) = NEW cl_uje_profile_memaccess( i_appset_id = iv_environment i_object_id = ls_definition-id ).
            IF lo_profile->is_default_profile( ) = abap_true.
              rv_message = 'BPC default data access profiles cannot be restored'.
              RETURN.
            ENDIF.
            DATA(lt_access) = VALUE uje_t_mbr_prof_det( ( ls_definition-access ) ).
            DATA(lo_appset) = cl_uja_bpc_admin_factory=>get_appset_manager( i_appset_id = iv_environment ).
            lo_appset->get_applications( EXPORTING if_summary = abap_true IMPORTING et_applications = DATA(lt_models) ).
            " Native DAP save replaces the entire profile. Check model mode
            " before it can remove rules; it otherwise ignores wrong-mode data.
            LOOP AT ls_definition-access-cube_acc INTO DATA(ls_cube).
              IF NOT line_exists( lt_models[ application_id = ls_cube-application_id ] ).
                rv_message = 'A data access rule refers to a model missing from this environment'.
                RETURN.
              ENDIF.
              IF cl_uje_memaccess_runtime=>if_matrix_security_enabled(
                  i_appset_id = iv_environment i_appl_id = ls_cube-application_id ) = abap_true.
                rv_message = 'Standard access rules target a model using matrix security'.
                RETURN.
              ENDIF.
            ENDLOOP.
            LOOP AT ls_definition-access-cube_matrix_acc INTO DATA(ls_matrix).
              IF NOT line_exists( lt_models[ application_id = ls_matrix-application_id ] ).
                rv_message = 'A matrix access rule refers to a model missing from this environment'.
                RETURN.
              ENDIF.
              IF cl_uje_memaccess_runtime=>if_matrix_security_enabled(
                  i_appset_id = iv_environment i_appl_id = ls_matrix-application_id ) = abap_false.
                rv_message = 'Matrix access rules target a model using standard security'.
                RETURN.
              ENDIF.
            ENDLOOP.
            IF cl_uje_profile=>is_profile_exist( i_appset_id = iv_environment i_profile_id = CONV #( ls_definition-id )
                i_profile_class = uje0_cs_profile_class-mbr ) = abap_true.
              cl_uje_profile_memaccess=>update_mbr_profiles( i_appset_id = iv_environment it_mbr_prof_det = lt_access ).
            ELSE.
              cl_uje_profile_memaccess=>create_mbr_profiles( i_appset_id = iv_environment it_mbr_prof_det = lt_access ).
            ENDIF.
          WHEN OTHERS.
            rv_message = 'Unsupported security object type'.
            RETURN.
        ENDCASE.
        normalize( CHANGING cs_data = ls_definition ).
        DATA(ls_actual) = read( iv_environment = iv_environment iv_kind = ls_definition-kind iv_id = ls_definition-id ).
        IF encode( ls_actual ) <> encode( ls_definition ).
          rv_message = 'BPC security definition differs from Git after restore; synchronization was not recorded'.
        ENDIF.
      CATCH cx_root INTO DATA(lx_error).
        rv_message = lx_error->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
