--invoke standalone with BROWSER
--set BROWSER=default&&fglrun fglproxy simpleform
--runs the sample in the default system browser

--set BROWSER=GDC&&fglrun fglproxy simpleform
--runs the sample in an url based webco in GDC

--set BROWSER=gdcm&&fglrun fglproxy simpleform
--runs the sample in the gdcm browser

OPTIONS
SHORT CIRCUIT
IMPORT com
IMPORT os
IMPORT FGL utils
DEFINE m_channel base.Channel
DEFINE m_vmcmd STRING
DEFINE m_gbcdir STRING
DEFINE m_htport INT
DEFINE m_owndir STRING
DEFINE m_privdir STRING
DEFINE m_pubdir STRING
DEFINE m_progdir STRING
DEFINE m_fglserver STRING
DEFINE m_fglproxyhost STRING
DEFINE m_mydir STRING
DEFINE m_showallheaders STRING
DEFINE m_GDC STRING
DEFINE m_starttime DATETIME HOUR TO FRACTION(1)
DEFINE m_verbose BOOLEAN

CONSTANT C_FGLAPPSERVER="FGLAPPSERVER"

MAIN
  DEFINE i INT
  CONSTANT startport= 9363
  DEFINE foundFree BOOLEAN
  DEFINE cliurl, url, trial, htpre STRING
  DEFINE req com.HTTPServiceRequest
  DEFINE uapre, gbcpre, priv, pub, fname, body, clitag STRING
  DEFINE gzip BOOLEAN
  LET m_starttime=CURRENT
  IF num_args() < 1 THEN
    CALL myerr(SFMT("usage: fglrun %1 <program>", arg_val(0)))
  END IF
  LET m_mydir = os.Path.fullPath(os.Path.dirname(arg_val(0)))
  LET m_fglserver = fgl_getenv("FGLSERVER")
  IF m_fglserver IS NULL THEN
    LET m_fglserver = "localhost:0"
  END IF
  --set FGLPROXYHOST if you need to connect to fglproxy from another machine (device)
  LET m_fglproxyhost = fgl_getenv("FGLPROXYHOST")
  IF m_fglproxyhost IS NULL THEN
    LET m_fglproxyhost = "localhost"
  END IF
  LET m_showallheaders = fgl_getenv("SHOWALLHEADERS")
  CALL init()
  LET m_gbcdir = checkGBCAvailable()
  LET m_owndir = os.Path.fullPath(os.Path.dirName(arg_val(0)))
  LET m_privdir = os.Path.join(m_owndir, "priv")
  --make FGLDIR/lib/FontAwesome.ttf cacheable..but this is just a hack
  --LET m_pubdir = os.Path.join(fgl_getenv("FGLDIR"), "lib")
  CALL copyFontAwesome()
  LET m_pubdir = m_owndir
  CALL os.Path.mkdir(m_privdir) RETURNING status
  --do I need this option?
  CALL com.WebServiceEngine.setOption("server_readwritetimeout", -1)
  CALL fgl_setenv(C_FGLAPPSERVER, startport) --avoid a random port to ensure caching
  FOR i = startport TO startport+200
    TRY
      CALL com.WebServiceEngine.Start()
      LET foundFree = TRUE
      LET m_htport=fgl_getenv(C_FGLAPPSERVER)
      --CALL log(sfmt("found free server port:%1",m_htport))
      EXIT FOR
    CATCH
      LET m_htport = i
      CALL fgl_setenv("FGLAPPSERVER", m_htport)
    END TRY
  END FOR
  IF NOT foundFree THEN
    CALL myerr("no free port")
  END IF
  LET htpre = SFMT("http://%1:%2/", m_fglproxyhost, m_htport)
  LET gbcpre = htpre, "gbc/"
  LET uapre = htpre, "ua/"
  LET priv = htpre, "priv/"
  LET pub = htpre, "pub/"
  LET cliurl = sfmt("%1index.html?app=foobar",gbcpre)
  CALL setup_program(priv, pub)
  DISPLAY cliurl
  CALL log(sfmt("SLAVE:%1,BROWSER:%2",fgl_getenv("SLAVE"),fgl_getenv("BROWSER")))
  IF (fgl_getenv("SLAVE") IS NULL) THEN
    CALL openBrowser(cliurl)
  END IF
  --this is the client url the Qt program needs to invoke
  --
  WHILE TRUE
    LET req = com.WebServiceEngine.getHTTPServiceRequest(-1)
    IF req IS NULL THEN
      CALL log("ERROR: getHTTPServiceRequest timed out (60 seconds). Exiting.")
      EXIT WHILE
    ELSE
      LET url = req.getURL()
      CALL log(SFMT("URL:%1,%2", url, req.getMethod()))
      CALL getIfNoneMatchAndGzip(req) RETURNING clitag,gzip
      CASE
        WHEN url.getIndexOf(uapre, 1) == 1 --ua proto
          IF req.getMethod() == "POST" THEN
            LET body = req.readTextRequest()
            CALL log(SFMT("  PROTOCOL:%1", body))
            IF body.getLength() > 0 AND m_channel IS NOT NULL THEN
              CALL m_channel.writeNoNL(body)
            END IF
          END IF
          IF m_vmcmd IS NULL AND m_channel IS NOT NULL THEN
            --DISPLAY "BEFORE readline"
            LET m_vmcmd = m_channel.readLine()
            --DISPLAY "AFTER readline"
            IF m_channel.isEof() THEN
              CALL log("!!!EOF")
              CALL req.setResponseHeader("X-FourJs-Closed", "true")
              CALL m_channel.close()
              LET m_channel = NULL
            END IF
          END IF
          CALL req.setResponseHeader(
              "Content-Type", "text/plain; charset=UTF-8")
          CALL req.setResponseHeader("Cache-Control", "no-cache")
          CALL req.setResponseHeader("Expires", "-1")
          CALL req.setResponseHeader("Pragma", "no-cache")
          CALL req.setResponseHeader("Connection", "Keep-Alive")
          CALL req.setResponseHeader("X-FourJs-Development", "true")
          CALL req.setResponseHeader("X-FourJs-Version", "2.0")
          --CALL req.setResponseHeader("X-FourJs-GBC","gbc")
          CALL req.setResponseHeader(
              "X-FourJs-GBC",
              SFMT("http://%1:%2/gbc", m_fglproxyhost, m_htport))
          CALL req.setResponseHeader("X-FourJs-Timeout", "3600")
          CALL req.setResponseHeader("X-FourJs-WebComponent", "webcomponents")
          CALL req.setResponseHeader("X-FourJs-Id", "0815")
          CALL req.setResponseHeader("X-FourJs-PageId", "1")
          CALL log(
              SFMT("  sendTextResponse:%1,len:%2",
                  m_vmcmd, m_vmcmd.getLength()))
          IF m_vmcmd.getLength() == 0 THEN
            CALL req.sendResponse(200, NULL)
            IF m_channel IS NULL THEN
              EXIT WHILE
            END IF
          ELSE
            LET m_vmcmd = m_vmcmd, "\n"
            CALL req.sendTextResponse(200, NULL, m_vmcmd)
          END IF
          LET m_vmcmd = NULL

        WHEN url.getIndexOf(gbcpre, 1) == 1 --gbc asset
          LET fname = url.subString(gbcpre.getLength() + 1, url.getLength())
          LET fname = cut_question(fname)
          IF fname.getIndexOf("webcomponents", 1) THEN
            LET fname = fname.subString(15, fname.getLength())
            --first look in <programdir>/webcomponents
            LET trial = os.Path.join(m_progdir, fname)
            IF os.Path.exists(trial) THEN
              LET fname = trial
            ELSE
              --lookup the fgl web components
              --DISPLAY "Can't find:",trial
              LET fname = os.Path.join(fgl_getenv("FGLDIR"), fname)
            END IF
          ELSE
            LET fname = os.Path.join(m_gbcdir, fname)
          END IF
          CALL log(SFMT("  fname:%1", fname))
          CALL processFile(req, fname, clitag, gzip, TRUE)
        WHEN url.getIndexOf(priv, 1) == 1 --private images
          LET fname = processURL(url, priv, m_privdir)
          CALL processFile(
              req, fname, clitag, gzip, FALSE) --makes no sense to cache
        WHEN url.getIndexOf(pub, 1) == 1 --public images
          LET fname = processURL(url, pub, m_pubdir)
          CALL processFile(req, fname, clitag, gzip, TRUE) --do cache
        OTHERWISE
          CALL log(SFMT("  404 Not Found:%1", url))
          CALL req.sendTextResponse(404, NULL, SFMT("URL:%1 not found", URL))
      END CASE
    END IF
  END WHILE
  DISPLAY "Finished in :",CURRENT - m_starttime
