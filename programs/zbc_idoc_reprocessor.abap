*&---------------------------------------------------------------------*
*& Report ZBC_IDOC_REPROCESSOR
*&---------------------------------------------------------------------*
* This program reprocesses IDocs by executing the relevant SAP standard
* programs according to the current status of each IDoc.
* See program documentation.
*----------------------------------------------------------------------*

REPORT zbc_idoc_reprocessor.

TABLES sscrfields.

DATA _edidc_docnum TYPE edidc-docnum.
DATA _edidc_status TYPE edidc-status.
DATA _edidc_mestyp TYPE edidc-mestyp.
DATA _edidc_credat TYPE edidc-credat.
DATA _edidc_upddat TYPE edidc-upddat.

DATA selection_criteria TYPE zcl_idoc_reprocessor=>selection_criteria.
DATA idoc_count TYPE i.

*--------------------------------------------------------------------*
* SELECTION-SCREEN
*--------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK main_selection WITH FRAME TITLE TEXT-se1.
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN PUSHBUTTON (4) b_sel USER-COMMAND uc_sel.
SELECTION-SCREEN END OF LINE.

SELECT-OPTIONS docnum FOR _edidc_docnum.
SELECT-OPTIONS status FOR _edidc_status.
SELECT-OPTIONS mestyp FOR _edidc_mestyp.
SELECT-OPTIONS credat FOR _edidc_credat.
SELECT-OPTIONS upddat FOR _edidc_upddat.
SELECTION-SCREEN END OF BLOCK main_selection.

SELECTION-SCREEN BEGIN OF BLOCK processing_options WITH FRAME TITLE TEXT-op1.

SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS simulate RADIOBUTTON GROUP opt1 DEFAULT 'X'.
SELECTION-SCREEN COMMENT 05(32) c_simu FOR FIELD simulate.
SELECTION-SCREEN POSITION POS_HIGH.
SELECTION-SCREEN PUSHBUTTON (4) b_simu USER-COMMAND uc_simu.
SELECTION-SCREEN END OF LINE.

SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS reproces RADIOBUTTON GROUP opt1.
SELECTION-SCREEN COMMENT 05(12) c_repro1 FOR FIELD reproces.
SELECTION-SCREEN COMMENT 18(05) c_repro2.
SELECTION-SCREEN POSITION POS_HIGH.
SELECTION-SCREEN PUSHBUTTON (4) b_repro USER-COMMAND uc_repro.
SELECTION-SCREEN END OF LINE.

SELECTION-SCREEN END OF BLOCK processing_options.

SELECTION-SCREEN BEGIN OF BLOCK additional_options WITH FRAME TITLE TEXT-op2.

" Large Selection Threshold (The count limit before confirmation popup)
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 01(30) c_thres FOR FIELD threshld.
SELECTION-SCREEN POSITION POS_LOW.
PARAMETERS threshld TYPE n LENGTH 5 DEFAULT '1000' VISIBLE LENGTH 5.
SELECTION-SCREEN COMMENT 40(5) c_row.
SELECTION-SCREEN POSITION POS_HIGH.
SELECTION-SCREEN PUSHBUTTON (4) b_thres USER-COMMAND uc_thres.
SELECTION-SCREEN END OF LINE.

" Inter-Process Wait (Pause interval (seconds) between successive reprocessing program calls)
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 01(30) c_wait FOR FIELD wait.
SELECTION-SCREEN POSITION POS_LOW.
PARAMETERS wait TYPE byte DEFAULT '1'.
SELECTION-SCREEN COMMENT 40(7) c_sec.
SELECTION-SCREEN POSITION POS_HIGH.
SELECTION-SCREEN PUSHBUTTON (4) b_wait USER-COMMAND uc_wait.
SELECTION-SCREEN END OF LINE.

SELECTION-SCREEN END OF BLOCK additional_options.

