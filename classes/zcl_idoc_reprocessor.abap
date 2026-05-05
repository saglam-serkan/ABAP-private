CLASS zcl_idoc_reprocessor DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE .

  PUBLIC SECTION.

    TYPES docnum_range TYPE RANGE OF edidc-docnum .
    TYPES mestyp_range TYPE RANGE OF edidc-mestyp .
    TYPES status_range TYPE RANGE OF edidc-status .
    TYPES credat_range TYPE RANGE OF edidc-credat .
    TYPES upddat_range TYPE RANGE OF edidc-upddat .

    TYPES: BEGIN OF selection_criteria,
             docnum_range TYPE docnum_range,
             mestyp_range TYPE mestyp_range,
             status_range TYPE status_range,
             credat_range TYPE credat_range,
             upddat_range TYPE upddat_range,
           END OF selection_criteria .

    TYPES: BEGIN OF reprocessor,
             program      TYPE program,
             direction    TYPE edidc-direct,
             status_range TYPE status_range,
           END OF reprocessor .

    TYPES reprocessors TYPE TABLE OF reprocessor WITH EMPTY KEY .

    TYPES: BEGIN OF idoc_status,
             status TYPE teds2-status,
             descrp TYPE teds2-descrp,
           END OF idoc_status .

    DATA reprocessors_cache TYPE reprocessors .
    DATA idoc_statuses TYPE SORTED TABLE OF idoc_status WITH UNIQUE KEY status .

    CONSTANTS: BEGIN OF direction,
                 outbound TYPE edidc-direct VALUE '1',
                 inbound  TYPE edidc-direct VALUE '2',
               END OF direction .

    CLASS-METHODS get_instance
      RETURNING VALUE(instance) TYPE REF TO zcl_idoc_reprocessor .

    METHODS reprocess
      IMPORTING !selection_criteria TYPE selection_criteria
                !interprocess_wait  TYPE byte DEFAULT 1
                !display_idocs      TYPE abap_bool .

    METHODS simulate
      IMPORTING !selection_criteria TYPE selection_criteria .

    METHODS validate_selection
      IMPORTING !selection_criteria TYPE selection_criteria
      RETURNING VALUE(is_valid)     TYPE abap_bool .

    METHODS confirm_large_selection
      IMPORTING !count              TYPE i
                !threshold          TYPE i
      RETURNING VALUE(is_confirmed) TYPE abap_bool .

    METHODS confirm_reprocessing
      IMPORTING !count              TYPE i
      RETURNING VALUE(is_confirmed) TYPE abap_bool .

    METHODS select_idoc_count
      IMPORTING !selection_criteria TYPE selection_criteria
      RETURNING VALUE(idocs_count)  TYPE i .

  PRIVATE SECTION.

    CLASS-DATA instance TYPE REF TO zcl_idoc_reprocessor .
    DATA idoc_list TYPE zif_idoc_reprocessor=>idoc_list .

    METHODS display_idoc_list
      IMPORTING !title     TYPE lvc_title OPTIONAL
      CHANGING  !idoc_list TYPE ANY TABLE .

    METHODS execute_reprocessing
      IMPORTING !program      TYPE program
                !direction    TYPE edidc-direct OPTIONAL
                !docnum_range TYPE docnum_range .

    METHODS get_reprocessors
      RETURNING VALUE(reprocessors) TYPE reprocessors .

    METHODS get_status_filter
      IMPORTING !status_range        TYPE status_range
      RETURNING VALUE(status_filter) TYPE status_range .

    METHODS get_reprocessable_statuses
      RETURNING VALUE(valid_statuses) TYPE status_range .

    METHODS get_status_text
      IMPORTING !status       TYPE teds2-status
      RETURNING VALUE(descrp) TYPE teds2-descrp .

    METHODS select_idocs
      IMPORTING !selection_criteria TYPE selection_criteria
      RETURNING VALUE(idocs)        TYPE zif_idoc_reprocessor=>idoc_list .

    METHODS set_idoc_reprocessors
      CHANGING !idoc_list TYPE zif_idoc_reprocessor=>idoc_list .

    METHODS set_idoc_statuses
      CHANGING !idoc_list TYPE zif_idoc_reprocessor=>idoc_list .

    METHODS on_link_click
        FOR EVENT link_click OF cl_salv_events_table
      IMPORTING
        !row
        !column .

