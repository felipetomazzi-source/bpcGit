CLASS ltcl_form_fields DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS root_folder_presence FOR TESTING.
ENDCLASS.

CLASS ltcl_form_fields IMPLEMENTATION.
  METHOD root_folder_presence.
    DATA fields TYPE tihttpnvp.
    fields = VALUE #( ( name = 'ROOTFOLDER' value = 'bpc' ) ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_http=>has_form_field(
      it_fields = fields iv_name = 'rootFolder' ) exp = abap_true ).
    fields = VALUE #( ( name = 'rootFolder' value = 'content/bpc' ) ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_http=>has_form_field(
      it_fields = fields iv_name = 'rootFolder' ) exp = abap_true ).
    fields = VALUE #( ( name = 'RootFolder' value = '' ) ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_http=>has_form_field(
      it_fields = fields iv_name = 'rootFolder' ) exp = abap_true ).
    fields = VALUE #( ( name = 'branch' value = 'main' ) ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bpc_git_http=>has_form_field(
      it_fields = fields iv_name = 'rootFolder' ) exp = abap_false ).
  ENDMETHOD.
ENDCLASS.
