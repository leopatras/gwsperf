IMPORT FGL fgldialog
MAIN
  DEFINE starttime DATETIME HOUR TO FRACTION(3)
  DEFINE diff INTERVAL MINUTE TO FRACTION(3)
  DEFINE i INT
  CONSTANT MAXCNT=1000
  LET starttime=CURRENT
  FOR i=1 TO MAXCNT
    CALL ui.interface.frontCall("standard","feinfo",["fename"], [])
  END FOR
  LET diff=CURRENT-starttime
  --CALL fgl_winMessage("Info",SFMT("time:%1,time for one frontcall:%2",diff,diff/MAXCNT),"info")
  DISPLAY sfmt("time:%1,time for one frontcall:%2",diff,diff/MAXCNT)
END MAIN