ENDCLASS.



CLASS zcl_idoc_reprocessor IMPLEMENTATION.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_IDOC_REPROCESSOR->CONFIRM_LARGE_SELECTION
* +-------------------------------------------------------------------------------------------------+
* | [--->] COUNT                          TYPE        I
* | [--->] THRESHOLD                      TYPE        I
* | [<-()] IS_CONFIRMED                   TYPE        ABAP_BOOL
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD confirm_large_selection.

    " Default to true if running in background
    is_confirmed = abap_true.

    " Only for foreground
    CHECK sy-batch = abap_false.

    CHECK count > threshold.

    DATA answer TYPE c.
    DATA(question) = |Current selection of { count } IDocs exceeds the defined safety threshold. |
                  && |Processing this volume may impact system performance and memory. |
                  && |Proceed with the requested operation?|.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Data Volume Warning'
        text_question         = question
        default_button        = '2'    "Default to 'No'
        display_cancel_button = abap_false
      IMPORTING
        answer                = answer
      EXCEPTIONS
        text_not_found        = 1
        OTHERS                = 2.

    is_confirmed = xsdbool( answer = '1' ).

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_IDOC_REPROCESSOR->CONFIRM_REPROCESSING
* +-------------------------------------------------------------------------------------------------+
* | [--->] COUNT                          TYPE        I
* | [<-()] IS_CONFIRMED                   TYPE        ABAP_BOOL
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD confirm_reprocessing.

    " Default to true if running in background
    is_confirmed = abap_true.

    " Only for foreground
    CHECK sy-batch = abap_false.

    DATA(question) = |{ count } IDoc{ COND #( WHEN count > 1 THEN 's' ) } selected for reprocessing. |
                  && |This will trigger reprocessor program{ COND #( WHEN count > 1 THEN 's' ) } |
                  && |in the background and attempt to update status{ COND #( WHEN count > 1 THEN 'es' ) } |
                  && |for the selected IDoc{ COND #( WHEN count > 1 THEN 's' ) }. |
                  && |Do you want to proceed?|.

    DATA answer TYPE c.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Confirm Mass Reprocessing'
        text_question         = question
        default_button        = '2'    "Default to 'No'
        display_cancel_button = abap_false
      IMPORTING
        answer                = answer
      EXCEPTIONS
        text_not_found        = 1
        OTHERS                = 2.

    is_confirmed = xsdbool( answer = '1' ).

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->DISPLAY_IDOC_LIST
* +-------------------------------------------------------------------------------------------------+
* | [--->] TITLE                          TYPE        LVC_TITLE(optional)
* | [<-->] IDOC_LIST                      TYPE        ANY TABLE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD display_idoc_list.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(salv_table)
          CHANGING  t_table      = idoc_list ).

        salv_table->get_columns( )->set_optimize( abap_true ).
        salv_table->get_display_settings( )->set_striped_pattern( abap_true ).
        salv_table->get_display_settings( )->set_list_header( title ).
        salv_table->get_functions( )->set_all( abap_true ).
        salv_table->get_layout( )->set_save_restriction( if_salv_c_layout=>restrict_none ).
        salv_table->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).

        TRY.
            salv_table->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).
            salv_table->get_sorts( )->add_sort( 'DOCNUM' ).
          CATCH cx_root.
        ENDTRY.

        LOOP AT salv_table->get_columns( )->get( ) ASSIGNING FIELD-SYMBOL(<column>).
          CASE <column>-r_column->get_columnname( ).
            WHEN 'MANDT' OR 'CLIENT'.
              <column>-r_column->set_technical( abap_true ).
            WHEN 'STATUS_CHANGED'.
              <column>-r_column->set_short_text( |Status Changed?| ).
              <column>-r_column->set_medium_text( |Status Changed?| ).
              <column>-r_column->set_long_text( |Status Changed?| ).
              <column>-r_column->set_tooltip( |Status Changed?| ).
            WHEN 'NEW_STATUS'.
              <column>-r_column->set_short_text( |New Status| ).
              <column>-r_column->set_medium_text( |New Status| ).
              <column>-r_column->set_long_text( |New Status| ).
              <column>-r_column->set_tooltip( |New Status| ).
            WHEN 'NEW_STATUS_TEXT'.
              <column>-r_column->set_short_text( |New Status Descr.| ).
              <column>-r_column->set_medium_text( |New Status Description| ).
              <column>-r_column->set_long_text( |New Status Description| ).
              <column>-r_column->set_tooltip( |New Status Description| ).
            WHEN 'NEW_UPDDAT'.
              <column>-r_column->set_short_text( |Update Date| ).
              <column>-r_column->set_medium_text( |Update Date| ).
              <column>-r_column->set_long_text( |Update Date| ).
              <column>-r_column->set_tooltip( |Update Date| ).
            WHEN 'REPROCESSOR'.
              <column>-r_column->set_short_text( |Reprocesor| ).
              <column>-r_column->set_medium_text( |Reprocesor Prog.| ).
              <column>-r_column->set_long_text( |Reprocesor Program| ).
              <column>-r_column->set_tooltip( |Reprocesor Program| ).
            WHEN 'ERROR_OCCURRED'.
              <column>-r_column->set_short_text( |Error?| ).
              <column>-r_column->set_medium_text( |Error?| ).
              <column>-r_column->set_long_text( |Error?| ).
              <column>-r_column->set_tooltip( |Error?| ).
            WHEN 'MESSAGE'.
              <column>-r_column->set_short_text( |Message| ).
              <column>-r_column->set_medium_text( |Message| ).
              <column>-r_column->set_long_text( |Message| ).
              <column>-r_column->set_tooltip( |Message| ).
          ENDCASE.
        ENDLOOP.

        " Color
        TRY.
            CAST cl_salv_column_table( salv_table->get_columns( )->get_column( 'DOCNUM' )
                )->set_color( VALUE lvc_s_colo( col = cl_gui_resources=>list_col_key
                                                int = cl_gui_resources=>list_intensified ) ).
            CAST cl_salv_column_table( salv_table->get_columns( )->get_column( 'OLD_STATUS' )
                )->set_color( VALUE lvc_s_colo( col = cl_gui_resources=>list_col_key
                                                int = cl_gui_resources=>list_intensified ) ).
            CAST cl_salv_column_table( salv_table->get_columns( )->get_column( 'NEW_STATUS' )
                )->set_color( VALUE lvc_s_colo( col = cl_gui_resources=>list_col_group
                                                int = cl_gui_resources=>list_intensified ) ).
          CATCH cx_root.
        ENDTRY.

        " Hotspots
        CAST cl_salv_column_table( salv_table->get_columns( )->get_column( 'DOCNUM' )
            )->set_cell_type( if_salv_c_cell_type=>hotspot ).

        " Register event handlers
        SET HANDLER on_link_click FOR salv_table->get_event( ).

        salv_table->display( ).

      CATCH cx_root INTO DATA(exception).
        MESSAGE exception->get_text( ) TYPE 'I'.
    ENDTRY.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->EXECUTE_REPROCESSING
* +-------------------------------------------------------------------------------------------------+
* | [--->] PROGRAM                        TYPE        PROGRAM
* | [--->] DIRECTION                      TYPE        EDIDC-DIRECT(optional)
* | [--->] DOCNUM_RANGE                   TYPE        DOCNUM_RANGE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD execute_reprocessing.

    CHECK docnum_range IS NOT INITIAL.

    CASE program.

      WHEN 'RBDAGAI2'.
        "Reprocess IDocs After Inbound ALE Error
        SUBMIT rbdagai2 AND RETURN
          WITH so_docnu IN docnum_range
          WITH p_output = abap_false.

      WHEN 'RBDAGAIN'.
        "Process Outbound IDocs with Errors Again
        SUBMIT rbdagain AND RETURN
          WITH so_docnu IN docnum_range
          WITH p_output = abap_false.

      WHEN 'RBDAGAIE'. " Inbound/Outbound
        "Reprocessing of Edited IDocs
        SUBMIT rbdagaie AND RETURN
          WITH p_idoc IN docnum_range
          WITH p_output = abap_false
          WITH p_direct = direction.

      WHEN 'RBDAPP01'.
        "Inbound Processing of IDocs Ready for Passing
        SUBMIT rbdapp01 AND RETURN
          WITH docnum IN docnum_range
          WITH p_output = abap_false.

      WHEN 'RBDMANI2'.
        "Manual Processing of IDocs: Post IDocs Not Yet Posted
        SUBMIT rbdmani2 AND RETURN
          WITH so_docnu IN docnum_range
          WITH p_output = abap_false.

      WHEN 'RBDSYNEI'.
        "Continue Inbound IDoc Processing Despite Syntax Errors
        SUBMIT rbdsynei AND RETURN
          WITH so_docnu IN docnum_range
          WITH p_output = abap_false.

      WHEN 'RBDSYNEO'.
        "Continue Outbound IDoc Processing Despite Syntax Errors
        SUBMIT rbdsyneo AND RETURN
          WITH so_docnu IN docnum_range
          WITH p_output = abap_false.

      WHEN 'RSEOUT00'.
        "Process All Selected IDocs (processes the IDocs with the status 'to be processed')
        SUBMIT rseout00 AND RETURN
          WITH docnum IN docnum_range
          WITH p_show_w = 'B'.

    ENDCASE.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Static Public Method ZCL_IDOC_REPROCESSOR=>GET_INSTANCE
* +-------------------------------------------------------------------------------------------------+
* | [<-()] INSTANCE                       TYPE REF TO ZCL_IDOC_REPROCESSOR
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_instance.

    IF zcl_idoc_reprocessor=>instance IS NOT BOUND.
      zcl_idoc_reprocessor=>instance = NEW #( ).
    ENDIF.

    instance = zcl_idoc_reprocessor=>instance.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->GET_REPROCESSABLE_STATUSES
* +-------------------------------------------------------------------------------------------------+
* | [<-()] VALID_STATUSES                 TYPE        STATUS_RANGE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_reprocessable_statuses.

    valid_statuses = VALUE #( sign = 'I' option = 'EQ'
                              ( low = zif_idoc_status=>_56_idoc_with_errors_added )
                              ( low = zif_idoc_status=>_61_proc_despite_syntax_err )
                              ( low = zif_idoc_status=>_63_err_passing_idoc_to_appl )
                              ( low = zif_idoc_status=>_65_err_in_ale_service )
                              ( low = zif_idoc_status=>_02_err_passing_data_to_port )
                              ( low = zif_idoc_status=>_04_err_ctrl_info_edi_subsys )
                              ( low = zif_idoc_status=>_05_err_during_translation )
                              ( low = zif_idoc_status=>_25_proc_despite_syntax_err )
                              ( low = zif_idoc_status=>_29_err_in_ale_service )
                              ( low = zif_idoc_status=>_37_err_when_adding_idoc )
                              ( low = zif_idoc_status=>_69_idoc_was_edited )
                              ( low = zif_idoc_status=>_32_idoc_was_edited )
                              ( low = zif_idoc_status=>_64_idoc_ready_to_pass_appl )
                              ( low = zif_idoc_status=>_66_idoc_waiting_predecessor )
                              ( low = zif_idoc_status=>_51_appl_doc_not_posted )
                              ( low = zif_idoc_status=>_60_err_during_syntax_check )
                              ( low = zif_idoc_status=>_26_err_during_syntax_check )
                              ( low = zif_idoc_status=>_30_idoc_ready_for_dispatch )
                            ).

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->GET_REPROCESSORS
* +-------------------------------------------------------------------------------------------------+
* | [<-()] REPROCESSORS                   TYPE        REPROCESSORS
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_reprocessors.

    " Reprocessors by statuses:
    " - RBDAGAI2: ALE/EDI Errors (56, 61, 63, 65)
    " - RBDAGAIN: Port/Translation/Control Errors (02, 04, 05, 25, 29, 37)
    " - RBDAGAIE: Edited IDocs (69 Inbound / 32 Outbound)
    " - RBDAPP01: Ready/Postponed (64, 66)
    " - RBDMANI2: Application Errors (51)
    " - RBDSYNEI: Syntax Errors (60 Inbound)
    " - RBDSYNEO: Syntax Errors (26 Outbound)
    " - RSEOUT00: Dispatching (30)

    IF reprocessors_cache IS INITIAL.
      reprocessors_cache = VALUE #(
        ( program = 'RBDAGAI2'
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_56_idoc_with_errors_added )
                                                           ( low = zif_idoc_status=>_61_proc_despite_syntax_err )
                                                           ( low = zif_idoc_status=>_63_err_passing_idoc_to_appl )
                                                           ( low = zif_idoc_status=>_65_err_in_ale_service ) ) )
        ( program = 'RBDAGAIN'
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_02_err_passing_data_to_port )
                                                           ( low = zif_idoc_status=>_04_err_ctrl_info_edi_subsys )
                                                           ( low = zif_idoc_status=>_05_err_during_translation )
                                                           ( low = zif_idoc_status=>_25_proc_despite_syntax_err )
                                                           ( low = zif_idoc_status=>_29_err_in_ale_service )
                                                           ( low = zif_idoc_status=>_37_err_when_adding_idoc ) ) )
        ( program = 'RBDAGAIE'
          direction = direction-inbound
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_69_idoc_was_edited ) ) )

        ( program = 'RBDAGAIE'
          direction = direction-outbound
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_32_idoc_was_edited ) ) )

        ( program = 'RBDAPP01'
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_64_idoc_ready_to_pass_appl )
                                                           ( low = zif_idoc_status=>_66_idoc_waiting_predecessor ) ) )
        ( program = 'RBDMANI2'
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_51_appl_doc_not_posted ) ) )

        ( program = 'RBDSYNEI'
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_60_err_during_syntax_check ) ) )

        ( program = 'RBDSYNEO'
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_26_err_during_syntax_check ) ) )

        ( program = 'RSEOUT00'
          status_range = VALUE #( sign = 'I' option = 'EQ' ( low = zif_idoc_status=>_30_idoc_ready_for_dispatch ) ) )
      ).
    ENDIF.

    reprocessors = reprocessors_cache.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->GET_STATUS_FILTER
