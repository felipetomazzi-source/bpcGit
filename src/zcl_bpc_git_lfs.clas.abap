"! Git LFS basic transfers for Bitbucket Cloud. No credentials are persisted.
CLASS zcl_bpc_git_lfs DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS c_max_bytes TYPE i VALUE 134217728.
    TYPES: BEGIN OF ty_pointer,
             oid TYPE string,
             size TYPE i,
           END OF ty_pointer,
           BEGIN OF ty_header,
             name TYPE string,
             value TYPE string,
           END OF ty_header,
           ty_headers TYPE HASHED TABLE OF ty_header WITH UNIQUE KEY name,
           BEGIN OF ty_action,
             href TYPE string,
             header TYPE ty_headers,
           END OF ty_action,
           BEGIN OF ty_object,
             oid TYPE string,
             size TYPE i,
             BEGIN OF actions,
               upload TYPE ty_action,
               download TYPE ty_action,
               verify TYPE ty_action,
             END OF actions,
             BEGIN OF error,
               code TYPE i,
               message TYPE string,
             END OF error,
           END OF ty_object.
    CLASS-METHODS parse
      IMPORTING iv_data TYPE xstring
      RETURNING VALUE(rs_pointer) TYPE ty_pointer RAISING zcx_abapgit_exception.
    CLASS-METHODS pointer
      IMPORTING iv_data TYPE xstring
      RETURNING VALUE(rv_data) TYPE xstring RAISING zcx_abapgit_exception.
    CLASS-METHODS sha256
      IMPORTING iv_data TYPE xstring
      RETURNING VALUE(rv_hash) TYPE string RAISING zcx_abapgit_exception.
    CLASS-METHODS eligible
      IMPORTING iv_path TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    CLASS-METHODS attributes
      IMPORTING iv_attributes TYPE string iv_path TYPE string
      RETURNING VALUE(rv_text) TYPE string RAISING zcx_abapgit_exception.
    METHODS constructor
      IMPORTING iv_url TYPE string iv_user TYPE string iv_token TYPE string
      RAISING zcx_abapgit_exception.
    METHODS upload
      IMPORTING iv_data TYPE xstring
      RETURNING VALUE(rv_pointer) TYPE xstring RAISING zcx_abapgit_exception.
    METHODS download
      IMPORTING is_pointer TYPE ty_pointer
      RETURNING VALUE(rv_data) TYPE xstring RAISING zcx_abapgit_exception.
  PRIVATE SECTION.
    DATA mv_endpoint TYPE string.
    DATA mv_user TYPE string.
    DATA mv_token TYPE string.
    METHODS batch
      IMPORTING iv_operation TYPE string is_pointer TYPE ty_pointer
      RETURNING VALUE(rs_object) TYPE ty_object RAISING zcx_abapgit_exception.
    METHODS request
      IMPORTING is_action TYPE ty_action iv_method TYPE string
        iv_data TYPE xstring OPTIONAL iv_batch TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rv_data) TYPE xstring RAISING zcx_abapgit_exception.
ENDCLASS.

