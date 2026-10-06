"! Per-member BPC working-copy definitions; processing remains in BPC.
CLASS zcl_bpc_git_members DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPE-POOLS: uje0, uj00.
    TYPES ty_dimensions TYPE STANDARD TABLE OF uj_dim_name WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_value,
        name TYPE string,
        value TYPE string,
      END OF ty_value,
      ty_values TYPE SORTED TABLE OF ty_value WITH UNIQUE KEY name,
      BEGIN OF ty_definition,
        version TYPE i,
        dimension TYPE uj_dim_name,
        id TYPE string,
        name TYPE string,
        description TYPE string,
        language TYPE sylangu,
        properties TYPE ty_values,
        parents TYPE ty_values,
      END OF ty_definition,
      ty_definitions TYPE STANDARD TABLE OF ty_definition WITH DEFAULT KEY,
      BEGIN OF ty_file,
        path TYPE string,
        description TYPE string,
        content TYPE xstring,
      END OF ty_file,
      ty_files TYPE SORTED TABLE OF ty_file WITH UNIQUE KEY path.
    CLASS-METHODS can_read RETURNING VALUE(rv_allowed) TYPE abap_bool.
    CLASS-METHODS get_kind IMPORTING iv_path TYPE string RETURNING VALUE(rv_kind) TYPE string.
    CLASS-METHODS get_dimension IMPORTING iv_path TYPE string RETURNING VALUE(rv_dimension) TYPE string.
    CLASS-METHODS dimensions IMPORTING iv_environment TYPE uj_appset_id
      RETURNING VALUE(rt_dimensions) TYPE ty_dimensions RAISING cx_uj_static_check.
    CLASS-METHODS list IMPORTING iv_environment TYPE uj_appset_id iv_dimension TYPE string OPTIONAL
      RETURNING VALUE(rt_files) TYPE ty_files RAISING cx_uj_static_check zcx_abapgit_exception.
    CLASS-METHODS restore IMPORTING iv_environment TYPE uj_appset_id iv_path TYPE string
      iv_xml TYPE xstring iv_delete TYPE abap_bool RETURNING VALUE(rv_message) TYPE string.
  PRIVATE SECTION.
    CLASS-METHODS supported IMPORTING is_dimension TYPE uja_s_dimension RETURNING VALUE(rv_supported) TYPE abap_bool.
    CLASS-METHODS read IMPORTING iv_environment TYPE uj_appset_id iv_dimension TYPE uj_dim_name
      RETURNING VALUE(rt_definitions) TYPE ty_definitions
      RAISING cx_uj_static_check zcx_abapgit_exception.
    CLASS-METHODS definition IMPORTING is_dimension TYPE uja_s_dimension is_row TYPE any it_names TYPE string_table
      RETURNING VALUE(rs_definition) TYPE ty_definition RAISING zcx_abapgit_exception.
    CLASS-METHODS path IMPORTING is_definition TYPE ty_definition RETURNING VALUE(rv_path) TYPE string.
    CLASS-METHODS encode IMPORTING is_definition TYPE ty_definition RETURNING VALUE(rv_xml) TYPE xstring.
    CLASS-METHODS set_value IMPORTING iv_name TYPE string iv_value TYPE string CHANGING cs_row TYPE any
      RAISING zcx_abapgit_exception.
ENDCLASS.