* +-------------------------------------------------------------------------------------------------+
* | [--->] STATUS_RANGE                   TYPE        STATUS_RANGE
* | [<-()] STATUS_FILTER                  TYPE        STATUS_RANGE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_status_filter.

    DATA(reprocessable_statuses) = get_reprocessable_statuses( ).

    IF status_range IS INITIAL.
      status_filter = reprocessable_statuses.
    ELSE.
      SELECT status FROM teds1
        INTO TABLE @DATA(provided_statuses)
       WHERE status IN @status_range.

      status_filter = VALUE #( FOR provided_status IN provided_statuses
                               WHERE ( status IN reprocessable_statuses )
                               ( sign = 'I' option = 'EQ' low = provided_status-status ) ).

      " If no valid statuses remain after filtering, fallback to all reprocessable statuses.
      IF status_filter IS INITIAL.
        status_filter = reprocessable_statuses.
      ENDIF.
    ENDIF.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->GET_STATUS_TEXT
* +-------------------------------------------------------------------------------------------------+
* | [--->] STATUS                         TYPE        TEDS2-STATUS
* | [<-()] DESCRP                         TYPE        TEDS2-DESCRP
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_status_text.

    IF idoc_statuses IS INITIAL.
      SELECT status descrp FROM teds2 INTO TABLE idoc_statuses WHERE langua EQ sy-langu.
    ENDIF.

    READ TABLE idoc_statuses ASSIGNING FIELD-SYMBOL(<status>) WITH KEY status = status.
    IF <status> IS ASSIGNED.
      descrp = <status>-descrp.
    ENDIF.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->ON_LINK_CLICK
