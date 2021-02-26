OPTIONS SHORT CIRCUIT
IMPORT util
IMPORT os
--IMPORT FGL fglproxy

DEFINE m_starttime DATETIME HOUR TO FRACTION(1)
DEFINE m_isMac BOOLEAN
DEFINE m_verbose BOOLEAN
DEFINE m_gbcdir STRING

MAIN
  DEFINE port INT
  DEFINE text, path, data, content, fn STRING
  DEFINE c base.Channel
  DEFINE t TEXT
  LET m_starttime=CURRENT
  CALL init()
  LET port = findFreeServerPort(9100,9300,TRUE)
  LET c = base.Channel.create()
  CALL c.openServerSocket("127.0.0.1", port, "u")
  CALL openBrowser(sfmt("http://localhost:%1/stress.html",port))
  WHILE TRUE
    --DISPLAY "wait:"
    CALL nextRequest(c) RETURNING path, data
    --DISPLAY "+ request complete path:", path, ",data:", data
    IF path IS NULL THEN
      IF c.isEof() THEN
        DISPLAY "EOF"
        EXIT WHILE
      END IF
      CALL http404(c, "NULL request")
      CONTINUE WHILE
    END IF
    CASE path
      WHEN "/"
        LET text = "<!DOCTYPE html><html><body>Hello root</body></html>"
        CALL writeResponse(c, text)
      WHEN "/index.html"
        LET text = "<!DOCTYPE html><html><body>Hello index.html</body></html>"
        CALL writeResponse(c, text)
      WHEN "/exit"
        CALL writeResponse(c, "Exit seen")
        EXIT WHILE
      OTHERWISE
        LET fn = path.subString(2, path.getLength())
        --DISPLAY "try reading:", fn
        IF NOT os.Path.exists(fn) THEN
          DISPLAY "call http404 for :",fn
          CALL http404(c, fn)
        ELSE
          LOCATE t IN FILE fn
          LET content = t
          CALL writeResponse(c, content)
        END IF
    END CASE
  END WHILE
  DISPLAY "Finished in :",CURRENT - m_starttime
END MAIN

FUNCTION init()
  LET m_isMac = NULL
  LET m_verbose=fgl_getenv("VERBOSE") IS NOT NULL
END FUNCTION

FUNCTION writeResponse(c, content)
  DEFINE c base.Channel
  DEFINE content STRING
  CALL writeResponseInt(c, content, "200 OK")
END FUNCTION

FUNCTION http404(c, fn)
  DEFINE c base.Channel
  DEFINE fn, content STRING
  LET content = SFMT("Can't find: '%1'", fn)
  CALL writeResponseInt(c, content, "404 Not Found")
END FUNCTION

FUNCTION writeResponseInt(c, content, codedesc)
  DEFINE c base.Channel
  DEFINE content, codedesc STRING
  DEFINE content_length INT
  DEFINE s STRING
  DEFINE h STRING

  CALL writeLine(c, SFMT("HTTP/1.1 %1", codedesc))
  LET h = "Date: ", TODAY USING "DDD, DD MMM YYY", " ", TIME, " GMT"
  CALL writeLine(c, h)
  CALL writeLine(c, "Connection: close")

  LET content_length = content.getLength()
  CALL writeLine(c, "Content-Length: " || content_length)
  CALL writeLine(c, "Content-Type: text/html")
  CALL writeLine(c, "")
  CALL c.writeLine(content) -- writeOctets
  LET s = c.readLine() -- ??
  --DISPLAY "> ", content
  CALL c.writeLine(ASCII (26)) -- FIXME
END FUNCTION

FUNCTION nextRequest(c)
  DEFINE c base.Channel
  DEFINE method, path, data STRING
  DEFINE content_length INT
  DEFINE s STRING
  DEFINE a DYNAMIC ARRAY OF STRING
  LET s = c.readLine()
  IF s IS NULL THEN
    IF c.isEof() THEN
      DISPLAY "EOF"
      EXIT PROGRAM 1
    END IF
    RETURN "", ""
  END IF
  IF s.getCharAt(s.getLength()) == '\r' THEN
    LET s = s.subString(1, s.getLength() - 1)
  END IF
  LET a = split(s)
  LET method = a[1]
  LET path = a[2]
  IF a[3] <> "HTTP/1.1" THEN
    RETURN "", ""
  END IF
  WHILE s IS NOT NULL AND s.getLength() > 0
    --DISPLAY "< ", s
    LET s = c.readLine()
    IF s.getCharAt(s.getLength()) == '\r' THEN
      LET s = s.subString(1, s.getLength() - 1)
    END IF
    IF s.getLength() == 0 THEN
      EXIT WHILE
    END IF
    LET s = s.toLowerCase()
    IF s MATCHES "content-length:*" THEN
      LET content_length =
        s.subString(length("content-Length:") + 1, s.getLength())
      --DISPLAY "****", content_length
    END IF
  END WHILE
  IF content_length > 0 THEN
    LET data = c.readOctets(content_length)
    DISPLAY "< ", data
  END IF
  RETURN path, data
