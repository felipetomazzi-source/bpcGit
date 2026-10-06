"! Records restored BPC objects in a customizing transport request, the way
"! BPC's own transport (CL_UJT_TRANS_MGR) does: each object is an entry
"! R3TR <tlogo> <GUID>, with the GUID mapped to the BPC entity in UJT_GUID.
"! BPC exports the object's content when the request is released and imports
"! it in the target system (UJT_TLOGO_AFTER_IMPORT).
CLASS zcl_bpc_git_transport DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_entity,
        "! Repository path that was restored
        path           TYPE string,
        application_id TYPE uj_appl_id,
        "! BPC transport entity (UJT_ENTITY_CLASS); initial if not transported
        entity_type    TYPE uj_entity_type,
        entity_id      TYPE uj_entityid,
        "! Why the object is not transported, when entity_type is initial
        note           TYPE string,
      END OF ty_entity,
      ty_entities TYPE STANDARD TABLE OF ty_entity WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_request,
        request TYPE trkorr,
        text    TYPE as4text,
        owner   TYPE as4user,
        date    TYPE as4date,
      END OF ty_request,
      ty_requests TYPE STANDARD TABLE OF ty_request WITH DEFAULT KEY.
    CONSTANTS c_max_text TYPE i VALUE 60.

    "! Open customizing requests of this client in which the user has an open task.
    CLASS-METHODS open_requests
      RETURNING VALUE(rt_requests) TYPE ty_requests.
    "! Creates a customizing request with a task for the user, on the default
    "! transport layer (target), as BPC does.
    CLASS-METHODS create_request
      IMPORTING iv_text TYPE string
      EXPORTING ev_request TYPE trkorr ev_error TYPE string.
    "! Error text unless the request is an open customizing request of this
    "! client with an open task of the user.
    CLASS-METHODS check_request
      IMPORTING iv_request TYPE trkorr
      RETURNING VALUE(rv_error) TYPE string.
    "! BPC entity of a restored repository path. Packages and links need their
    "! Git definition and are mapped with package_entity and link_entity.
    CLASS-METHODS entity_for_path
      IMPORTING iv_environment TYPE uj_appset_id iv_kind TYPE string iv_path TYPE string
      RETURNING VALUE(rs_entity) TYPE ty_entity.
    CLASS-METHODS package_entity
      IMPORTING iv_path TYPE string iv_model TYPE string iv_team TYPE uj_team_id
                iv_group TYPE uj_pack_grp_id iv_package TYPE uj_package_id
      RETURNING VALUE(rs_entity) TYPE ty_entity.
    CLASS-METHODS link_entity
      IMPORTING iv_path TYPE string iv_model TYPE string iv_name TYPE string
      RETURNING VALUE(rs_entity) TYPE ty_entity.
    "! Adds the entities (duplicates once) to the user's task of the request.
    "! ev_count is the number of transport entries in the request for them.
    CLASS-METHODS record
      IMPORTING iv_environment TYPE uj_appset_id iv_request TYPE trkorr it_entities TYPE ty_entities
      EXPORTING ev_count TYPE i ev_error TYPE string.
  PRIVATE SECTION.
    CONSTANTS c_rstlogo TYPE uj_rstlogo VALUE 'ABPC'.
    CONSTANTS c_customizing TYPE trfunction VALUE 'W'.
    CONSTANTS c_customizing_task TYPE trfunction VALUE 'Q'.
    CONSTANTS c_modifiable TYPE trstatus VALUE 'D'.
    CLASS-METHODS user_task
      IMPORTING iv_request TYPE trkorr
      RETURNING VALUE(rv_task) TYPE trkorr.
    CLASS-METHODS file_entity_id
      IMPORTING iv_rest TYPE string iv_strip_type TYPE abap_bool
      RETURNING VALUE(rv_id) TYPE string.
    CLASS-METHODS unescape_name
      IMPORTING iv_path TYPE string
      RETURNING VALUE(rv_name) TYPE string.
ENDCLASS.

