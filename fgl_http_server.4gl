OPTIONS SHORT CIRCUIT
IMPORT util
IMPORT os
IMPORT FGL fglproxy

DEFINE m_starttime DATETIME HOUR TO FRACTION(1)

MAIN
  DEFINE port INT
  DEFINE text, path, data, content, fn STRING
  DEFINE c base.Channel
  DEFINE t TEXT
  LET m_starttime=CURRENT
  CALL fglproxy.init()
  LET port = fglproxy.findFreeServerPort(9100,9300,TRUE)
  LET c = base.Channel.create()
  CALL c.openServerSocket("127.0.0.1", port, "u")
  CALL fglproxy.openBrowser(sfmt("http://localhost:%1/stress.html",port))
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
