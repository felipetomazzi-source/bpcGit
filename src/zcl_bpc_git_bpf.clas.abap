"! BPC 10 BPF design definitions; deployment and instances stay local.
CLASS zcl_bpc_git_bpf DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPE-POOLS: uje0, ujb0.
    TYPES:
      BEGIN OF ty_link,
        step_order TYPE ujb_step_order,
        role TYPE string,
        name TYPE rsbpc_fullname,
        resource_type TYPE rsbpcr_resource_type,
      END OF ty_link,
      ty_links TYPE SORTED TABLE OF ty_link WITH UNIQUE KEY step_order role,
      BEGIN OF ty_definition,
        version TYPE i,
        id TYPE ujb_bpf_tmpl_name,
        template TYPE ujb_s_api_tmpl,
        links TYPE ty_links,
      END OF ty_definition,
      BEGIN OF ty_file,
        path TYPE string,
        model TYPE string,
        content TYPE xstring,
      END OF ty_file,
      ty_files TYPE STANDARD TABLE OF ty_file WITH DEFAULT KEY.
    CLASS-METHODS can_read RETURNING VALUE(rv_allowed) TYPE abap_bool.
    CLASS-METHODS get_kind IMPORTING iv_path TYPE string RETURNING VALUE(rv_kind) TYPE string.
    CLASS-METHODS list
      IMPORTING iv_environment TYPE uj_appset_id iv_model TYPE string OPTIONAL
      RETURNING VALUE(rt_files) TYPE ty_files RAISING cx_uj_static_check zcx_abapgit_exception.
    CLASS-METHODS restore
      IMPORTING iv_environment TYPE uj_appset_id iv_path TYPE string iv_xml TYPE xstring iv_delete TYPE abap_bool
      RETURNING VALUE(rv_message) TYPE string.
  PRIVATE SECTION.
    CLASS-METHODS path IMPORTING is_definition TYPE ty_definition RETURNING VALUE(rv_path) TYPE string.
    CLASS-METHODS encode IMPORTING is_definition TYPE ty_definition RETURNING VALUE(rv_xml) TYPE xstring.
    CLASS-METHODS definition
      IMPORTING is_header TYPE ujb_s_api_tmpl_hdr is_template TYPE ujb_s_api_tmpl
      RETURNING VALUE(rs_definition) TYPE ty_definition RAISING zcx_abapgit_exception.
    CLASS-METHODS local_workspace
      IMPORTING is_template TYPE ujb_s_api_tmpl is_link TYPE ty_link
      RETURNING VALUE(rs_aws) TYPE ujb_s_aws.
    CLASS-METHODS normalize CHANGING cs_data TYPE any RAISING zcx_abapgit_exception.
    CLASS-METHODS localize IMPORTING iv_environment TYPE uj_appset_id CHANGING cs_data TYPE any
      RAISING zcx_abapgit_exception.
    CLASS-METHODS check_result IMPORTING iv_success TYPE uj_flg it_messages TYPE uj0_t_message
      RAISING zcx_abapgit_exception.
ENDCLASS.