CLASS zcl_bpc_git_members IMPLEMENTATION.
  METHOD can_read.
    TRY.
        cl_uj_context=>get_cur_context( )->check_task_access( uje0_cs_task_id-p0012 ).
        rv_allowed = abap_true.
      CATCH cx_uj_no_auth.
        TRY.
            cl_uj_context=>get_cur_context( )->check_task_access( 'P0133' ).
            rv_allowed = abap_true.
          CATCH cx_uj_no_auth.
            rv_allowed = abap_false.
        ENDTRY.
    ENDTRY.
  ENDMETHOD.

  METHOD get_kind.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    IF lines( lt_parts ) = 4 AND lt_parts[ 1 ] = 'DIMENSIONS' AND lt_parts[ 2 ] IS NOT INITIAL
        AND lt_parts[ 3 ] = 'MEMBERS' AND lt_parts[ 4 ] <> '.xml'
        AND substring_after( val = lt_parts[ 4 ] sub = '.' occ = -1 ) = 'xml'.
      rv_kind = 'DIMMEMBER'.
    ENDIF.
  ENDMETHOD.

  METHOD get_dimension.
    IF get_kind( iv_path ) = 'DIMMEMBER'.
      DATA lt_parts TYPE string_table.
      SPLIT iv_path AT '/' INTO TABLE lt_parts.
      rv_dimension = cl_http_utility=>unescape_url( lt_parts[ 2 ] ).
    ENDIF.
  ENDMETHOD.

  METHOD supported.
    rv_supported = xsdbool( is_dimension-hier_time_dep = abap_false AND is_dimension-ref_dim IS INITIAL ).
    LOOP AT is_dimension-attributes INTO DATA(ls_attr) WHERE time_dependent = abap_true.
      rv_supported = abap_false.
    ENDLOOP.
  ENDMETHOD.

  METHOD dimensions.
    IF can_read( ) = abap_false.
      RAISE EXCEPTION TYPE cx_uj_no_auth.
    ENDIF.
    cl_uja_dim=>get_dim_library( EXPORTING i_appset_id = iv_environment IMPORTING et_dim = DATA(lt_dims) ).
    LOOP AT lt_dims INTO DATA(ls_dim).
      TRY.
          DATA lo_dimension TYPE REF TO if_uja_dimension_manager.
          lo_dimension = NEW cl_ujaa_dimension( i_appset_id = iv_environment i_dimension_id = ls_dim-dimension ).
          lo_dimension->get( EXPORTING if_summary = abap_false IMPORTING es_dimension = DATA(ls_info) ).
          IF supported( ls_info ) = abap_true.
            APPEND ls_dim-dimension TO rt_dimensions.
          ENDIF.
        CATCH cx_uj_no_auth.
          CONTINUE.
      ENDTRY.
    ENDLOOP.
    SORT rt_dimensions.
    DELETE ADJACENT DUPLICATES FROM rt_dimensions.
  ENDMETHOD.

  METHOD path.
    rv_path = |DIMENSIONS/{ cl_http_utility=>escape_url( CONV string( is_definition-dimension ) ) }/MEMBERS/| &&
      |{ cl_http_utility=>escape_url( is_definition-id ) }.xml|.
  ENDMETHOD.

  METHOD encode.
    DATA(lo_writer) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_xml10 ).
    lo_writer->if_sxml_writer~set_option( option = if_sxml_writer=>co_opt_indent value = abap_true ).
    lo_writer->if_sxml_writer~set_option( option = if_sxml_writer=>co_opt_linebreaks value = abap_true ).
    CALL TRANSFORMATION id SOURCE definition = is_definition RESULT XML lo_writer.
    rv_xml = lo_writer->get_output( ).
  ENDMETHOD.

  METHOD definition.
    rs_definition = VALUE #( version = 1 dimension = is_dimension-dimension language = sy-langu ).
    DATA lv_index TYPE i.
    LOOP AT it_names INTO DATA(lv_name).
      lv_index = lv_index + 1.
      ASSIGN COMPONENT lv_index OF STRUCTURE is_row TO FIELD-SYMBOL(<lv_value>).
      IF sy-subrc <> 0.
        zcx_abapgit_exception=>raise( 'BPC member field layout is incomplete' ).
      ENDIF.
      CASE lv_name.
        WHEN 'ID'.
          rs_definition-id = to_upper( CONV string( <lv_value> ) ).
          IF rs_definition-name IS INITIAL.
            rs_definition-name = <lv_value>.
          ENDIF.
        WHEN 'MBR_NAME'.
          rs_definition-name = <lv_value>.
        WHEN 'EVDESCRIPTION'.
          rs_definition-description = <lv_value>.
        WHEN 'ROWFLAG' OR 'OBJVERS'.
          CONTINUE.
        WHEN OTHERS.
          READ TABLE is_dimension-attributes INTO DATA(ls_attr) WITH KEY attribute_name = lv_name.
          IF sy-subrc = 0 AND ls_attr-f_generate = abap_false.
            INSERT VALUE #( name = lv_name value = CONV string( <lv_value> ) ) INTO TABLE rs_definition-properties.
          ELSEIF line_exists( is_dimension-hierarchies[ hierarchy_name = lv_name ] ).
            INSERT VALUE #( name = lv_name value = CONV string( <lv_value> ) ) INTO TABLE rs_definition-parents.
          ENDIF.
      ENDCASE.
    ENDLOOP.
    LOOP AT is_dimension-attributes INTO ls_attr WHERE f_generate = abap_false.
      IF ls_attr-attribute_name = 'ID' OR ls_attr-attribute_name = 'MBR_NAME'
          OR ls_attr-attribute_name = 'EVDESCRIPTION' OR ls_attr-attribute_name = 'ROWFLAG'
          OR ls_attr-attribute_name = 'OBJVERS'.
        CONTINUE.
      ENDIF.
      IF NOT line_exists( rs_definition-properties[ name = ls_attr-attribute_name ] ).
        zcx_abapgit_exception=>raise( |BPC property { ls_attr-attribute_name } could not be read| ).
      ENDIF.
    ENDLOOP.
    LOOP AT is_dimension-hierarchies INTO DATA(ls_hier).
      IF NOT line_exists( rs_definition-parents[ name = ls_hier-hierarchy_name ] ).
        zcx_abapgit_exception=>raise( |BPC hierarchy { ls_hier-hierarchy_name } could not be read| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD read.
    DATA lo_dimension TYPE REF TO if_uja_dimension_manager.
    lo_dimension = NEW cl_ujaa_dimension( i_appset_id = iv_environment i_dimension_id = iv_dimension ).
    lo_dimension->get( EXPORTING if_summary = abap_false IMPORTING es_dimension = DATA(ls_dimension) ).
    IF supported( ls_dimension ) = abap_false.
      zcx_abapgit_exception=>raise( 'Time-dependent and reference dimensions are not supported yet' ).
    ENDIF.
    DATA lo_members TYPE REF TO if_uja_member_manager.
    lo_members = NEW cl_ujam_member( i_appset_id = iv_environment i_dimension_id = iv_dimension ).
    " Dynamic native rows preserve long property values beyond UJA_S_PROPERTY's 255 characters.
    DATA(lr_data) = lo_members->get_attr_names_and_members( ).
    DATA lt_names TYPE string_table.
    LOOP AT lr_data->t_field_name INTO DATA(lv_name).
      APPEND lv_name TO lt_names.
    ENDLOOP.
    FIELD-SYMBOLS <lt_members> TYPE STANDARD TABLE.
    ASSIGN lr_data->content->* TO <lt_members>.
    LOOP AT <lt_members> ASSIGNING FIELD-SYMBOL(<ls_member>).
      ASSIGN COMPONENT 'ROWFLAG' OF STRUCTURE <ls_member> TO FIELD-SYMBOL(<lv_flag>).
      IF sy-subrc = 0 AND <lv_flag> = uj00_cs_action-delete.
        CONTINUE.
      ENDIF.
      APPEND definition( is_dimension = ls_dimension is_row = <ls_member> it_names = lt_names ) TO rt_definitions.
    ENDLOOP.
  ENDMETHOD.

  METHOD list.
    DATA(lt_dimensions) = dimensions( iv_environment ).
    IF iv_dimension IS NOT INITIAL.
      IF NOT line_exists( lt_dimensions[ table_line = iv_dimension ] ).
        zcx_abapgit_exception=>raise( 'Choose an accessible non-time-dependent BPC dimension' ).
      ENDIF.
      DELETE lt_dimensions WHERE table_line <> iv_dimension.
    ENDIF.
    LOOP AT lt_dimensions INTO DATA(lv_dimension).
      DATA(lt_definitions) = read( iv_environment = iv_environment iv_dimension = lv_dimension ).
      LOOP AT lt_definitions INTO DATA(ls_definition).
        DATA(lv_path) = path( ls_definition ).
        IF ls_definition-id IS INITIAL OR line_exists( rt_files[ path = lv_path ] ).
          zcx_abapgit_exception=>raise( 'Empty or duplicate BPC member IDs cannot share a Git path' ).
        ENDIF.
        INSERT VALUE #( path = lv_path description = ls_definition-description content = encode( ls_definition ) ) INTO TABLE rt_files.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD set_value.
    ASSIGN COMPONENT iv_name OF STRUCTURE cs_row TO FIELD-SYMBOL(<lv_value>).
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( |Member field { iv_name } does not exist in the target dimension| ).
    ENDIF.
    <lv_value> = iv_value.
    IF CONV string( <lv_value> ) <> iv_value.
      zcx_abapgit_exception=>raise( |Member field { iv_name } cannot hold the Git value without changing it| ).
    ENDIF.
  ENDMETHOD.

  METHOD restore.
    TRY.
        IF can_read( ) = abap_false.
          RAISE EXCEPTION TYPE cx_uj_no_auth.
        ENDIF.
        IF iv_delete = abap_true.
          zcx_abapgit_exception=>raise( 'Delete members in BPC after checking data references; Git restore only adds or updates members' ).
        ENDIF.
        DATA ls_definition TYPE ty_definition.
        CALL TRANSFORMATION id SOURCE XML iv_xml RESULT definition = ls_definition.
        IF ls_definition-version <> 1 OR ls_definition-id IS INITIAL OR ls_definition-language <> sy-langu
            OR get_kind( iv_path ) <> 'DIMMEMBER' OR path( ls_definition ) <> iv_path
            OR to_upper( ls_definition-name ) <> ls_definition-id.
          zcx_abapgit_exception=>raise( 'Member XML identity, language or schema does not match this restore' ).
        ENDIF.
        DATA lo_dimension TYPE REF TO if_uja_dimension_manager.
        lo_dimension = NEW cl_ujaa_dimension( i_appset_id = iv_environment i_dimension_id = ls_definition-dimension ).
        lo_dimension->get( EXPORTING if_summary = abap_false IMPORTING es_dimension = DATA(ls_dimension) ).
        IF supported( ls_dimension ) = abap_false OR ls_dimension-locked = abap_true.
          zcx_abapgit_exception=>raise( 'Dimension is locked or uses an unsupported time-dependent/reference layout' ).
        ENDIF.
        DATA lt_attrs TYPE uja_t_attr_name.
        DATA lt_hiers TYPE uja_t_hier_name.
        LOOP AT ls_definition-properties INTO DATA(ls_value).
          READ TABLE ls_dimension-attributes INTO DATA(ls_attr) WITH KEY attribute_name = ls_value-name.
          IF sy-subrc <> 0 OR ls_attr-f_generate = abap_true OR ls_value-name = 'ID'
              OR ls_value-name = 'MBR_NAME' OR ls_value-name = 'ROWFLAG' OR ls_value-name = 'OBJVERS'.
            zcx_abapgit_exception=>raise( |Property { ls_value-name } is missing or not editable in the target dimension| ).
          ENDIF.
          APPEND CONV #( ls_value-name ) TO lt_attrs.
        ENDLOOP.
        LOOP AT ls_definition-parents INTO ls_value.
          IF NOT line_exists( ls_dimension-hierarchies[ hierarchy_name = ls_value-name ] ).
            zcx_abapgit_exception=>raise( |Hierarchy { ls_value-name } does not exist in the target dimension| ).
          ENDIF.
          APPEND CONV #( ls_value-name ) TO lt_hiers.
        ENDLOOP.
        DATA lt_expected_props TYPE ty_values.
        DATA lt_expected_parents TYPE ty_values.
        LOOP AT ls_dimension-attributes INTO ls_attr WHERE f_generate = abap_false.
          IF ls_attr-attribute_name <> 'ID' AND ls_attr-attribute_name <> 'MBR_NAME'
              AND ls_attr-attribute_name <> 'ROWFLAG' AND ls_attr-attribute_name <> 'OBJVERS'
              AND ls_attr-attribute_name <> 'EVDESCRIPTION'.
            INSERT VALUE #( name = ls_attr-attribute_name ) INTO TABLE lt_expected_props.
          ENDIF.
        ENDLOOP.
        LOOP AT ls_dimension-hierarchies INTO DATA(ls_hier).
          INSERT VALUE #( name = ls_hier-hierarchy_name ) INTO TABLE lt_expected_parents.
        ENDLOOP.
        DATA(lt_requested_props) = ls_definition-properties.
        DATA(lt_requested_parents) = ls_definition-parents.
        LOOP AT lt_requested_props ASSIGNING FIELD-SYMBOL(<ls_value>).
          CLEAR <ls_value>-value.
        ENDLOOP.
        LOOP AT lt_requested_parents ASSIGNING <ls_value>.
          CLEAR <ls_value>-value.
        ENDLOOP.
        IF lt_requested_props <> lt_expected_props OR lt_requested_parents <> lt_expected_parents.
          zcx_abapgit_exception=>raise( 'Dimension properties or hierarchies differ; align their definitions before restoring members' ).
        ENDIF.
        DATA lo_members TYPE REF TO if_uja_member_manager.
        lo_members = NEW cl_ujam_member( i_appset_id = iv_environment i_dimension_id = ls_definition-dimension ).
        lo_members->create_data_ref( EXPORTING i_data_type = 'T' it_attr_name = lt_attrs it_hier_name = lt_hiers
          if_with_mbr_name = abap_true IMPORTING er_data = DATA(lr_members) ).
        FIELD-SYMBOLS <lt_members> TYPE STANDARD TABLE.
        ASSIGN lr_members->* TO <lt_members>.
        APPEND INITIAL LINE TO <lt_members> ASSIGNING FIELD-SYMBOL(<ls_member>).
        set_value( EXPORTING iv_name = 'ID' iv_value = ls_definition-id CHANGING cs_row = <ls_member> ).
        set_value( EXPORTING iv_name = 'MBR_NAME' iv_value = ls_definition-name CHANGING cs_row = <ls_member> ).
        set_value( EXPORTING iv_name = 'EVDESCRIPTION' iv_value = ls_definition-description CHANGING cs_row = <ls_member> ).
        LOOP AT ls_definition-properties INTO ls_value.
          set_value( EXPORTING iv_name = ls_value-name iv_value = ls_value-value CHANGING cs_row = <ls_member> ).
        ENDLOOP.
        LOOP AT ls_definition-parents INTO ls_value.
          set_value( EXPORTING iv_name = ls_value-name iv_value = ls_value-value CHANGING cs_row = <ls_member> ).
        ENDLOOP.
        lo_members->save( EXPORTING ir_members = lr_members if_compute_flags = abap_true if_update_mode = abap_true
          IMPORTING ef_success = DATA(lv_success) et_messages = DATA(lt_messages)
          et_errors = DATA(lt_errors) et_exception_messages = DATA(lt_exceptions) ).
        IF lv_success <> abap_true OR lt_errors IS NOT INITIAL OR lt_exceptions IS NOT INITIAL.
          DATA lv_text TYPE string.
          LOOP AT lt_messages INTO DATA(ls_message).
            DATA lv_line TYPE string.
            MESSAGE ID ls_message-msgid TYPE 'S' NUMBER ls_message-msgno
              WITH ls_message-msgv1 ls_message-msgv2 ls_message-msgv3 ls_message-msgv4 INTO lv_line.
            lv_text = lv_text && lv_line && ` `.
          ENDLOOP.
          IF lv_text IS INITIAL.
            lv_text = 'BPC rejected the member values or their references'.
          ENDIF.
          zcx_abapgit_exception=>raise( lv_text ).
        ENDIF.
        DATA(lt_actual) = read( iv_environment = iv_environment iv_dimension = ls_definition-dimension ).
        READ TABLE lt_actual INTO DATA(ls_actual) WITH KEY id = ls_definition-id.
        IF sy-subrc <> 0 OR encode( ls_actual ) <> encode( ls_definition ).
          zcx_abapgit_exception=>raise( 'Restored member does not match Git; synchronization was not recorded' ).
        ENDIF.
      CATCH cx_root INTO DATA(lx_error).
        rv_message = lx_error->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