* +-------------------------------------------------------------------------------------------------+
* | [--->] ROW                            LIKE
* | [--->] COLUMN                         LIKE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD on_link_click.

    CASE column.
      WHEN 'DOCNUM'.
        READ TABLE idoc_list ASSIGNING FIELD-SYMBOL(<idoc>) INDEX row.
        IF <idoc> IS ASSIGNED.
          CALL FUNCTION 'EDI_DOCUMENT_TREE_DISPLAY'
            EXPORTING
              docnum        = <idoc>-docnum
            EXCEPTIONS
              no_idoc_found = 1.
        ENDIF.
    ENDCASE.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_IDOC_REPROCESSOR->REPROCESS
* +-------------------------------------------------------------------------------------------------+
* | [--->] SELECTION_CRITERIA             TYPE        SELECTION_CRITERIA
* | [--->] INTERPROCESS_WAIT              TYPE        BYTE (default =1)
* | [--->] DISPLAY_IDOCS                  TYPE        ABAP_BOOL
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD reprocess.

    "--------------------------------------------------------------------*
    " reprocess()
    "   |-- select_idocs()
    "   |-- badi process_idocs
    "   |-- execute_reprocessing
    "--------------------------------------------------------------------*

    CHECK validate_selection( selection_criteria ) = abap_true.

    idoc_list = select_idocs( selection_criteria ).

    DATA custom_processed_idocs TYPE zif_idoc_reprocessor=>custom_processed_idocs.

    TRY .
        DATA zbd_idoc_reprocessor TYPE REF TO zbd_idoc_reprocessor.
        GET BADI zbd_idoc_reprocessor.

        CALL BADI zbd_idoc_reprocessor->process_idocs
          EXPORTING
            idoc_list       = idoc_list
            simulate        = abap_false
          CHANGING
            processed_idocs = custom_processed_idocs.

      CATCH cx_badi_not_implemented.
      CATCH cx_root INTO DATA(exception).
        MESSAGE exception->get_text( ) TYPE 'I'.
    ENDTRY.

    " Apply processing results back to idoc_list
    "
    " IDocs handled by the BAdI are marked as reprocessor = 'CUSTOM LOGIC'
    " to exclude them from standard reprocessing.
    " This applies regardless of outcome (success, fail)
    LOOP AT custom_processed_idocs ASSIGNING FIELD-SYMBOL(<processed_idoc>).
      MODIFY idoc_list FROM VALUE #( docnum           = <processed_idoc>-docnum
                                     new_status       = <processed_idoc>-status
                                     new_status_text  = get_status_text( <processed_idoc>-status )
                                     reprocessor      = 'CUSTOM LOGIC'
                                     message          = <processed_idoc>-message
                                    )
                       TRANSPORTING new_status
                                    new_status_text
                                    reprocessor
                                    message
                       WHERE docnum = <processed_idoc>-docnum.
    ENDLOOP.

    IF idoc_list IS NOT INITIAL.
      DATA num_of_processed TYPE i.

      LOOP AT get_reprocessors( ) ASSIGNING FIELD-SYMBOL(<reprocessor>).
        " Filter main list by current status group
        DATA(filtered_docnum_range) = VALUE docnum_range(
                                        FOR idoc IN idoc_list WHERE ( old_status IN <reprocessor>-status_range AND
                                                                      reprocessor <> 'CUSTOM LOGIC' )
                                        ( sign = 'I' option = 'EQ' low = idoc-docnum ) ).

        IF filtered_docnum_range IS NOT INITIAL.
          num_of_processed = num_of_processed + lines( filtered_docnum_range ).

          cl_progress_indicator=>progress_indicate(
              i_text               = |Executing { <reprocessor>-program } with { lines( filtered_docnum_range ) } IDocs...|
              i_processed          = num_of_processed
              i_total              = lines( idoc_list )
              i_output_immediately = abap_true ).

          execute_reprocessing(
            program      = <reprocessor>-program
            direction    = <reprocessor>-direction
            docnum_range = filtered_docnum_range ).

          IF interprocess_wait > 0.
            " Wait between reprocessors. Do not use the statement WAIT as it does a DB commit.
            CALL FUNCTION 'ENQUE_SLEEP'
              EXPORTING
                seconds = interprocess_wait
              EXCEPTIONS
                OTHERS  = 2.
          ENDIF.
        ENDIF.
      ENDLOOP.

      set_idoc_reprocessors( CHANGING idoc_list = idoc_list ).
      set_idoc_statuses( CHANGING idoc_list = idoc_list ).
    ENDIF.

    IF display_idocs = abap_true.
      display_idoc_list(
        EXPORTING title = |{ sy-title } (Actual Run)|
        CHANGING  idoc_list = idoc_list ).
    ENDIF.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->SELECT_IDOCS