*--------------------------------------------------------------------*
* INITIALIZATION
*--------------------------------------------------------------------*
INITIALIZATION.
  c_simu   = 'Simulate...'.
  c_repro1 = 'Reprocess...'.
  c_repro2 = icon_warning.
  c_thres  = 'Large Selection Threshold'.
  c_row    = 'rows'.
  c_wait   = 'Inter-Process Wait'.
  c_sec    = 'seconds'.
  b_sel    = icon_paw_item.
  b_simu   = icon_paw_item.
  b_repro  = icon_paw_item.
  b_thres  = icon_paw_item.
  b_wait   = icon_paw_item.

*--------------------------------------------------------------------*
* AT SELECTION-SCREEN
*--------------------------------------------------------------------*
AT SELECTION-SCREEN.

  CASE sscrfields-ucomm.
    WHEN 'UC_SEL'.
      zcl_gui_context_help=>get_instance( )->display(
        context_title = 'Main Selection Criteria'
        context_html  = |<p>At least one of the following selection criteria must be specified:|
                     && |<ul>|
                     && |<li>Document number</li>|
                     && |<li>Creation or change date</li>|
                     && |<li>A valid combination of message type or status together with a date</li>|
                     && |</ul>|
                     && |<table class="callout-info"><tr><td width="15" align="center" valign="top">{ zcl_gui_context_help=>symbols-info }</td>|
                     && |<td>Any statuses entered other than those listed below will be excluded from the selection: |
                     && |<p><b>02, 04, 05, 25, 26, 29, 30, 32, 37, 51, 56, 60, 61, 63, 64, 65, 66, 69</b></p></td>|
                     && |</tr></table>| ).

    WHEN 'UC_SIMU'.
      zcl_gui_context_help=>get_instance( )->display(
        context_title = 'Simulation Mode'
        context_html  = |<p>Simulation mode analyzes the selected IDocs without executing any reprocessing programs.</p>|
                     && |<p>The system determines which SAP standard program would be called for each IDoc based on its current status.</p>|
                     && |<ul>|
                     && |<li>No status changes are performed.</li>|
                     && |<li>No reprocessing function modules or reports are executed.</li>|
                     && |<li>No database updates are triggered.</li>|
                     && |</ul>|
                     && |<table class="callout-info"><tr><td width="15" align="center" valign="top">{ zcl_gui_context_help=>symbols-info }</td>|
                     && |<td>Use Simulation to verify your selection criteria and review the expected processing behavior before executing actual reprocessing.</td>|
                     && |</tr></table>| ).

    WHEN 'UC_REPRO'.
      zcl_gui_context_help=>get_instance( )->display(
        context_title = 'Reprocessing Mode'
        context_html  = |<p>Reprocessing mode executes the appropriate SAP standard program for the selected IDocs based on their current status.</p>|
                     && |<p>Depending on the status, the system calls reports such as RBDAPP01, RBDMANI2, RBDAGAI2, RBDAGAIN, RBDAGAIE, RBDSYNEI, RBDSYNEO, or RSEOUT00.</p>|
                     && |<ul>|
                     && |<li>IDoc statuses may change during processing.</li>|
                     && |<li>Application documents may be created, posted, or updated.</li>|
                     && |<li>The standard error-handling logic of the respective SAP program is applied.</li>|
                     && |</ul>|
                     && |<table class="callout-warning"><tr><td width="15" align="center" valign="top">{ zcl_gui_context_help=>symbols-warning }</td>|
                     && |<td>Reprocessing may modify application data and cannot be automatically reversed.</td>|
                     && |</tr></table>| ).

    WHEN 'UC_THRES'.
      zcl_gui_context_help=>get_instance( )->display(
        context_title = 'Large Selection Threshold'
        context_html  = |<p>Defines the maximum number of IDocs that can be selected without triggering a warning message.</p>|
                     && |<p>During execution, the system counts the IDocs that match your selection criteria.</p>|
                     && |<p>If the number of matching records exceeds the value entered here, a warning popup is displayed.</p>|
                     && |<ul>|
                     && |<li><b>No</b>: Cancels the selection so you can refine your filters (e.g., by date or message type).</li>|
                     && |<li><b>Yes</b>: Continues and attempts to load all matching records.</li>|
                     && |</ul>|
                     && |<table class="callout-info"><tr><td width="15" align="center" valign="top">{ zcl_gui_context_help=>symbols-info }</td>|
                     && |<td>The Large Selection Threshold is ignored when the program runs as a background job.</td>|
                     && |</tr></table>|
                     && |<p></p>|
                     && |<table class="callout-warning"><tr><td width="15" align="center" valign="top">{ zcl_gui_context_help=>symbols-warning }</td>|
                     && |<td>Selecting a very large number of IDocs may impact system performance or cause a timeout in foreground execution.</td>|
                     && |</tr></table>| ).

    WHEN 'UC_WAIT'.
      zcl_gui_context_help=>get_instance( )->display(
        context_title = 'Inter-Process Wait (seconds)'
        context_html  = |<p>Specifies the pause interval (in seconds) between successive reprocessing program calls.</p>|
                     && |<p>During execution, the program waits this number of seconds before starting the next reprocessing call.</p>| ).

    WHEN 'UC_BADI'.
      zcl_gui_context_help=>get_instance( )->display(
        context_title = 'Enable Custom Logic'
        context_html  = |<p>If active, an available implementation of BAdI ZBD_IDOC_REPROCESSOR is called before standard reprocessing.</p>|
                     && |<table class="callout-warning"><tr><td width="15" align="center" valign="top">{ zcl_gui_context_help=>symbols-warning }</td>|
                     && |<td>Ensure that the BAdI implementation is thoroughly tested before enabling it in production.</td>|
                     && |</tr></table>| ).

    WHEN 'ONLI'.
      selection_criteria = VALUE zcl_idoc_reprocessor=>selection_criteria(
                                    docnum_range = docnum[]
                                    mestyp_range = mestyp[]
                                    status_range = status[]
                                    credat_range = credat[]
                                    upddat_range = upddat[]
                                    ).

      IF NOT zcl_idoc_reprocessor=>get_instance( )->validate_selection( selection_criteria ).
        IF sy-batch = abap_true.
          MESSAGE 'Selection is not valid.' TYPE 'I'.
        ELSE.
          MESSAGE 'Selection is not valid.' TYPE 'E' DISPLAY LIKE 'W'.
        ENDIF.
      ENDIF.

      idoc_count = zcl_idoc_reprocessor=>get_instance( )->select_idoc_count( selection_criteria ).
      IF idoc_count = 0.
        IF sy-batch = abap_true.
          MESSAGE 'No IDocs found for selection.' TYPE 'I'.
        ELSE.
          MESSAGE 'No IDocs found for selection.' TYPE 'E' DISPLAY LIKE 'W'.
        ENDIF.
      ENDIF.

      " Confirm large selection (only for foreground)
      IF sy-batch = abap_false AND idoc_count > threshld.
        IF NOT zcl_idoc_reprocessor=>get_instance( )->confirm_large_selection(
                 count     = idoc_count
                 threshold = CONV #( threshld ) ).
          MESSAGE 'Process cancelled by user.' TYPE 'E' DISPLAY LIKE 'W'.
        ENDIF.
      ENDIF.
  ENDCASE.

*--------------------------------------------------------------------*
* START-OF-SELECTION
*--------------------------------------------------------------------*
START-OF-SELECTION.

  DATA(idoc_reprocessor) = zcl_idoc_reprocessor=>get_instance( ).

  CASE abap_true.
    WHEN reproces.
      IF idoc_reprocessor->confirm_reprocessing( idoc_count ).
        idoc_reprocessor->reprocess(
            selection_criteria = selection_criteria
            interprocess_wait  = wait
            display_idocs      = abap_true ).
      ELSE.
        MESSAGE 'Process cancelled by user.' TYPE 'S'.
        RETURN.
      ENDIF.

    WHEN simulate.
      idoc_reprocessor->simulate( selection_criteria ).
  ENDCASE.
