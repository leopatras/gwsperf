IMPORT FGL utils
MAIN
  DEFINE ch base.Channel
  DEFINE jsfile, func STRING
  DEFINE i INT
  LET ch = base.Channel.create()
  CALL ch.openFile("stress.html", "w")
  CALL ch.writeLine("<html>")
  CALL ch.writeLine("<body>")
  CALL ch.writeLine("Hello")
  CALL ch.writeLine("</body>")
  CALL ch.writeLine(
      '<script language="JavaScript" type="text/javascript">var cnt=0;var starttime = new Date().getTime();</script>')
  FOR i = 1 TO utils.numStress
    LET func = SFMT("stress%1()", i)
    LET jsfile = SFMT("stress%1.js", i)
    CALL ch.writeLine(
        SFMT('<script language="JavaScript" type="text/javascript" src="%1" onload="%2"></script>',
            jsfile, func))
    CALL generateJs(jsfile, func)
  END FOR
  CALL ch.writeLine(
      SFMT('<script language="JavaScript" type="text/javascript" src="endStress.js" onload="endStress(%1)"></script>',
          utils.numStress))
  CALL ch.writeLine("</html>")
END MAIN

FUNCTION generateJs(jsfile STRING, func STRING)
  DEFINE ch base.Channel
  LET ch = base.Channel.create()
  CALL ch.openFile(jsfile, "w")
  CALL ch.writeLine(SFMT("function %1 { cnt = cnt + 1;}", func))
  CALL ch.close()
END FUNCTION
