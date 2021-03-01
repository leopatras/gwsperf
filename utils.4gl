IMPORT os

PUBLIC CONSTANT numStress=1000

DEFINE _gbcdir STRING

FUNCTION openBrowserWithStress(port INT)
  DEFINE url STRING
  LET url=sfmt("http://127.0.0.1:%1/stress.html",port)
  CALL openBrowser(url)
END FUNCTION


FUNCTION openBrowser(url STRING)
  DEFINE cmd, browser, gdcm STRING
  LET browser = fgl_getenv("BROWSER")
  DISPLAY "start URL:'", url, "' in browser:'", browser, "'"
  CASE
    WHEN browser IS NULL OR browser == "default" OR browser == "standard"
      CASE
        WHEN isWin()
          LET cmd = SFMT("start %1", url)
        WHEN isMac()
          LET cmd = SFMT("open %1", url)
        OTHERWISE --assume kinda linux
          LET cmd = SFMT("xdg-open %1", url)
      END CASE
    WHEN browser == "GDC"
      LET cmd =
          SFMT("%1 FGLSERVER=localhost:0&&fglrun urlwebco.42m %2",
              IIF(isWin(), "set", "export"), url)
    WHEN browser == "gwsreq"
      LET cmd=SFMT("fglrun gwsreq %1 %2", url, numStress)
    WHEN browser == "gdcm"
      CASE
        WHEN isWin()
          LET gdcm = ".\\gdcm.exe"
        WHEN isMac()
          LET gdcm = "./gdcm.app/Contents/MacOS/gdcm"
        OTHERWISE
          LET gdcm = "./gdcm"
      END CASE
      LET cmd = SFMT("%1 %2", gdcm, url)
    OTHERWISE
      IF isMac() THEN
        LET cmd = SFMT("open -a %1 %2", quote(fgl_getenv("BROWSER")), url)
      ELSE
        LET cmd = SFMT("%1 %2", quote(fgl_getenv("BROWSER")), url)
      END IF
  END CASE
  DISPLAY "browser cmd:", cmd
  RUN cmd WITHOUT WAITING
END FUNCTION

FUNCTION isWin()
  RETURN fgl_getenv("WINDIR") IS NOT NULL
END FUNCTION

FUNCTION isMac()
  DEFINE arr DYNAMIC ARRAY OF STRING
  IF NOT isWin() THEN
    CALL file_get_output("uname", arr)
    IF arr.getLength() < 1 THEN
      RETURN FALSE
    END IF
    IF arr[1] == "Darwin" THEN
      RETURN TRUE
    END IF
  END IF
  RETURN FALSE
END FUNCTION

FUNCTION file_get_output(program, arr)
  DEFINE program, linestr STRING
  DEFINE arr DYNAMIC ARRAY OF STRING
  DEFINE mystatus, idx INTEGER
  DEFINE c base.Channel
  LET c = base.channel.create()
  WHENEVER ERROR CONTINUE
  CALL c.openpipe(program, "r")
  LET mystatus = status
  WHENEVER ERROR STOP
  IF mystatus THEN
    CALL myerr(SFMT("program:%1, error:%2", program, err_get(mystatus)))
  END IF
  CALL arr.clear()
  WHILE (linestr := c.readline()) IS NOT NULL
    LET idx = idx + 1
    --DISPLAY "LINE ",idx,"=",linestr
    LET arr[idx] = linestr
  END WHILE
  CALL c.close()
END FUNCTION
{
FUNCTION openGDC()
  DEFINE gdc, cmd STRING
  LET gdc = m_gdc
  IF NOT os.Path.exists(gdc) THEN
    CALL myerr(SFMT("Can't find '%1'", gdc))
  END IF
  IF NOT os.Path.executable(gdc) THEN
    DISPLAY "Warning:os.Path not executable:", gdc
  END IF
  LET cmd = SFMT('"%1" -u %2', gdc, getUAGASURL())
  DISPLAY SFMT("RUN '%1' WITHOUT WAITING", cmd)
  RUN cmd WITHOUT WAITING
END FUNCTION
}

FUNCTION already_quoted(path)
  DEFINE path,first,last STRING
  LET first=NVL(path.getCharAt(1),"NULL")
  LET last=NVL(path.getCharAt(path.getLength()),"NULL")
  IF isWin() THEN
    RETURN (first=='"' AND last=='"')
  END IF
  RETURN (first=="'" AND last=="'") OR (first=='"' AND last=='"')
END FUNCTION

FUNCTION quote(path)
  DEFINE path STRING
  IF path.getIndexOf(" ",1)>0 THEN
    IF NOT already_quoted(path) THEN
      LET path='"',path,'"'
    END IF
  ELSE
    IF already_quoted(path) AND isWin() THEN --remove quotes(Windows)
      LET path=path.subString(2,path.getLength()-1)
    END IF
  END IF
  RETURN path
END FUNCTION

FUNCTION myerr(err)
  DEFINE err STRING
  DISPLAY "ERROR:", err
  EXIT PROGRAM 1
END FUNCTION

PRIVATE FUNCTION _findGBCIn(dirname)
  DEFINE dirname STRING
  IF os.Path.exists(os.Path.join(dirname, "index.html"))
      AND os.Path.exists(os.Path.join(dirname, "index.html"))
      AND os.Path.exists(os.Path.join(dirname, "VERSION")) THEN
    LET _gbcdir = dirname
    RETURN TRUE
  END IF
  RETURN FALSE
END FUNCTION

FUNCTION checkGBCAvailable()
  LET _gbcdir=NULL
  IF NOT _findGBCIn(os.Path.join(os.Path.pwd(), "gbc")) THEN
    IF NOT _findGBCIn(fgl_getenv("FGLGBCDIR")) THEN
      IF NOT _findGBCIn(
          os.Path.join(fgl_getenv("FGLDIR"), "web_utilities/gbc/gbc")) THEN
        CALL myerr(
            "Can't find a GBC in <pwd>/gbc, fgl_getenv('FGLGBCDIR') or $FGLDIR/web_utilities/gbc/gbc")
      END IF
    END IF
  END IF
  RETURN _gbcdir
END FUNCTION

FUNCTION findFreeServerPort(start, end, local)
  DEFINE start, end, local, freeport INT
  DEFINE ch base.Channel
  DEFINE i INT
  LET local = TRUE
  LET ch = base.Channel.create()
  FOR i = start TO end
    TRY
      CALL ch.openServerSocket(IIF(local, "127.0.0.1", NULL), i, "u")
      LET freeport = i
      EXIT FOR
    CATCH
      DISPLAY SFMT("can't bind port %1:%2", i, err_get(status))
    END TRY
  END FOR
  IF freeport > 0 THEN
    CALL ch.close()
    --DISPLAY "found free port:",freeport
    RETURN freeport
  END IF
  CALL myerr(SFMT("Can't find free port in the range %1-%2", start, end))
  RETURN -1
END FUNCTION