CLASS zcl_bpc_git_lfs IMPLEMENTATION.
  METHOD sha256.
    TRY.
        cl_abap_message_digest=>calculate_hash_for_raw(
          EXPORTING if_algorithm = 'SHA256' if_data = iv_data
          IMPORTING ef_hashstring = rv_hash ).
        rv_hash = to_lower( rv_hash ).
      CATCH cx_root.
        zcx_abapgit_exception=>raise( 'Cannot calculate Git LFS SHA-256 on this SAP system' ).
    ENDTRY.
  ENDMETHOD.

  METHOD pointer.
    IF xstrlen( iv_data ) > c_max_bytes.
      zcx_abapgit_exception=>raise( 'Git LFS workbook exceeds the 128 MB transfer limit' ).
    ENDIF.
    rv_data = cl_abap_codepage=>convert_to(
      |version https://git-lfs.github.com/spec/v1{ cl_abap_char_utilities=>newline }| &&
      |oid sha256:{ sha256( iv_data ) }{ cl_abap_char_utilities=>newline }| &&
      |size { xstrlen( iv_data ) NUMBER = RAW }{ cl_abap_char_utilities=>newline }| ).
  ENDMETHOD.

  METHOD parse.
    " Inspect the ASCII marker without trying to decode Excel bytes as text.
    DATA(lv_marker) = cl_abap_codepage=>convert_to( 'version https://git-lfs.github.com/spec/v1' ).
    DATA(lv_length) = xstrlen( lv_marker ).
    IF xstrlen( iv_data ) < lv_length OR iv_data(lv_length) <> lv_marker.
      RETURN.
    ENDIF.
    IF xstrlen( iv_data ) >= 1024.
      zcx_abapgit_exception=>raise( 'Invalid or unsupported Git LFS pointer' ).
    ENDIF.
    TRY.
        DATA(lv_text) = cl_abap_codepage=>convert_from( iv_data ).
        DATA lt_lines TYPE string_table.
        SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
        IF lines( lt_lines ) <> 4 OR lt_lines[ 1 ] <> 'version https://git-lfs.github.com/spec/v1'
            OR lt_lines[ 4 ] IS NOT INITIAL.
          zcx_abapgit_exception=>raise( 'Invalid or extended Git LFS pointer; only canonical SHA-256 pointers are supported' ).
        ENDIF.
        FIND REGEX '^oid sha256:([0-9a-f]{64})$' IN lt_lines[ 2 ] SUBMATCHES rs_pointer-oid.
        IF sy-subrc <> 0.
          zcx_abapgit_exception=>raise( 'Invalid Git LFS object hash' ).
        ENDIF.
        DATA lv_size TYPE string.
        FIND REGEX '^size (0|[1-9][0-9]*)$' IN lt_lines[ 3 ] SUBMATCHES lv_size.
        IF sy-subrc <> 0.
          zcx_abapgit_exception=>raise( 'Invalid Git LFS object size' ).
        ENDIF.
        rs_pointer-size = lv_size.
        IF rs_pointer-size > c_max_bytes.
          zcx_abapgit_exception=>raise( 'Git LFS workbook exceeds the 128 MB transfer limit' ).
        ENDIF.
      CATCH zcx_abapgit_exception INTO DATA(lx_pointer).
        RAISE EXCEPTION lx_pointer.
      CATCH cx_root.
        zcx_abapgit_exception=>raise( 'Invalid Git LFS pointer' ).
    ENDTRY.
  ENDMETHOD.

  METHOD eligible.
    DATA(lv_path) = to_upper( iv_path ).
    rv_yes = xsdbool( lv_path CS '/EEXCEL/' AND
      ( lv_path CP '*.XLS' OR lv_path CP '*.XLSX' OR lv_path CP '*.XLSM'
        OR lv_path CP '*.XLTX' OR lv_path CP '*.XLTM' ) ).
  ENDMETHOD.

  METHOD constructor.
    DATA lv_workspace TYPE string.
    DATA lv_repository TYPE string.
    FIND REGEX '^https://bitbucket[.]org/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/?$'
      IN iv_url SUBMATCHES lv_workspace lv_repository.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( 'Git LFS currently supports Bitbucket Cloud repositories only' ).
    ENDIF.
    REPLACE REGEX '[.]git$' IN lv_repository WITH ''.
    mv_endpoint = |https://bitbucket.org/{ lv_workspace }/{ lv_repository }.git/info/lfs/objects/batch|.
    mv_user = iv_user.
    mv_token = iv_token.
  ENDMETHOD.

  METHOD attributes.
    IF iv_path CA cl_abap_char_utilities=>cr_lf.
      zcx_abapgit_exception=>raise( 'Unsupported newline in Git LFS workbook path' ).
    ENDIF.
    DATA(lv_quoted) = iv_path.
    " Escape glob characters first, then C-quote the complete Git pattern.
    REPLACE ALL OCCURRENCES OF '\' IN lv_quoted WITH '\\'.
    REPLACE ALL OCCURRENCES OF '*' IN lv_quoted WITH '\*'.
    REPLACE ALL OCCURRENCES OF '?' IN lv_quoted WITH '\?'.
    REPLACE ALL OCCURRENCES OF '[' IN lv_quoted WITH '\['.
    REPLACE ALL OCCURRENCES OF ']' IN lv_quoted WITH '\]'.
    REPLACE ALL OCCURRENCES OF '\' IN lv_quoted WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN lv_quoted WITH '\"'.
    DATA(lv_rule) = |"/{ lv_quoted }" filter=lfs diff=lfs merge=lfs -text|.
    DATA lt_lines TYPE string_table.
    SPLIT iv_attributes AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    " Remove only our identical rule, then put it last so root rules cannot
    " override it. Preserve all other attributes and their relative order.
    DELETE lt_lines WHERE table_line = lv_rule.
    rv_text = concat_lines_of( table = lt_lines sep = cl_abap_char_utilities=>newline ) &&
      cl_abap_char_utilities=>newline && lv_rule && cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD request.
    " The authenticated batch server supplies action URLs/headers. Never send
    " the repository password to storage URLs or follow redirects with it.
    FIND REGEX '^https://[A-Za-z0-9.-]+(/|$)' IN is_action-href.
    IF sy-subrc <> 0 OR is_action-href CS '#' OR is_action-href CA cl_abap_char_utilities=>cr_lf.
      zcx_abapgit_exception=>raise( 'Git LFS returned an unsupported transfer URL' ).
    ENDIF.
    TEST-SEAM lfs_http.
    DATA lo_client TYPE REF TO if_http_client.
    cl_http_client=>create_by_url( EXPORTING url = is_action-href
      IMPORTING client = lo_client EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( 'Cannot create Git LFS HTTPS connection' ).
    ENDIF.
    lo_client->propertytype_logon_popup = if_http_client=>co_disabled.
    lo_client->propertytype_redirect = if_http_client=>co_disabled.
    lo_client->request->set_method( iv_method ).
    lo_client->request->set_header_field( name = 'Accept' value = 'application/vnd.git-lfs+json' ).
    IF iv_batch = abap_true OR iv_method = 'POST'.
      lo_client->request->set_content_type( 'application/vnd.git-lfs+json' ).
    ELSEIF iv_method = 'PUT'.
      lo_client->request->set_content_type( 'application/octet-stream' ).
    ENDIF.
    IF iv_batch = abap_true AND mv_user IS NOT INITIAL AND mv_token IS NOT INITIAL.
      lo_client->authenticate( username = mv_user password = mv_token ).
    ENDIF.
    LOOP AT is_action-header INTO DATA(ls_header).
      IF ls_header-name CA cl_abap_char_utilities=>cr_lf OR ls_header-value CA cl_abap_char_utilities=>cr_lf
          OR to_lower( ls_header-name ) = 'host' OR to_lower( ls_header-name ) = 'content-length'.
        lo_client->close( ).
        zcx_abapgit_exception=>raise( 'Git LFS returned an unsupported transfer header' ).
      ENDIF.
      lo_client->request->set_header_field( name = ls_header-name value = ls_header-value ).
    ENDLOOP.
    IF iv_method = 'POST' OR iv_method = 'PUT'.
      lo_client->request->set_data( iv_data ).
    ENDIF.
    lo_client->send( EXPORTING timeout = 60 EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc = 0.
      lo_client->receive( EXCEPTIONS OTHERS = 1 ).
    ENDIF.
    IF sy-subrc <> 0.
      lo_client->close( ).
      zcx_abapgit_exception=>raise( 'Git LFS HTTPS transfer failed; check SAP HTTPS trust and connectivity' ).
    ENDIF.
    DATA lv_status TYPE i.
    lo_client->response->get_status( IMPORTING code = lv_status ).
    rv_data = lo_client->response->get_data( ).
    lo_client->close( ).
    IF lv_status = 401.
      zcx_abapgit_exception=>raise( 'Unauthorized Git LFS access; log in with a token that permits LFS' ).
    ELSEIF lv_status < 200 OR lv_status >= 300.
      zcx_abapgit_exception=>raise( |Git LFS { iv_method } returned HTTP { lv_status }; check LFS permissions, quota and HTTPS connectivity| ).
    ENDIF.
    IF ( iv_method = 'GET' AND xstrlen( rv_data ) > c_max_bytes )
        OR ( iv_method <> 'GET' AND xstrlen( rv_data ) > 1048576 ).
      zcx_abapgit_exception=>raise( 'Git LFS response exceeds the transfer limit' ).
    ENDIF.
    END-TEST-SEAM.
  ENDMETHOD.

  METHOD batch.
    DATA(lv_json) = |\{"operation":"{ iv_operation }","transfers":["basic"],"objects":[| &&
      |\{"oid":"{ is_pointer-oid }","size":{ is_pointer-size NUMBER = RAW }\}]\}|.
    DATA(lv_reply) = request( is_action = VALUE #( href = mv_endpoint ) iv_method = 'POST'
      iv_batch = abap_true iv_data = cl_abap_codepage=>convert_to( lv_json ) ).
    TYPES: BEGIN OF ty_reply,
             transfer TYPE string,
             hash_algo TYPE string,
             objects TYPE STANDARD TABLE OF ty_object WITH DEFAULT KEY,
           END OF ty_reply.
    DATA ls_reply TYPE ty_reply.
    /ui2/cl_json=>deserialize( EXPORTING json = cl_abap_codepage=>convert_from( lv_reply )
      assoc_arrays = abap_true assoc_arrays_opt = abap_true CHANGING data = ls_reply ).
    IF lines( ls_reply-objects ) <> 1 OR ( ls_reply-transfer IS NOT INITIAL AND ls_reply-transfer <> 'basic' )
        OR ( ls_reply-hash_algo IS NOT INITIAL AND ls_reply-hash_algo <> 'sha256' ).
      zcx_abapgit_exception=>raise( 'Invalid or unsupported Git LFS batch response' ).
    ENDIF.
    rs_object = ls_reply-objects[ 1 ].
    IF rs_object-oid <> is_pointer-oid OR rs_object-size <> is_pointer-size OR rs_object-error-code <> 0.
      zcx_abapgit_exception=>raise( |Git LFS object unavailable (code { rs_object-error-code }); check permissions and storage quota| ).
    ENDIF.
  ENDMETHOD.

  METHOD upload.
    rv_pointer = pointer( iv_data ).
    DATA(ls_pointer) = parse( rv_pointer ).
    DATA(ls_object) = batch( iv_operation = 'upload' is_pointer = ls_pointer ).
    IF ls_object-actions-upload-href IS NOT INITIAL.
      request( is_action = ls_object-actions-upload iv_method = 'PUT' iv_data = iv_data ).
      IF ls_object-actions-verify-href IS NOT INITIAL.
        DATA(lv_json) = |\{"oid":"{ ls_pointer-oid }","size":{ ls_pointer-size NUMBER = RAW }\}|.
        request( is_action = ls_object-actions-verify iv_method = 'POST'
          iv_data = cl_abap_codepage=>convert_to( lv_json ) ).
      ENDIF.
    ENDIF.
    " No upload action means the server already holds this immutable object.
  ENDMETHOD.

  METHOD download.
    DATA(ls_object) = batch( iv_operation = 'download' is_pointer = is_pointer ).
    IF ls_object-actions-download-href IS INITIAL.
      zcx_abapgit_exception=>raise( 'Git LFS response has no download action' ).
    ENDIF.
    rv_data = request( is_action = ls_object-actions-download iv_method = 'GET' ).
    IF xstrlen( rv_data ) <> is_pointer-size OR sha256( rv_data ) <> is_pointer-oid.
      zcx_abapgit_exception=>raise( 'Git LFS content failed size or SHA-256 verification; restore was refused' ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