CLASS zcl_bpc_git_transport IMPLEMENTATION.
  METHOD open_requests.
    SELECT r~trkorr AS request, t~as4text AS text, r~as4user AS owner, r~as4date AS date
      FROM e070 AS r
      INNER JOIN e070c AS c ON c~trkorr = r~trkorr
      LEFT OUTER JOIN e07t AS t ON t~trkorr = r~trkorr AND t~langu = @sy-langu
      WHERE r~trfunction = @c_customizing AND r~trstatus = @c_modifiable AND r~strkorr = @space
        AND c~client = @sy-mandt
        AND EXISTS ( SELECT trkorr FROM e070 WHERE strkorr = r~trkorr AND as4user = @sy-uname
                                                AND trstatus = @c_modifiable )
      ORDER BY r~as4date DESCENDING, r~trkorr DESCENDING
      INTO CORRESPONDING FIELDS OF TABLE @rt_requests
      UP TO 200 ROWS.
    LOOP AT rt_requests ASSIGNING FIELD-SYMBOL(<ls_request>) WHERE text IS INITIAL.
      SELECT SINGLE as4text FROM e07t WHERE trkorr = @<ls_request>-request INTO @<ls_request>-text.
    ENDLOOP.
  ENDMETHOD.

  METHOD create_request.
    CLEAR: ev_request, ev_error.
    IF iv_text IS INITIAL OR strlen( iv_text ) > c_max_text.
      ev_error = |Enter a request description of 1 to { c_max_text } characters|.
      RETURN.
    ENDIF.
    DATA ls_header TYPE trwbo_request_header.
    DATA lt_users TYPE scts_users.
    APPEND VALUE #( user = sy-uname type = c_customizing_task ) TO lt_users.
    " No target: the default transport layer of this client applies.
    CALL FUNCTION 'TR_INSERT_REQUEST_WITH_TASKS'
      EXPORTING
        iv_type           = c_customizing
        iv_text           = CONV as4text( iv_text )
        iv_owner          = sy-uname
        it_users          = lt_users
      IMPORTING
        es_request_header = ls_header
      EXCEPTIONS
        insert_failed     = 1
        enqueue_failed    = 2
        OTHERS            = 3.
    IF sy-subrc <> 0 OR ls_header-trkorr IS INITIAL.
      DATA lv_text TYPE string.
      IF sy-msgid IS NOT INITIAL.
        MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_text.
      ENDIF.
      ROLLBACK WORK.
      ev_error = `Cannot create the transport request` && COND string( WHEN lv_text IS NOT INITIAL THEN |: { lv_text }| ).
      RETURN.
    ENDIF.
    COMMIT WORK AND WAIT.
    ev_request = ls_header-trkorr.
  ENDMETHOD.

  METHOD check_request.
    IF iv_request IS INITIAL.
      rv_error = 'Choose a transport request'.
      RETURN.
    ENDIF.
    SELECT SINGLE r~trfunction, r~trstatus, r~strkorr, c~client
      FROM e070 AS r LEFT OUTER JOIN e070c AS c ON c~trkorr = r~trkorr
      WHERE r~trkorr = @iv_request
      INTO @DATA(ls_request).
    IF sy-subrc <> 0.
      rv_error = |Transport request { iv_request } does not exist|.
    ELSEIF ls_request-strkorr IS NOT INITIAL OR ls_request-trfunction <> c_customizing.
      rv_error = |{ iv_request } is not a customizing request|.
    ELSEIF ls_request-trstatus <> c_modifiable.
      rv_error = |Transport request { iv_request } is already released|.
    ELSEIF ls_request-client <> sy-mandt.
      rv_error = |Transport request { iv_request } belongs to client { ls_request-client }|.
    ELSEIF user_task( iv_request ) IS INITIAL.
      rv_error = |You have no open task in transport request { iv_request }|.
    ENDIF.
  ENDMETHOD.

  METHOD user_task.
    SELECT SINGLE trkorr FROM e070
      WHERE strkorr = @iv_request AND as4user = @sy-uname AND trstatus = @c_modifiable
      INTO @rv_task.
  ENDMETHOD.

  METHOD entity_for_path.
    rs_entity-path = iv_path.
    DATA lt_parts TYPE string_table.
    SPLIT iv_path AT '/' INTO TABLE lt_parts.
    IF lt_parts IS INITIAL.
      rs_entity-note = 'Not a BPC object path'.
      RETURN.
    ENDIF.
    DATA(lv_rest) = substring_after( val = iv_path sub = '/' ).
    CASE iv_kind.
      WHEN zcl_bpc_git_service=>c_kind-workbook.
        rs_entity-application_id = to_upper( lt_parts[ 1 ] ).
        rs_entity-entity_type = 'AFLE'.
        rs_entity-entity_id = file_entity_id( iv_rest = lv_rest iv_strip_type = abap_false ).
      WHEN zcl_bpc_git_service=>c_kind-transformation OR zcl_bpc_git_service=>c_kind-conversion.
        " The definition and its workbook are one Data Manager file entity.
        rs_entity-application_id = to_upper( lt_parts[ 1 ] ).
        rs_entity-entity_type = 'ADMF'.
        rs_entity-entity_id = file_entity_id( iv_rest = lv_rest iv_strip_type = abap_true ).
      WHEN zcl_bpc_git_service=>c_kind-script.
        " BPC transports the logic script folder of a model as one entity.
        IF lines( lt_parts ) >= 2.
          rs_entity-application_id = to_upper( lt_parts[ 2 ] ).
          rs_entity-entity_type = 'ASPR'.
          rs_entity-entity_id = |ADMINAPP\\{ rs_entity-application_id }|.
        ENDIF.
      WHEN zcl_bpc_git_service=>c_kind-dimmember.
        " BPC transports all members of a dimension together.
        rs_entity-entity_type = 'AMBR'.
        rs_entity-entity_id = to_upper( zcl_bpc_git_members=>get_dimension( iv_path ) ).
      WHEN zcl_bpc_git_service=>c_kind-bpf.
        DATA(lv_name) = CONV ujb_bpf_tmpl_name( unescape_name( iv_path ) ).
        SELECT SINGLE tmpl_guid FROM ujb_tmpl_hdr
          WHERE appset_id = @iv_environment AND tech_name = @lv_name
          INTO @DATA(lv_template).
        IF sy-subrc = 0.
          rs_entity-entity_type = 'ABPF'.
          rs_entity-entity_id = lv_template.
        ELSE.
          rs_entity-note = |BPF template { lv_name } not found in BPC|.
        ENDIF.
      WHEN zcl_bpc_git_service=>c_kind-team.
        rs_entity-entity_type = 'ATEM'.
        rs_entity-entity_id = unescape_name( iv_path ).
      WHEN zcl_bpc_git_service=>c_kind-taskprofile.
        rs_entity-entity_type = 'ATPF'.
        rs_entity-entity_id = unescape_name( iv_path ).
      WHEN zcl_bpc_git_service=>c_kind-dataprofile.
        rs_entity-entity_type = 'ADAF'.
        rs_entity-entity_id = unescape_name( iv_path ).
      WHEN OTHERS.
        rs_entity-note = 'This object type is not transported by bpcGit'.
    ENDCASE.
    IF rs_entity-entity_type IS NOT INITIAL AND rs_entity-entity_id IS INITIAL.
      CLEAR rs_entity-entity_type.
      rs_entity-note = 'Cannot determine the BPC object of this path'.
    ENDIF.
  ENDMETHOD.

  METHOD package_entity.
    rs_entity = VALUE #( path = iv_path application_id = to_upper( iv_model ) entity_type = 'ADMP'
      entity_id = cl_ujd_entity_admp=>concat_entity_id( i_team_id = iv_team i_group_id = iv_group
                                                        i_package_id = iv_package ) ).
  ENDMETHOD.

  METHOD link_entity.
    rs_entity = VALUE #( path = iv_path application_id = to_upper( iv_model ) entity_type = 'ADML'
      entity_id = iv_name ).
    IF iv_name IS INITIAL.
      CLEAR rs_entity-entity_type.
      rs_entity-note = 'Package link has no name'.
    ENDIF.
  ENDMETHOD.

  METHOD file_entity_id.
    " <model>/EEXCEL/... is COMPANY\EEXCEL\...; <model>/TEAM FILES/<team>/...
    " is <team>\..., as BPC names its file entities.
    rv_id = COND #( WHEN iv_rest CP 'TEAM FILES/*' THEN substring_after( val = iv_rest sub = '/' )
                    ELSE |COMPANY/{ iv_rest }| ).
    IF iv_strip_type = abap_true AND rv_id CS '.'.
      rv_id = substring_before( val = rv_id sub = '.' occ = -1 ).
    ENDIF.
    REPLACE ALL OCCURRENCES OF '/' IN rv_id WITH '\'.
  ENDMETHOD.

  METHOD unescape_name.
    DATA(lv_file) = substring_after( val = iv_path sub = '/' occ = -1 ).
    IF lv_file IS INITIAL.
      lv_file = iv_path.
    ENDIF.
    IF lv_file CP '*.xml'.
      lv_file = substring_before( val = lv_file sub = '.' occ = -1 ).
    ENDIF.
    rv_name = cl_http_utility=>unescape_url( lv_file ).
  ENDMETHOD.

  METHOD record.
    CLEAR: ev_count, ev_error.
    ev_error = check_request( iv_request ).
    IF ev_error IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_task) = user_task( iv_request ).
    TYPES: BEGIN OF ty_entry,
             object   TYPE e071-object,
             obj_name TYPE e071-obj_name,
           END OF ty_entry.
    DATA lt_entries TYPE SORTED TABLE OF ty_entry WITH UNIQUE KEY object obj_name.
    DATA lt_new_guids TYPE STANDARD TABLE OF ujt_guid WITH DEFAULT KEY.
    GET TIME STAMP FIELD DATA(lv_timestamp).

    " GUID of each entity: BPC's existing mapping, else a new one as BPC creates it.
    LOOP AT it_entities INTO DATA(ls_entity) WHERE entity_type IS NOT INITIAL.
      DATA(ls_key) = VALUE ujt_s_entity( appset_id = iv_environment application_id = ls_entity-application_id
        entity_type = ls_entity-entity_type entity_id = ls_entity-entity_id ).
      DATA(lv_guid) = cl_ujt_transports_dao=>get_guid_by_entity( is_entity = ls_key i_rstlogo = c_rstlogo ).
      IF lv_guid IS INITIAL.
        READ TABLE lt_new_guids INTO DATA(ls_new) WITH KEY appset_id = ls_key-appset_id
          application_id = ls_key-application_id entity_type = ls_key-entity_type entity_id = ls_key-entity_id.
        IF sy-subrc = 0.
          lv_guid = ls_new-guid.
        ELSE.
          lv_guid = cl_ujt_utility=>generate_guid( is_entity = ls_key i_rstlogo = c_rstlogo ).
          APPEND VALUE #( guid = lv_guid rstlogo = c_rstlogo appset_id = ls_key-appset_id
            application_id = ls_key-application_id entity_type = ls_key-entity_type
            entity_id = ls_key-entity_id timestamp = lv_timestamp ) TO lt_new_guids.
        ENDIF.
      ENDIF.
      " Entity types without their own transport object use the generic ABPC.
      SELECT SINGLE f_generic_tlogo FROM ujt_entity_class
        WHERE entity_type = @ls_entity-entity_type INTO @DATA(lv_generic).
      IF sy-subrc <> 0.
        ev_error = |BPC has no transport object type { ls_entity-entity_type }|.
        RETURN.
      ENDIF.
      INSERT VALUE #( object = COND #( WHEN lv_generic = abap_true THEN c_rstlogo ELSE ls_entity-entity_type )
                      obj_name = lv_guid ) INTO TABLE lt_entries.
    ENDLOOP.
    IF lt_entries IS INITIAL.
      RETURN.
    ENDIF.

    IF lt_new_guids IS NOT INITIAL.
      MODIFY ujt_guid FROM TABLE lt_new_guids.
    ENDIF.
    DATA lt_requests TYPE RANGE OF trkorr.
    SELECT trkorr FROM e070 WHERE strkorr = @iv_request OR trkorr = @iv_request
      INTO TABLE @DATA(lt_request_ids).
    LOOP AT lt_request_ids INTO DATA(lv_request_id).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_request_id ) TO lt_requests.
    ENDLOOP.
    LOOP AT lt_entries INTO DATA(ls_entry).
      ev_count = ev_count + 1.
      " Already in the request or one of its tasks
      SELECT SINGLE trkorr FROM e071
        WHERE trkorr IN @lt_requests AND pgmid = 'R3TR'
          AND object = @ls_entry-object AND obj_name = @ls_entry-obj_name
        INTO @DATA(lv_found).
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      CALL FUNCTION 'TR_APPEND_TO_COMM'
        EXPORTING
          pi_korrnum                     = lv_task
          wi_e071                        = VALUE e071( pgmid = 'R3TR' object = ls_entry-object
                                                       obj_name = ls_entry-obj_name )
        EXCEPTIONS
          no_authorization               = 1
          no_systemname                  = 2
          no_systemtype                  = 3
          tr_check_keysyntax_error       = 4
          tr_check_obj_error             = 5
          tr_enqueue_failed              = 6
          tr_ill_korrnum                 = 7
          tr_key_without_header          = 8
          tr_lockmod_failed              = 9
          tr_lock_enqueue_failed         = 10
          tr_modif_only_in_modif_order   = 11
          tr_not_owner                   = 12
          tr_no_append_of_corr_entry     = 13
          tr_no_append_of_c_member       = 14
          tr_no_shared_repairs           = 15
          tr_order_not_exist             = 16
          tr_order_released              = 17
          tr_order_update_error          = 18
          tr_repair_only_in_repair_order = 19
          tr_wrong_order_type            = 20
          wrong_client                   = 21
          OTHERS                         = 22.
      IF sy-subrc <> 0.
        DATA(lv_subrc) = sy-subrc.
        DATA lv_text TYPE string.
        IF sy-msgid IS NOT INITIAL.
          MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_text.
        ENDIF.
        ROLLBACK WORK.
        CLEAR ev_count.
        ev_error = |Cannot add { ls_entry-object } { ls_entry-obj_name } to { iv_request }| &&
          COND string( WHEN lv_text IS NOT INITIAL THEN |: { lv_text }| ELSE | (error { lv_subrc })| ).
        RETURN.
      ENDIF.
    ENDLOOP.
    COMMIT WORK AND WAIT.
  ENDMETHOD.
ENDCLASS.