* +-------------------------------------------------------------------------------------------------+
* | [--->] SELECTION_CRITERIA             TYPE        SELECTION_CRITERIA
* | [<-()] IDOCS                          TYPE        ZIF_IDOC_REPROCESSOR=>IDOC_LIST
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD select_idocs.

    DATA(status_filter) = get_status_filter( selection_criteria-status_range ).

    TRY.
        SELECT a~docnum,
               a~direct,
               a~mestyp,
               a~idoctp,
               a~credat,
               a~upddat,
               a~status AS old_status
              "b~descrp AS old_status_text
          FROM edidc AS a
         "LEFT OUTER JOIN teds2 AS b ON b~status = a~status
         "                           AND b~langua = @sy-langu
          INTO CORRESPONDING FIELDS OF TABLE @idocs
         WHERE a~docnum IN @selection_criteria-docnum_range AND
               a~status IN @status_filter AND
               a~mestyp IN @selection_criteria-mestyp_range AND
               a~credat IN @selection_criteria-credat_range AND
               a~upddat IN @selection_criteria-upddat_range.

      CATCH cx_root INTO DATA(exception).
        MESSAGE exception->get_text( ) TYPE 'I'.
    ENDTRY.

    " Set status descriptions
    IF idoc_statuses IS INITIAL.
      SELECT status descrp FROM teds2 INTO TABLE idoc_statuses WHERE langua EQ sy-langu.
    ENDIF.

    LOOP AT idoc_statuses ASSIGNING FIELD-SYMBOL(<status>).
      MODIFY idocs FROM VALUE #( old_status_text = <status>-descrp )
                   TRANSPORTING old_status_text
                   WHERE old_status = <status>-status.
    ENDLOOP.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_IDOC_REPROCESSOR->SELECT_IDOC_COUNT
