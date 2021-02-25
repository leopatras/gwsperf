MAIN
  DEFINE starttime DATETIME HOUR TO FRACTION(1)
  DEFINE diff INTERVAL MINUTE TO FRACTION(1)
  LET starttime=CURRENT
  OPEN FORM f FROM arg_val(0)
  DISPLAY FORM f
  CALL ui.Interface.frontCall("qa","startQA",[],[])
  MENU
    COMMAND "qa_menu_ready"
      LET diff = CURRENT - starttime
      MESSAGE "diff:",diff
    ON ACTION butWithImage ATTRIBUTE(IMAGE="smiley")
    COMMAND "Exit"
       EXIT MENU
  END MENU
END MAIN