CLASS zcl_bpc_git_bpf IMPLEMENTATION.
  METHOD can_read.
    TRY.
        cl_uj_context=>get_cur_context( )->check_task_access( uje0_cs_task_id-p0043 ).
        rv_allowed = abap_true.
      CATCH cx_uj_no_auth.
        rv_allowed = abap_false.
    ENDTRY.
  ENDMETHOD.

  METHOD get_kind.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    IF lines( lt_parts ) = 3 AND lt_parts[ 1 ] IS NOT INITIAL AND lt_parts[ 2 ] = 'BPF'
        AND lt_parts[ 3 ] <> '.xml' AND substring_after( val = lt_parts[ 3 ] sub = '.' occ = -1 ) = 'xml'.
      rv_kind = 'BPF'.
    ENDIF.
  ENDMETHOD.

  METHOD path.
    rv_path = |{ is_definition-template-control_appl_id }/BPF/{ cl_http_utility=>escape_url( CONV string( is_definition-id ) ) }.xml|.
  ENDMETHOD.

  METHOD encode.
    DATA(lo_writer) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_xml10 ).
    lo_writer->if_sxml_writer~set_option( option = if_sxml_writer=>co_opt_indent value = abap_true ).
    lo_writer->if_sxml_writer~set_option( option = if_sxml_writer=>co_opt_linebreaks value = abap_true ).
    CALL TRANSFORMATION id SOURCE definition = is_definition RESULT XML lo_writer.
    rv_xml = lo_writer->get_output( ).
  ENDMETHOD.

  METHOD check_result.
    IF iv_success = abap_true.
      RETURN.
    ENDIF.
    DATA lv_text TYPE string.
    LOOP AT it_messages INTO DATA(ls_message).
      DATA lv_line TYPE string.
      MESSAGE ID ls_message-msgid TYPE 'S' NUMBER ls_message-msgno
        WITH ls_message-msgv1 ls_message-msgv2 ls_message-msgv3 ls_message-msgv4 INTO lv_line.
      lv_text = lv_text && lv_line && ` `.
    ENDLOOP.
    IF lv_text IS INITIAL.
      lv_text = 'BPC could not process the BPF definition'.
    ENDIF.
    zcx_abapgit_exception=>raise( lv_text ).
  ENDMETHOD.

  METHOD definition.
    rs_definition = VALUE #( version = 1 id = is_header-tech_name template = is_template ).
    CLEAR rs_definition-template-name.
    SORT rs_definition-template-steps BY step_order.
    LOOP AT rs_definition-template-steps ASSIGNING FIELD-SYMBOL(<ls_design_step>).
      SORT <ls_design_step>-drive_dimension-members BY member_name hier_name formula hier_level
        attribute_name attribute_sign attribute_option attribute_low attribute_high.
    ENDLOOP.
    LOOP AT is_template-steps INTO DATA(ls_step).
      DO 2 TIMES.
        DATA(lv_role) = COND string( WHEN sy-index = 1 THEN 'PERF' ELSE 'REVW' ).
        DATA(lv_uuid) = COND #( WHEN lv_role = 'PERF' THEN ls_step-perf_aws ELSE ls_step-revw_aws ).
        IF lv_uuid IS INITIAL.
          CONTINUE.
        ENDIF.
        READ TABLE ls_step-aws_list INTO DATA(ls_aws) WITH KEY uuid = lv_uuid.
        IF sy-subrc <> 0 OR ls_aws-name IS INITIAL.
          zcx_abapgit_exception=>raise( 'A BPF activity workspace could not be read; its link cannot be exported' ).
        ENDIF.
        INSERT VALUE #( step_order = ls_step-step_order role = lv_role name = ls_aws-name
          resource_type = ls_aws-type ) INTO TABLE rs_definition-links.
        IF sy-subrc <> 0.
          zcx_abapgit_exception=>raise( 'Duplicate BPF activity order; resolve it in BPC before tracking' ).
        ENDIF.
      ENDDO.
    ENDLOOP.
    normalize( CHANGING cs_data = rs_definition-template ).
  ENDMETHOD.

  METHOD normalize.
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( cs_data ).
    CASE lo_type->kind.
      WHEN cl_abap_typedescr=>kind_struct.
        DATA lo_struct TYPE REF TO cl_abap_structdescr.
        lo_struct ?= lo_type.
        LOOP AT lo_struct->components INTO DATA(ls_component).
          ASSIGN COMPONENT ls_component-name OF STRUCTURE cs_data TO FIELD-SYMBOL(<lv_value>).
          CASE ls_component-name.
            WHEN 'APPSET_ID' OR 'TMPL_ID' OR 'TMPL_GUID' OR 'STEP_ID' OR 'DRV_ID' OR 'MEM_ITEM_ID'
              OR 'PARENT_STEP_ID' OR 'ACTION_ID' OR 'STATUS' OR 'LOG_SYS' OR 'VERSION_CREATOR'
              OR 'VERSION_TIMESTAM' OR 'LOCKED_BY' OR 'LOCKED_TIMESTAMP' OR 'HAS_INST' OR 'HAS_ARC_INST'
              OR 'IS_VALID' OR 'FOR_TRANPORT' OR 'ACTIVATE_USER' OR 'ACTIVATE_TMESTMP'
              OR 'DIM_DESC' OR 'APPL_DESC' OR 'MEMBER_DESC' OR 'ACCESSES' OR 'AWS_LIST' OR 'PERF_AWS' OR 'REVW_AWS'.
              CLEAR <lv_value>.
            WHEN OTHERS.
              normalize( CHANGING cs_data = <lv_value> ).
          ENDCASE.
        ENDLOOP.
      WHEN cl_abap_typedescr=>kind_table.
        FIELD-SYMBOLS <lt_table> TYPE ANY TABLE.
        ASSIGN cs_data TO <lt_table>.
        " Rebuild tables: sorted/hashed keys may include local IDs.
        DATA lr_table TYPE REF TO data.
        DATA lr_row TYPE REF TO data.
        CREATE DATA lr_table LIKE cs_data.
        CREATE DATA lr_row LIKE LINE OF <lt_table>.
        FIELD-SYMBOLS <lt_copy> TYPE ANY TABLE.
        ASSIGN lr_table->* TO <lt_copy>.
        ASSIGN lr_row->* TO FIELD-SYMBOL(<ls_copy>).
        LOOP AT <lt_table> ASSIGNING FIELD-SYMBOL(<ls_row>).
          <ls_copy> = <ls_row>.
          normalize( CHANGING cs_data = <ls_copy> ).
          INSERT <ls_copy> INTO TABLE <lt_copy>.
          IF sy-subrc <> 0.
            zcx_abapgit_exception=>raise( 'BPF definition has colliding portable keys' ).
          ENDIF.
        ENDLOOP.
        cs_data = <lt_copy>.
    ENDCASE.
  ENDMETHOD.

  METHOD list.
    IF can_read( ) = abap_false.
      RAISE EXCEPTION TYPE cx_uj_no_auth.
    ENDIF.
    DATA(ls_user) = VALUE uj0_s_user( user_id = sy-uname langu = sy-langu ).
    DATA(lo_manager) = NEW cl_ujb_10_tmpl_mgr( i_appset_id = iv_environment is_user = ls_user ).
    cl_ujb_10_tmpl_hdr=>get_template_list( EXPORTING i_appset_id = iv_environment is_user = ls_user
      IMPORTING et_template_hdrs = DATA(lt_headers) ).
    LOOP AT lt_headers INTO DATA(ls_header).
      DATA(lv_id) = ls_header-edit_version.
      IF lv_id IS INITIAL.
        lv_id = ls_header-active_version.
      ENDIF.
      IF lv_id IS INITIAL.
        cl_ujb_10_tmpl_hdr=>get_tmpl_latest_by_tmpl_guid( EXPORTING i_appset_id = iv_environment
          i_tmpl_guid = ls_header-tmpl_guid IMPORTING rv_latest_tmpl_id = lv_id ).
      ENDIF.
      IF lv_id IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA lv_model TYPE uj_appl_id.
      CLEAR lv_model.
      SELECT SINGLE control_appl_id FROM ujb_tmpl INTO @lv_model
        WHERE appset_id = @iv_environment AND tmpl_id = @lv_id.
      IF iv_model IS NOT INITIAL AND lv_model <> iv_model.
        CONTINUE.
      ENDIF.
      lo_manager->get_version_full_template( EXPORTING i_appset_id = iv_environment i_template_id = lv_id
        if_load_mdata = abap_false IMPORTING es_template = DATA(ls_template) e_success = DATA(lv_success)
        et_message_lines = DATA(lt_messages) ).
      check_result( iv_success = lv_success it_messages = lt_messages ).
      DATA(ls_definition) = definition( is_header = ls_header is_template = ls_template ).
      DATA(lv_path) = path( ls_definition ).
      IF line_exists( rt_files[ path = lv_path ] ).
        zcx_abapgit_exception=>raise( 'Duplicate BPF technical names cannot share a Git path' ).
      ENDIF.
      APPEND VALUE #( path = lv_path model = ls_template-control_appl_id content = encode( ls_definition ) ) TO rt_files.
    ENDLOOP.
  ENDMETHOD.

  METHOD restore.
    DATA lo_manager TYPE REF TO cl_ujb_10_tmpl_mgr.
    DATA lo_header TYPE REF TO cl_ujb_10_tmpl_hdr.
    DATA lv_guid TYPE ujb_tmpl_guid.
    DATA lv_locked TYPE abap_bool.
    TRY.
        cl_uj_context=>get_cur_context( )->check_task_access( uje0_cs_task_id-p0043 ).
        IF iv_delete = abap_true.
          zcx_abapgit_exception=>raise( 'Delete or archive BPF templates in BPC; Git restore preserves deployed versions and instances' ).
        ENDIF.
        DATA ls_definition TYPE ty_definition.
        CALL TRANSFORMATION id SOURCE XML iv_xml RESULT definition = ls_definition.
        IF ls_definition-version <> 1 OR ls_definition-id IS INITIAL OR get_kind( iv_path ) <> 'BPF'
            OR path( ls_definition ) <> iv_path.
          zcx_abapgit_exception=>raise( 'BPF XML identity or schema version does not match the selected path' ).
        ENDIF.
        " Reject runtime IDs/assignments rather than accepting them from Git.
        DATA(ls_canonical) = ls_definition.
        normalize( CHANGING cs_data = ls_canonical-template ).
        IF ls_canonical-template <> ls_definition-template OR ls_definition-template-name IS NOT INITIAL.
          zcx_abapgit_exception=>raise( 'BPF XML must contain portable design fields only' ).
        ENDIF.
        DATA(ls_user) = VALUE uj0_s_user( user_id = sy-uname langu = sy-langu ).
        lo_manager = NEW #( i_appset_id = iv_environment is_user = ls_user ).
        DATA(ls_template) = ls_definition-template.
        DATA lt_orders TYPE SORTED TABLE OF ujb_step_order WITH UNIQUE KEY table_line.
        LOOP AT ls_template-steps INTO DATA(ls_design_step).
          INSERT ls_design_step-step_order INTO TABLE lt_orders.
          IF sy-subrc <> 0 OR ls_design_step-actions IS NOT INITIAL OR ls_design_step-substeps IS NOT INITIAL.
            zcx_abapgit_exception=>raise( 'BPF needs unique activity orders and BPC 10 activities without legacy actions/substeps' ).
          ENDIF.
        ENDLOOP.
        DATA(lo_appset) = cl_uja_bpc_admin_factory=>get_appset_manager( i_appset_id = iv_environment ).
        lo_appset->get_applications( EXPORTING if_summary = abap_true IMPORTING et_applications = DATA(lt_models) ).
        IF NOT line_exists( lt_models[ application_id = ls_template-control_appl_id ] ).
          zcx_abapgit_exception=>raise( 'The BPF controlling model does not exist in this environment' ).
        ENDIF.
        cl_ujb_10_tmpl_hdr=>get_template_list( EXPORTING i_appset_id = iv_environment is_user = ls_user
          IMPORTING et_template_hdrs = DATA(lt_headers) ).
        DELETE lt_headers WHERE tech_name <> ls_definition-id.
        IF lines( lt_headers ) > 1.
          zcx_abapgit_exception=>raise( 'The BPF technical name is ambiguous in this environment' ).
        ENDIF.
        IF lt_headers IS NOT INITIAL.
          DATA(ls_header) = lt_headers[ 1 ].
          lv_guid = ls_header-tmpl_guid.
          IF ls_header-locked_by IS NOT INITIAL.
            zcx_abapgit_exception=>raise( 'BPF template is open for editing; close it in BPC before restoring' ).
          ENDIF.
          lo_header = cl_ujb_10_tmpl_hdr=>get_obj_by_tmpl_guid( i_appset_id = iv_environment i_tmpl_guid = lv_guid ).
          lo_header->acquire_writelock( ).
          SELECT SINGLE * FROM ujb_tmpl_hdr INTO @DATA(ls_locked_header)
            WHERE appset_id = @iv_environment AND tmpl_guid = @lv_guid.
          IF sy-subrc <> 0 OR ls_locked_header-locked_by IS NOT INITIAL
              OR ls_locked_header-edit_version <> ls_header-edit_version
              OR ls_locked_header-active_version <> ls_header-active_version.
            zcx_abapgit_exception=>raise( 'BPF changed or was opened for editing; reload and try again' ).
          ENDIF.
          DATA(lv_source) = COND #( WHEN ls_header-edit_version IS NOT INITIAL THEN ls_header-edit_version ELSE ls_header-active_version ).
          IF lv_source IS INITIAL.
            cl_ujb_10_tmpl_hdr=>get_tmpl_latest_by_tmpl_guid( EXPORTING i_appset_id = iv_environment
              i_tmpl_guid = lv_guid IMPORTING rv_latest_tmpl_id = lv_source ).
          ENDIF.
          lo_manager->get_version_full_template( EXPORTING i_appset_id = iv_environment i_template_id = lv_source
            if_load_mdata = abap_false IMPORTING es_template = DATA(ls_source)
            e_success = DATA(lv_success) et_message_lines = DATA(lt_messages) ).
          check_result( iv_success = lv_success it_messages = lt_messages ).
          IF ls_source-control_appl_id <> ls_template-control_appl_id.
            zcx_abapgit_exception=>raise( 'The local BPF has a different controlling model; resolve it in BPC first' ).
          ENDIF.
          IF ls_header-edit_version IS NOT INITIAL.
            IF ls_source-status <> ujb0_cs_tmpl_status-edit OR ls_source-has_inst = abap_true
                OR ls_source-has_arc_inst = abap_true.
              zcx_abapgit_exception=>raise( 'The BPF edit version is deployed or has instances; resolve it in BPC first' ).
            ENDIF.
            lo_manager->check_if_version_is_local( EXPORTING i_appset_id = iv_environment i_tmpl_id = lv_source ).
          ENDIF.
        ENDIF.
        " Resolve dependencies, preferring this activity's existing local workspace.
        DATA lo_resources TYPE REF TO if_rsbpcr_res_manager.
        lo_resources = NEW cl_rsbpcr_res_manager( ).
        DATA(lo_aws) = NEW cl_ujb_aws_internal( ).
        LOOP AT ls_definition-links INTO DATA(ls_link).
          READ TABLE ls_template-steps ASSIGNING FIELD-SYMBOL(<ls_step>) WITH KEY step_order = ls_link-step_order.
          IF sy-subrc <> 0 OR ( ls_link-role <> 'PERF' AND ls_link-role <> 'REVW' ).
            zcx_abapgit_exception=>raise( 'BPF workspace link refers to an invalid activity or role' ).
          ENDIF.
          DATA(ls_aws) = local_workspace( is_template = ls_source is_link = ls_link ).
          IF ls_aws-uuid IS INITIAL.
            lo_resources->search( EXPORTING i_model_type = if_rsbpcr_res_provider=>n_c_connection_type_classic
              i_appset_id = iv_environment i_f_design_time = abap_true
              i_t_filter = VALUE #( ( keyword = if_rsbpcr_res_manager=>n_c_filter_res_name value = ls_link-name ) )
              IMPORTING e_t_res_node = DATA(lt_resources) ).
            DELETE lt_resources WHERE name <> ls_link-name OR resource_type <> ls_link-resource_type.
            SORT lt_resources BY resource_id.
            DELETE ADJACENT DUPLICATES FROM lt_resources COMPARING resource_id.
            IF lines( lt_resources ) <> 1.
              zcx_abapgit_exception=>raise( |Workspace { ls_link-name } must exist uniquely in the target environment| ).
            ENDIF.
            lo_resources->get( EXPORTING i_model_type = if_rsbpcr_res_provider=>n_c_connection_type_classic
              i_appset_id = iv_environment i_resource_id = lt_resources[ 1 ]-resource_id
              IMPORTING e_s_resource = DATA(ls_resource) ).
            ls_aws = lo_aws->map_res_to_aws( ls_resource ).
          ENDIF.
          IF NOT line_exists( <ls_step>-aws_list[ uuid = ls_aws-uuid ] ).
            INSERT ls_aws INTO TABLE <ls_step>-aws_list.
          ENDIF.
          IF ls_link-role = 'PERF'.
            <ls_step>-perf_aws = ls_aws-uuid.
          ELSE.
            <ls_step>-revw_aws = ls_aws-uuid.
          ENDIF.
        ENDLOOP.
        localize( EXPORTING iv_environment = iv_environment CHANGING cs_data = ls_template ).
        ls_template-status = ujb0_cs_tmpl_status-edit.
        IF lt_headers IS NOT INITIAL.
          lv_locked = abap_true.
          lo_manager->create_template_edit_version( EXPORTING i_appset_id = iv_environment is_user = ls_user
            i_tmpl_guid = lv_guid i_src_tmpl_id = lv_source IMPORTING e_tmpl_id = DATA(lv_edit)
            e_success = lv_success et_message_lines = lt_messages ).
          check_result( iv_success = lv_success it_messages = lt_messages ).
          lo_manager->get_version_full_template( EXPORTING i_appset_id = iv_environment i_template_id = lv_edit
            IMPORTING es_template = DATA(ls_local) e_success = lv_success et_message_lines = lt_messages ).
          check_result( iv_success = lv_success it_messages = lt_messages ).
          " Native edit-version creation copies activity workspaces. Reuse those
          " copies for unchanged links rather than attaching a deployed resource.
          LOOP AT ls_definition-links INTO ls_link.
            ls_aws = local_workspace( is_template = ls_local is_link = ls_link ).
            IF ls_aws-uuid IS INITIAL.
              CONTINUE.
            ENDIF.
            READ TABLE ls_template-steps ASSIGNING <ls_step> WITH KEY step_order = ls_link-step_order.
            IF NOT line_exists( <ls_step>-aws_list[ uuid = ls_aws-uuid ] ).
              INSERT ls_aws INTO TABLE <ls_step>-aws_list.
            ENDIF.
            IF ls_link-role = 'PERF'.
              <ls_step>-perf_aws = ls_aws-uuid.
            ELSE.
              <ls_step>-revw_aws = ls_aws-uuid.
            ENDIF.
          ENDLOOP.
          ls_template-tmpl_guid = lv_guid.
          ls_template-tmpl_id = lv_edit.
          ls_template-name = ls_local-name.
          ls_template-accesses = ls_local-accesses.
          ls_template-log_sys = ls_local-log_sys.
          lo_manager->save_version_full_template( EXPORTING is_template = ls_template is_user = ls_user if_modify = abap_true
            IMPORTING e_tmpl_id = lv_edit e_success = lv_success et_message_lines = lt_messages ).
        ELSE.
          ls_template-name = 'Git draft'.
          lo_manager->create_template( EXPORTING is_tmplate_hdr = VALUE #( appset_id = iv_environment name = ls_definition-id )
            is_template = ls_template is_user = ls_user IMPORTING e_tmpl_guid = lv_guid e_tmpl_id = lv_edit
            e_success = lv_success et_message_lines = lt_messages ).
          lv_locked = xsdbool( lv_guid IS NOT INITIAL ).
        ENDIF.
        check_result( iv_success = lv_success it_messages = lt_messages ).
        lo_manager->get_template_hdr( EXPORTING i_appset_id = iv_environment i_tmpl_guid = lv_guid
          IMPORTING es_tmpl_hdr = ls_header e_success = lv_success et_message_lines = lt_messages ).
        check_result( iv_success = lv_success it_messages = lt_messages ).
        IF lt_headers IS NOT INITIAL AND ls_header-active_version <> lt_headers[ 1 ]-active_version.
          zcx_abapgit_exception=>raise( 'BPF deployed version changed during restore; synchronization was not recorded' ).
        ENDIF.
        lo_manager->get_version_full_template( EXPORTING i_appset_id = iv_environment i_template_id = lv_edit
          if_load_mdata = abap_false IMPORTING es_template = ls_local e_success = lv_success et_message_lines = lt_messages ).
        check_result( iv_success = lv_success it_messages = lt_messages ).
        DATA(ls_actual) = definition( is_header = ls_header is_template = ls_local ).
        IF encode( ls_actual ) <> encode( ls_definition ).
          zcx_abapgit_exception=>raise( 'Restored BPF design differs from Git; synchronization was not recorded' ).
        ENDIF.
      CATCH cx_root INTO DATA(lx_error).
        rv_message = lx_error->get_text( ).
    ENDTRY.
    IF lv_locked = abap_true AND lo_manager IS BOUND.
      lo_manager->set_template_lock( EXPORTING i_appset_id = iv_environment is_user = ls_user
        i_tmpl_guid = lv_guid iv_lock = abap_false if_audit = abap_false
        IMPORTING e_success = lv_success et_message_lines = lt_messages ).
      IF lv_success <> abap_true AND rv_message IS INITIAL.
        rv_message = 'BPC could not release the template editing lock; restore was not marked successful'.
      ENDIF.
    ENDIF.
    IF lo_header IS BOUND.
      lo_header->release_writelock( ).
    ENDIF.
  ENDMETHOD.

  METHOD local_workspace.
    READ TABLE is_template-steps INTO DATA(ls_step) WITH KEY step_order = is_link-step_order.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(lv_uuid) = COND #( WHEN is_link-role = 'PERF' THEN ls_step-perf_aws ELSE ls_step-revw_aws ).
    READ TABLE ls_step-aws_list INTO rs_aws WITH KEY uuid = lv_uuid.
    IF sy-subrc <> 0 OR rs_aws-name <> is_link-name OR rs_aws-type <> is_link-resource_type.
      CLEAR rs_aws.
    ENDIF.
  ENDMETHOD.

  METHOD localize.
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( cs_data ).
    CASE lo_type->kind.
      WHEN cl_abap_typedescr=>kind_struct.
        DATA lo_struct TYPE REF TO cl_abap_structdescr.
        lo_struct ?= lo_type.
        LOOP AT lo_struct->components INTO DATA(ls_component).
          ASSIGN COMPONENT ls_component-name OF STRUCTURE cs_data TO FIELD-SYMBOL(<lv_value>).
          IF ls_component-name = 'APPSET_ID'.
            <lv_value> = iv_environment.
          ELSE.
            localize( EXPORTING iv_environment = iv_environment CHANGING cs_data = <lv_value> ).
          ENDIF.
        ENDLOOP.
      WHEN cl_abap_typedescr=>kind_table.
        FIELD-SYMBOLS <lt_table> TYPE ANY TABLE.
        ASSIGN cs_data TO <lt_table>.
        " Rebuild tables: sorted/hashed keys may include local IDs.
        DATA lr_table TYPE REF TO data.
        DATA lr_row TYPE REF TO data.
        CREATE DATA lr_table LIKE cs_data.
        CREATE DATA lr_row LIKE LINE OF <lt_table>.
        FIELD-SYMBOLS <lt_copy> TYPE ANY TABLE.
        ASSIGN lr_table->* TO <lt_copy>.
        ASSIGN lr_row->* TO FIELD-SYMBOL(<ls_copy>).
        LOOP AT <lt_table> ASSIGNING FIELD-SYMBOL(<ls_row>).
          <ls_copy> = <ls_row>.
          localize( EXPORTING iv_environment = iv_environment CHANGING cs_data = <ls_copy> ).
          INSERT <ls_copy> INTO TABLE <lt_copy>.
          IF sy-subrc <> 0.
            zcx_abapgit_exception=>raise( 'BPF definition has colliding portable keys' ).
          ENDIF.
        ENDLOOP.
        cs_data = <lt_copy>.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.