END MAIN

FUNCTION getIfNoneMatchAndGzip(req com.HTTPServiceRequest)
  DEFINE clitag,val STRING
  DEFINE gzip BOOLEAN
  DEFINE i INT
  LET clitag = NULL
  FOR i = 1 TO req.getRequestHeaderCount()
    IF req.getRequestHeaderName(i) == "If-None-Match" THEN
      LET clitag = req.getRequestHeaderValue(i)
      --CALL log(SFMT("  If-None-Match:%1", clitag))
    END IF
    IF req.getRequestHeaderName(i) == "Accept-Encoding" THEN
      LET val = req.getRequestHeaderValue(i)
      --CALL log(SFMT("  Accept-Encoding:%1", val))
      LET gzip = val.getIndexOf("gzip", 1) <> 0
    END IF
  END FOR
  RETURN clitag,gzip
END FUNCTION

FUNCTION init()
  LET m_verbose=fgl_getenv("VERBOSE") IS NOT NULL
  LET m_GDC = fgl_getenv("GDC")
END FUNCTION

FUNCTION cut_question(fname)
  DEFINE fname STRING
  DEFINE idx INT
  IF (idx := fname.getIndexOf("?", 1)) <> 0 THEN
    RETURN fname.subString(1, idx - 1)
  END IF
  RETURN fname
