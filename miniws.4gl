--small webserver for internal test
OPTIONS
SHORT CIRCUIT
IMPORT com
IMPORT os
IMPORT FGL fglproxy
DEFINE m_htport INT
DEFINE m_owndir, m_privdir STRING
DEFINE m_showallheaders STRING
DEFINE m_starttime DATETIME HOUR TO FRACTION(1)

MAIN
  DEFINE req com.HTTPServiceRequest
  DEFINE text, url, path, fname, pre,clitag STRING
  DEFINE gzip BOOLEAN
  LET m_starttime=CURRENT
  CALL fglproxy.init()
  LET m_owndir = os.Path.fullPath(os.Path.dirname(arg_val(0)))
  LET m_privdir = os.Path.join(m_owndir, "priv")
  LET m_showallheaders = fgl_getenv("SHOWALLHEADERS")
  CALL os.Path.mkdir(m_privdir) RETURNING status
  LET m_htport = fglproxy.findFreeServerPort(9100,9300,FALSE)
  CALL fgl_setenv("FGLAPPSERVER",m_htport)
  --do I need this option?
  CALL com.WebServiceEngine.setOption("server_readwritetimeout", -1)
  CALL com.WebServiceEngine.Start()
  LET pre=sfmt("http://localhost:%1/",m_htport)
  LET url=sfmt("%1stress.html",pre)
  --LET url=sfmt("%1bart.png",pre)
  CALL fglproxy.openBrowser(url)
  WHILE TRUE
    LET req = com.WebServiceEngine.getHTTPServiceRequest(-1)
    IF req IS NULL THEN
      DISPLAY "ERROR: getHTTPServiceRequest timed out (60 seconds). Exiting."
      EXIT WHILE
    ELSE
      LET url = req.getURL()
      --DISPLAY "url:",url
      CALL fglproxy.getIfNoneMatchAndGzip(req) RETURNING clitag,gzip
&ifndef COM_HAS_URLPATH
      LET path = getUrlPath(url)
&else
      LET path = req.getUrlPath()
&endif
      DISPLAY "miniws path:", path, ",", req.getMethod(),",clitag:",clitag
      CASE
        WHEN path = "/index.html"
          LET text = "<!DOCTYPE html><html><body>Hello</body></html>"
          CALL setContentType(req, "text/html")
          CALL req.sendTextResponse(200, NULL, text)
        WHEN path = "/text"
          CALL setContentType(req, "text/plain")
          CALL req.sendTextResponse(200, NULL, "A text")
        WHEN path = "/exit"
          CALL setContentType(req, "text/plain")
          CALL req.sendTextResponse(200, NULL, "Exit seen")
          EXIT WHILE
        OTHERWISE
          LET fname = path.subString(2,path.getLength())
          DISPLAY "fname:",fname
          CALL fglproxy.processFile(req, fname, clitag, gzip, TRUE) --do cache
      END CASE
    END IF
  END WHILE
  DISPLAY "Finished in :",CURRENT - m_starttime
END MAIN

FUNCTION getUrlPath(url)
  DEFINE url STRING
  DEFINE idx INT
  LET idx=url.getIndexOf("://",1)
  IF idx>0 THEN --remove scheme
    LET url=url.subString(idx+3,url.getLength())
  END IF
  LET idx=url.getIndexOf("/",1)
  IF idx>0 THEN --remove host
    LET url=url.subString(idx,url.getLength())
  END IF
  LET idx=url.getIndexOf("?",1)
  IF idx>0 THEN --remove query
    LET url=url.subString(1,idx-1)
  END IF
  RETURN url
END FUNCTION


FUNCTION processFile(req, fname)
  DEFINE req com.HTTPServiceRequest
  DEFINE fname, ct, ext STRING
  LET ext = downshift(os.Path.extension(fname))
  IF NOT os.Path.exists(fname) THEN
    DISPLAY "  404 Not Found:", fname
    CALL req.sendTextResponse(404, NULL, SFMT("File:%1 not found", fname))
    RETURN
  END IF
  CASE
    WHEN ext == "html" OR ext == "css" OR ext == "js"
      CASE
        WHEN ext == "html"
          LET ct = "text/html"
        WHEN ext == "js"
          LET ct = "application/x-javascript"
        WHEN ext == "css"
          LET ct = "text/css"
      END CASE
      CALL req.setResponseCharset("UTF-8")
      CALL setContentType(req, ct)
      DISPLAY "  200 OK:", fname
      CALL req.sendTextResponse(200, NULL, fglproxy.readTextFile(fname))
    OTHERWISE
      CASE
        WHEN ext == "gif"
          LET ct = "image/gif"
        WHEN ext == "png"
          LET ct = "image/png"
        WHEN ext == "jpg"
          LET ct = "image/jpeg"
        WHEN ext == "jpeg"
          LET ct = "image/jpeg"
        WHEN ext == "woff"
          LET ct = "application/font-woff"
        WHEN ext == "ttf"
          LET ct = "application/octet-stream"
      END CASE
      CALL setContentType(req, ct)
      DISPLAY "  200 OK:", fname
      CALL req.sendDataResponse(200, NULL, fglproxy.readBlob(fname))
  END CASE
END FUNCTION

FUNCTION setContentType(req, ct)
  DEFINE req com.HTTPServiceRequest
  DEFINE ct STRING
  IF ct IS NOT NULL THEN
    CALL req.setResponseHeader("Content-Type", ct)
  END IF
  CALL req.setResponseHeader("Cache-Control", "no-cache")
  CALL req.setResponseHeader("Expires", "-1")
  CALL req.setResponseHeader("Pragma", "no-cache")
  CALL req.setResponseHeader("Access-Control-Allow-Origin","*")
END FUNCTION