* +-------------------------------------------------------------------------------------------------+
* | [--->] SELECTION_CRITERIA             TYPE        SELECTION_CRITERIA
* | [<-()] IDOCS_COUNT                    TYPE        I
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD select_idoc_count.

    DATA(status_filter) = get_status_filter( selection_criteria-status_range ).

    TRY.
        SELECT COUNT(*)
          FROM edidc
          INTO idocs_count
         WHERE docnum IN selection_criteria-docnum_range AND
               status IN status_filter AND
               mestyp IN selection_criteria-mestyp_range AND
               credat IN selection_criteria-credat_range AND
               upddat IN selection_criteria-upddat_range.

      CATCH cx_root INTO DATA(exception).
        MESSAGE exception->get_text( ) TYPE 'I'.
    ENDTRY.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->SET_IDOC_REPROCESSORS
* +-------------------------------------------------------------------------------------------------+
* | [<-->] IDOC_LIST                      TYPE        ZIF_IDOC_REPROCESSOR=>IDOC_LIST
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD set_idoc_reprocessors.

    LOOP AT get_reprocessors( ) ASSIGNING FIELD-SYMBOL(<reprocessor>).
      MODIFY idoc_list FROM VALUE #( reprocessor = <reprocessor>-program )
                       TRANSPORTING reprocessor
                       WHERE old_status IN <reprocessor>-status_range
                         AND reprocessor <> 'CUSTOM LOGIC'.
    ENDLOOP.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_IDOC_REPROCESSOR->SET_IDOC_STATUSES
