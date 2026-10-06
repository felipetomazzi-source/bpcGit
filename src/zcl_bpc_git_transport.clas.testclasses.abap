CLASS ltcl_entities DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS files FOR TESTING.
    METHODS data_manager FOR TESTING.
    METHODS environment_objects FOR TESTING.
    METHODS unsupported FOR TESTING.
    METHODS assert_entity
      IMPORTING is_entity TYPE zcl_bpc_git_transport=>ty_entity
                iv_application TYPE string OPTIONAL iv_type TYPE string iv_id TYPE string.
ENDCLASS.

CLASS ltcl_entities IMPLEMENTATION.
  METHOD assert_entity.
    cl_abap_unit_assert=>assert_equals( act = is_entity-application_id exp = iv_application ).
    cl_abap_unit_assert=>assert_equals( act = is_entity-entity_type exp = iv_type ).
    cl_abap_unit_assert=>assert_equals( act = is_entity-entity_id exp = iv_id ).
  ENDMETHOD.

  METHOD files.
    " Formats observed in UJT_GUID for BPC's own transports
    assert_entity( is_entity = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
        iv_kind = zcl_bpc_git_service=>c_kind-workbook iv_path = `AGGR_OPEX/EEXCEL/REPORTS/X.XLSX` )
      iv_application = `AGGR_OPEX` iv_type = `AFLE` iv_id = `COMPANY\EEXCEL\REPORTS\X.XLSX` ).
    assert_entity( is_entity = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
        iv_kind = zcl_bpc_git_service=>c_kind-workbook
        iv_path = `PROJPLAN/TEAM FILES/Proj. Outturn Super/EEXCEL/BOOKS/M.XLSM` )
      iv_application = `PROJPLAN` iv_type = `AFLE` iv_id = `Proj. Outturn Super\EEXCEL\BOOKS\M.XLSM` ).
    assert_entity( is_entity = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
        iv_kind = zcl_bpc_git_service=>c_kind-script iv_path = `ADMINAPP/AGGR_OPEX/CLEAR_DATA.LGF` )
      iv_application = `AGGR_OPEX` iv_type = `ASPR` iv_id = `ADMINAPP\AGGR_OPEX` ).
  ENDMETHOD.

  METHOD data_manager.
    DATA(ls_definition) = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
      iv_kind = zcl_bpc_git_service=>c_kind-transformation
      iv_path = `AGGR_OPEX/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.TDM` ).
    assert_entity( is_entity = ls_definition iv_application = `AGGR_OPEX` iv_type = `ADMF`
      iv_id = `COMPANY\DATAMANAGER\TRANSFORMATIONFILES\IMPORT` ).
    " The workbook of a definition is the same entity
    DATA(ls_workbook) = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
      iv_kind = zcl_bpc_git_service=>c_kind-transformation
      iv_path = `AGGR_OPEX/DATAMANAGER/TRANSFORMATIONFILES/IMPORT.XLS` ).
    cl_abap_unit_assert=>assert_equals( act = ls_workbook-entity_id exp = ls_definition-entity_id ).
    assert_entity( is_entity = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
        iv_kind = zcl_bpc_git_service=>c_kind-conversion
        iv_path = `AGGR_OPEX/DATAMANAGER/CONVERSIONFILES/CONVERSION.CDM` )
      iv_application = `AGGR_OPEX` iv_type = `ADMF` iv_id = `COMPANY\DATAMANAGER\CONVERSIONFILES\CONVERSION` ).
    assert_entity( is_entity = zcl_bpc_git_transport=>package_entity( iv_path = `P` iv_model = `aggr_opex`
        iv_team = '' iv_group = 'Data Management' iv_package = 'IMPORT' )
      iv_application = `AGGR_OPEX` iv_type = `ADMP` iv_id = `$$Data Management$$IMPORT` ).
    assert_entity( is_entity = zcl_bpc_git_transport=>link_entity( iv_path = `L` iv_model = `AGGR_OPEX`
        iv_name = `LOAD_ACTUALS` )
      iv_application = `AGGR_OPEX` iv_type = `ADML` iv_id = `LOAD_ACTUALS` ).
  ENDMETHOD.

  METHOD environment_objects.
    assert_entity( is_entity = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
        iv_kind = zcl_bpc_git_service=>c_kind-team iv_path = `SECURITY/TEAMS/CNO%20Planners.xml` )
      iv_type = `ATEM` iv_id = `CNO Planners` ).
    assert_entity( is_entity = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
        iv_kind = zcl_bpc_git_service=>c_kind-taskprofile iv_path = `SECURITY/TASKPROFILES/TaskEndUser.xml` )
      iv_type = `ATPF` iv_id = `TaskEndUser` ).
    assert_entity( is_entity = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
        iv_kind = zcl_bpc_git_service=>c_kind-dataprofile
        iv_path = `SECURITY/DATAACCESSPROFILES/DAP_WriteCTO.xml` )
      iv_type = `ADAF` iv_id = `DAP_WriteCTO` ).
    " Members are transported per dimension
    assert_entity( is_entity = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
        iv_kind = zcl_bpc_git_service=>c_kind-dimmember iv_path = `DIMENSIONS/ACCOUNT/MEMBERS/REV100.xml` )
      iv_type = `AMBR` iv_id = `ACCOUNT` ).
  ENDMETHOD.

  METHOD unsupported.
    DATA(ls_entity) = zcl_bpc_git_transport=>entity_for_path( iv_environment = 'ENV'
      iv_kind = `OTHER` iv_path = `X/Y.Z` ).
    cl_abap_unit_assert=>assert_initial( ls_entity-entity_type ).
    cl_abap_unit_assert=>assert_not_initial( ls_entity-note ).
  ENDMETHOD.
ENDCLASS.