END FUNCTION

FUNCTION processURL(url, pre, dir)
  DEFINE url, pre, dir, fname STRING
  LET fname = url.subString(pre.getLength() + 1, url.getLength())
  LET fname = cut_question(fname)
  LET fname = os.Path.join(dir, fname)
  CALL log(SFMT("  processURL fname:%1", fname))
  RETURN fname
END FUNCTION

FUNCTION processFile(req, fname, clitag, gzip, cache)
  DEFINE req com.HTTPServiceRequest
  DEFINE fname STRING
  DEFINE clitag STRING
  DEFINE gzip, cache BOOLEAN
  DEFINE ext, ct, etag, gzname STRING
  LET ext = os.Path.extension(fname)
  LET gzname = fname, ".gz"
  IF gzip AND os.Path.exists(gzname) THEN
    --LET fname=gzname
    CALL req.setResponseHeader("Content-Encoding", "gzip")
  ELSE
    IF NOT os.Path.exists(fname) THEN
      CALL log(SFMT("  processFile 404 Not Found:%1", fname))
      CALL req.sendTextResponse(404, NULL, SFMT("File:%1 not found", fname))
      RETURN
    END IF
  END IF
  IF cache THEN
    LET etag = SFMT("%1.%2", os.Path.mtime(fname), os.Path.size(fname))
    IF clitag IS NOT NULL AND clitag == etag THEN
      CALL req.setResponseHeader("ETag", etag)
      CALL req.setResponseHeader("Cache-Control", "max-age=1,public")
      CALL req.sendResponse(304, "Not Modified")
      CALL log(SFMT("  304 Not Modified:%1", fname))
      RETURN
    END IF
  END IF
  LET ct = NULL
  {
  CASE ext
      WHEN "html"
        LET ct = "text/html"
      WHEN "js"
        LET ct = "application/x-javascript"
      WHEN "css"
        LET ct = "text/css"
      WHEN "gif"
        LET ct = "image/gif"
      WHEN "woff"
        LET ct = "application/font-woff"
      WHEN  "ttf"
        LET ct = "application/octet-stream"
  END CASE
  }
  CALL setContentTypeAndCache(req, ct, cache, etag)
  CALL log(SFMT("  200 OK:%1", fname))
  CALL req.setResponseHeader("Content-Disposition","inline")
  CALL req.sendFileResponse(200, NULL, fname)

END FUNCTION

FUNCTION setContentTypeAndCache(req, ct, cache, etag)
  DEFINE req com.HTTPServiceRequest
  DEFINE ct, etag STRING
  DEFINE cache BOOLEAN
  IF ct IS NOT NULL THEN
    CALL req.setResponseHeader("Content-Type", ct)
  END IF
  IF cache THEN
    CALL req.setResponseHeader("Cache-Control", "max-age=1,public")
    --DISPLAY "  send Cache-Control: max-age=1,public and ETag:",etag
    CALL req.setResponseHeader("ETag", etag)
  ELSE
    CALL req.setResponseHeader("Cache-Control", "no-cache")
  END IF
END FUNCTION

FUNCTION readTextFile(fname)
  DEFINE fname, res STRING
  DEFINE t TEXT
  LOCATE t IN FILE fname
  LET res = t
  RETURN res
END FUNCTION

FUNCTION readBlob(fname)
  DEFINE fname STRING
  DEFINE blob BYTE
  LOCATE blob IN FILE fname
  RETURN blob
END FUNCTION

FUNCTION setup_program(priv, pub)
  DEFINE priv, pub STRING
  DEFINE s, prog STRING
  DEFINE vmport INT
  LET m_channel = base.Channel.create()
  LET vmport = findFreeServerPort(8100, 8300, TRUE)
  CALL m_channel.openServerSocket("127.0.0.1", vmport, "u")
  --point FGLSERVER to us
  CALL fgl_setenv("FGLSERVER", SFMT("localhost:%1", vmport - 6400))
  CALL fgl_setenv("FGL_PRIVATE_DIR", m_privdir)
  CALL fgl_setenv("FGL_PUBLIC_DIR", ".")
  CALL fgl_setenv("FGL_PUBLIC_IMAGEPATH", ".")
  CALL fgl_setenv("FGL_PRIVATE_URL_PREFIX", priv)
  CALL fgl_setenv("FGL_PUBLIC_URL_PREFIX", pub)
  LET prog = arg_val(1)
  LET m_progdir = os.Path.fullPath(os.Path.dirname(prog))
  --should work on both Win and Unix
  LET s = "cd ", m_progdir, "&&fglrun ", os.Path.baseName(prog)
  CALL log(SFMT("RUN %1", s))
  RUN s WITHOUT WAITING
  LET m_vmcmd = m_channel.readLine()
  CALL log(SFMT("meta:%1", m_vmcmd))
END FUNCTION



FUNCTION getUAGASURL()
  RETURN SFMT("http://%1:%2/ua/r/_xxx", m_fglproxyhost, m_htport)
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