END FUNCTION

FUNCTION split(s)
  DEFINE a DYNAMIC ARRAY OF STRING
  DEFINE s STRING
  DEFINE t base.StringTokenizer
  LET t = base.StringTokenizer.create(s, ' ')
  LET a[1] = t.nextToken()
  LET a[2] = t.nextToken()
  LET a[3] = t.nextToken()
  RETURN a
END FUNCTION

FUNCTION writeLine(c, s)
  DEFINE c base.Channel
  DEFINE s STRING
  LET s = s, '\r'
  CALL c.writeLine(s)
END FUNCTION

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
  IF m_isMac IS NULL THEN
    LET m_isMac = isMacInt()
  END IF
  RETURN m_isMac
END FUNCTION

FUNCTION isMacInt()
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

PRIVATE FUNCTION _findGBCIn(dirname)
  DEFINE dirname STRING
  IF os.Path.exists(os.Path.join(dirname, "index.html"))
      AND os.Path.exists(os.Path.join(dirname, "index.html"))
      AND os.Path.exists(os.Path.join(dirname, "VERSION")) THEN
    LET m_gbcdir = dirname
    RETURN TRUE
  END IF
  RETURN FALSE
END FUNCTION

FUNCTION checkGBCAvailable()
  IF NOT _findGBCIn(os.Path.join(os.Path.pwd(), "gbc")) THEN
    IF NOT _findGBCIn(fgl_getenv("FGLGBCDIR")) THEN
      IF NOT _findGBCIn(
          os.Path.join(fgl_getenv("FGLDIR"), "web_utilities/gbc/gbc")) THEN
        CALL myerr(
            "Can't find a GBC in <pwd>/gbc, fgl_getenv('FGLGBCDIR') or $FGLDIR/web_utilities/gbc/gbc")
      END IF
    END IF
  END IF
END FUNCTION


FUNCTION log(logstr STRING)
  DEFINE ch base.Channel
  DEFINE diff INTERVAL MINUTE TO FRACTION(1)
  IF NOT m_verbose THEN
    RETURN --don't let write to stderr appear in the profile
  END IF
  LET ch = base.Channel.create()
  CALL ch.openFile("<stderr>", "w")
  LET diff = CURRENT - m_starttime
  CALL ch.writeLine(SFMT("%1 %2",diff,logstr))
  CALL ch.close()
END FUNCTION

FUNCTION copyFontAwesome()
  DEFINE libdir,fa STRING
  LET libdir=os.Path.join(base.Application.getFglDir(),"lib")
  LET fa=os.Path.join(libdir,"FontAwesome.ttf")
  IF NOT fileEqual(fa,"FontAwesome.ttf") THEN
    CALL log(sfmt("copy '%1' -> FontAwesome.ttf",fa))
    CALL os.Path.copy(fa,"FontAwesome.ttf") RETURNING status
  END IF
END FUNCTION

FUNCTION fileEqual(file1 STRING,file2 STRING)
  DEFINE code INT
  IF NOT os.Path.exists(file1) THEN
    --CALL log(sfmt("file1:%1 does not exist",file1))
    RETURN FALSE
  END IF
  IF NOT os.Path.exists(file2) THEN
    --CALL log(sfmt("file2:%1 does not exist",file2))
    RETURN FALSE
  END IF
  IF os.Path.size(file1) <> os.Path.size(file2) THEN
    --CALL log(sfmt("file1%1 size:%2 <> file2:%3 size:%4",file1,file2,os.Path.size(file1), os.Path.size(file2)))
    RETURN FALSE
  END IF
  IF isWin() THEN
    RUN sfmt('fc /B "%1" "%2" >NUL 2>&1',file1,file2) RETURNING code
  ELSE
    RUN sfmt("diff '%1' '%2'",file1,file2) RETURNING code
  END IF
  RETURN code==0
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