* +-------------------------------------------------------------------------------------------------+
* | [<-->] IDOC_LIST                      TYPE        ZIF_IDOC_REPROCESSOR=>IDOC_LIST
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD set_idoc_statuses.

    CHECK idoc_list IS NOT INITIAL.

    TYPES: BEGIN OF status,
             docnum TYPE edidc-docnum,
             upddat TYPE edidc-upddat,
             status TYPE edidc-status,
             "descrp TYPE teds2-descrp,
           END OF status.

    " Use hashed table for O(1) lookups instead of O(N) linear scan
    DATA new_statuses TYPE HASHED TABLE OF status WITH UNIQUE KEY docnum.

    TRY.
        SELECT a~docnum, a~upddat, a~status", b~descrp
          FROM edidc AS a
          "LEFT OUTER JOIN teds2 AS b ON b~status = a~status
          "                          AND b~langua = @sy-langu
           FOR ALL ENTRIES IN @idoc_list
         WHERE a~docnum = @idoc_list-docnum
          INTO TABLE @new_statuses.

      CATCH cx_root INTO DATA(exception).
        MESSAGE exception->get_text( ) TYPE 'I'.
    ENDTRY.

    LOOP AT idoc_list ASSIGNING FIELD-SYMBOL(<idoc>).
      READ TABLE new_statuses ASSIGNING FIELD-SYMBOL(<new_status>) WITH TABLE KEY docnum = <idoc>-docnum.
      IF sy-subrc = 0.
        <idoc>-new_status      = <new_status>-status.
        <idoc>-new_status_text = get_status_text( <idoc>-new_status ). "<new_status>-descrp.
        <idoc>-new_upddat      = <new_status>-upddat.
        <idoc>-status_changed  = COND #( WHEN <idoc>-old_status <> <idoc>-new_status
                                         THEN icon_set_state ELSE icon_space ).
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_IDOC_REPROCESSOR->SIMULATE
* +-------------------------------------------------------------------------------------------------+
* | [--->] SELECTION_CRITERIA             TYPE        SELECTION_CRITERIA
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD simulate.

    CHECK validate_selection( selection_criteria ) = abap_true.

    idoc_list = select_idocs( selection_criteria ).

    DATA custom_processed_idocs TYPE zif_idoc_reprocessor=>custom_processed_idocs.

    IF idoc_list IS NOT INITIAL.
      set_idoc_reprocessors( CHANGING idoc_list = idoc_list ).
    ENDIF.

    TRY .
        DATA zbd_idoc_reprocessor TYPE REF TO zbd_idoc_reprocessor.
        GET BADI zbd_idoc_reprocessor.

        CALL BADI zbd_idoc_reprocessor->process_idocs
          EXPORTING
            idoc_list       = idoc_list
            simulate        = abap_true
          CHANGING
            processed_idocs = custom_processed_idocs.

      CATCH cx_badi_not_implemented.
      CATCH cx_root INTO DATA(exception).
        MESSAGE exception->get_text( ) TYPE 'I'.
    ENDTRY.

    " Apply processing results back to idoc_list
    LOOP AT custom_processed_idocs ASSIGNING FIELD-SYMBOL(<processed_idoc>).
      MODIFY idoc_list FROM VALUE #( docnum           = <processed_idoc>-docnum
                                     new_status       = <processed_idoc>-status
                                     new_status_text  = get_status_text( <processed_idoc>-status )
                                     reprocessor      = 'CUSTOM LOGIC'
                                     message          = <processed_idoc>-message
                                    )
                       TRANSPORTING new_status
                                    new_status_text
                                    reprocessor
                                    message
                       WHERE docnum = <processed_idoc>-docnum.
    ENDLOOP.

    display_idoc_list(
      EXPORTING title = |{ sy-title } (Simulation)|
      CHANGING  idoc_list = idoc_list ).

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_IDOC_REPROCESSOR->VALIDATE_SELECTION
* +-------------------------------------------------------------------------------------------------+
* | [--->] SELECTION_CRITERIA             TYPE        SELECTION_CRITERIA
* | [<-()] IS_VALID                       TYPE        ABAP_BOOL
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD validate_selection.

    " At least one of the following selection criteria must be specified:
    " - Document number,
    " - Creation or change date,
    " - A valid combination of message type or status together with a date.

    is_valid = xsdbool(
      ( selection_criteria-docnum_range IS NOT INITIAL ) OR
      ( selection_criteria-credat_range IS NOT INITIAL ) OR
      ( selection_criteria-upddat_range IS NOT INITIAL ) OR
      ( selection_criteria-mestyp_range IS NOT INITIAL AND selection_criteria-credat_range IS NOT INITIAL ) OR
      ( selection_criteria-mestyp_range IS NOT INITIAL AND selection_criteria-upddat_range IS NOT INITIAL ) OR
      ( selection_criteria-status_range IS NOT INITIAL AND selection_criteria-credat_range IS NOT INITIAL ) OR
      ( selection_criteria-status_range IS NOT INITIAL AND selection_criteria-upddat_range IS NOT INITIAL ) ).

  ENDMETHOD.

ENDCLASS.
