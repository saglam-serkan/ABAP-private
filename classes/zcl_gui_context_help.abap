CLASS zcl_gui_context_help DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE .

  PUBLIC SECTION.

    CONSTANTS: BEGIN OF symbols,
                 info    TYPE c LENGTH 7 VALUE '&#8505;',
                 warning TYPE c LENGTH 7 VALUE '&#9888;',
               END OF symbols.

    CLASS-METHODS get_instance
      RETURNING VALUE(instance) TYPE REF TO zcl_gui_context_help .

    METHODS display
      IMPORTING !window_title  TYPE string DEFAULT 'Context Help'
                !window_size   TYPE string DEFAULT cl_abap_browser=>small
                !context_title TYPE string
                !context_html  TYPE string .

  PROTECTED SECTION.

  PRIVATE SECTION.

    CLASS-DATA instance TYPE REF TO zcl_gui_context_help.
    METHODS get_css RETURNING VALUE(css) TYPE string.

ENDCLASS.



CLASS zcl_gui_context_help IMPLEMENTATION.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_GUI_CONTEXT_HELP->DISPLAY
* +-------------------------------------------------------------------------------------------------+
* | [--->] WINDOW_TITLE                   TYPE        STRING (default ='Context Help')
* | [--->] WINDOW_SIZE                    TYPE        STRING (default =CL_ABAP_BROWSER=>SMALL)
* | [--->] CONTEXT_TITLE                  TYPE        STRING
* | [--->] CONTEXT_HTML                   TYPE        STRING
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD display.

    DATA(html_string) =
      |<html><head><style>{ get_css( ) }</style></head>| &&
      |<body>| &&
      |  <h1>{ context_title }</h1>| &&
      |  <div class="content">{ context_html }</div>| &&
      |</body></html>|.

    cl_abap_browser=>show_html(
      title       = CONV #( window_title )
      size        = window_size
      html_string = html_string
      format      = cl_abap_browser=>landscape ).

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_GUI_CONTEXT_HELP->GET_CSS
* +-------------------------------------------------------------------------------------------------+
* | [<-()] CSS                            TYPE        STRING
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_css.

    css =
      | body \{| &&
      |     background-color: #FEFEEE;| &&
      |     font-family: Arial, Helvetica, sans-serif;| &&
      |     margin: 10px;| &&
      |     color: #000;| &&
      | \} | &&
      | h1 \{| &&
      |     color: #003366;| &&
      |     font-size: 15px;| &&
      |     margin: 0 0 10px 0;| &&
      |     border-bottom: 1px solid #CCC;| &&
      |     padding-bottom: 5px;| &&
      | \} | &&
      | p \{| &&
      |     font-size: 13px;| &&
      |     line-height: 1.5;| &&
      |     margin: 0 0 10px 0;| &&
      | \} | &&
      | ul \{| &&
      |     margin: 10px 0;| &&
      |     padding-left: 20px;| &&
      |     font-size: 13px;| &&
      | \} | &&
      | li \{| &&
      |     margin-bottom: 3px;| &&
      | \} | &&
      | table \{| &&
      |     font-family: Arial, Helvetica, sans-serif;| &&
      |     font-size: 13px;| &&
      | \} | &&
      | code \{| &&
      |     background: #EEE;| &&
      |     padding: 2px 4px;| &&
      |     border-radius: 3px;| &&
      |     font-family: 'Consolas', monospace;| &&
      | \} | &&
      | pre \{| &&
      |     background: #606060;| &&
      |     color: #F8F8F2;| &&
      |     padding: 12px;| &&
      |     border-radius: 5px;| &&
      |     font-family: 'Consolas', monospace;| &&
      |     font-size: 13px;| &&
      |     overflow-x: auto;| &&
      |     border-left: 5px solid #303030;| &&
      | \} | &&
      | .content \{| &&
      |     font-size: 13px;| &&
      |     line-height: 1.5;| &&
      | \} | &&
      | .callout-warning \{| &&
      |     border: 1px solid #cc0000; | && " Red border
      |     background-color: #fff4f4; | && " Light red background
      |     border-collapse: collapse; | &&
      |     width: 100%; | &&
      | \} | &&
      | .callout-warning td \{| &&
      |     padding: 3px; | &&
      |     vertical-align: top; | &&
      | \} | &&
      | .callout-info \{| &&
      |     border: 1px solid #3399FF; | && " Blue border
      |     background-color: #E6F0FF; | && " Light blue background
      |     border-collapse: collapse; | &&
      |     width: 100%; | &&
      | \} | &&
      | .callout-info td \{| &&
      |     padding: 3px; | &&
      |     vertical-align: top; | &&
      | \} |.

  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Static Public Method ZCL_GUI_CONTEXT_HELP=>GET_INSTANCE
* +-------------------------------------------------------------------------------------------------+
* | [<-()] INSTANCE                       TYPE REF TO ZCL_GUI_CONTEXT_HELP
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_instance.

    IF zcl_gui_context_help=>instance IS NOT BOUND.
      zcl_gui_context_help=>instance = NEW #( ).
    ENDIF.

    instance = zcl_gui_context_help=>instance.

  ENDMETHOD.
  
ENDCLASS.
