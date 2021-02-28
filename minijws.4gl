#+ modified fgljp to process stress test
OPTIONS
SHORT CIRCUIT
&define MYASSERT(x) IF NOT NVL(x,0) THEN CALL myErr("ASSERTION failed in line:"||__LINE__||":"||#x) END IF
--&define MYASSERT_MSG(x,msg) IF NOT NVL(x,0) THEN CALL myErr("ASSERTION failed in line:"||__LINE__||":"||#x||","||msg) END IF
&define UNUSED_VAR(var) INITIALIZE var TO NULL
IMPORT os
IMPORT util
IMPORT FGL utils
IMPORT JAVA com.fourjs.fgl.lang.FglRecord
IMPORT JAVA java.io.File
IMPORT JAVA java.io.FileInputStream
IMPORT JAVA java.io.FileOutputStream
IMPORT JAVA java.io.DataInputStream
IMPORT JAVA java.io.DataOutputStream
IMPORT JAVA java.io.IOException
IMPORT JAVA java.io.InputStream
IMPORT JAVA java.io.InputStreamReader
IMPORT JAVA java.nio.channels.SelectionKey
IMPORT JAVA java.nio.channels.Selector
IMPORT JAVA java.nio.channels.ServerSocketChannel
IMPORT JAVA java.nio.channels.SocketChannel
IMPORT JAVA java.nio.channels.FileChannel
IMPORT JAVA java.nio.channels.Channels
IMPORT JAVA java.nio.file.Files
IMPORT JAVA java.nio.charset.Charset
IMPORT JAVA java.nio.charset.StandardCharsets
IMPORT JAVA java.net.URI
IMPORT JAVA java.net.ServerSocket
IMPORT JAVA java.net.InetSocketAddress
IMPORT JAVA java.util.Set --<SelectionKey>
IMPORT JAVA java.util.HashSet
IMPORT JAVA java.util.Iterator --<SelectionKey>
IMPORT JAVA java.lang.String
IMPORT JAVA java.lang.Object
CONSTANT _keepalive = FALSE

PUBLIC TYPE TStartEntries RECORD
  port INT,
  FGLSERVER STRING,
  pid INT,
  url STRING
END RECORD

TYPE TStringDict DICTIONARY OF STRING
TYPE TStringArr DYNAMIC ARRAY OF STRING
TYPE ByteArray ARRAY[] OF TINYINT

CONSTANT S_INIT = "Init"
CONSTANT S_HEADERS = "Headers"
CONSTANT S_WAITCONTENT = "WaitContent"
CONSTANT S_FINISH = "Finish"

TYPE TSelectionRec RECORD
  chan SocketChannel,
  dIn DataInputStream,
  dOut DataOutputStream,
  id INT,
  state STRING,
  starttime DATETIME HOUR TO FRACTION(1),
  isHTTP BOOLEAN, --HTTP related members
  path STRING,
  method STRING,
  body STRING,
  headers TStringDict,
  contentLen INT,
  clitag STRING
END RECORD

DEFINE _opt_port STRING
DEFINE _verbose BOOLEAN
DEFINE _sel TSelectionRec
DEFINE _selId INT
DEFINE _starttime DATETIME HOUR TO FRACTION(1)
DEFINE _stderr base.Channel

DEFINE _pendingKeys HashSet
DEFINE _htpre STRING
DEFINE _serverkey SelectionKey
DEFINE _server ServerSocketChannel
DEFINE _didAccept BOOLEAN

MAIN
  DEFINE socket ServerSocket
  DEFINE selector Selector
  DEFINE port INT
  DEFINE htpre STRING
  LET _verbose = FALSE
  LET _starttime = CURRENT
  LET _server = ServerSocketChannel.open();
  CALL _server.configureBlocking(FALSE);
  LET socket = _server.socket();
  LET port = 8787
  LABEL bind_again:
  TRY
    CALL socket.bind(InetSocketAddress.create(port));
  CATCH
    CALL log(SFMT("socket.bind:%1", err_get(status)))
    IF _opt_port IS NULL THEN
      LET port = port + 1
      IF port < 9000 THEN
        GOTO bind_again
      END IF
    END IF
  END TRY
  LET port = socket.getLocalPort()
  CALL log(
      SFMT("listening on real port:%1,FGLSERVER:%2",
          port, fgl_getenv("FGLSERVER")))
  LET htpre = SFMT("http://localhost:%1/", port)
  LET _htpre = htpre
  LET selector = java.nio.channels.Selector.open()
  LET _serverkey = _server.register(selector, SelectionKey.OP_ACCEPT);
  LET _pendingKeys = HashSet.create()
  DISPLAY SFMT("%1stress.html", htpre)
  CALL utils.openBrowserWithStress(port)
  WHILE TRUE
    CALL processKeys("_pendingKeys:", _pendingKeys, selector)
    CALL _pendingKeys.clear()
    --CALL printKeys("before select(),registered keys:",selector.keys())
    CALL selector.select();
    CALL processKeys("selectedKeys():", selector.selectedKeys(), selector)
  END WHILE
END MAIN

FUNCTION processKeys(what STRING, inkeys Set, selector Selector)
  DEFINE keys Set
  DEFINE key SelectionKey
  DEFINE it Iterator
  UNUSED_VAR(what)
  IF inkeys.size() == 0 THEN
    RETURN
  END IF
  LET keys = HashSet.create(inkeys)
  --CALL printKeys(what, keys)
  LET it = keys.iterator()
  WHILE it.hasNext()
    LET key = CAST(it.next() AS SelectionKey);
    IF key.equals(_serverkey) THEN --accept a new connection
      MYASSERT(key.attachment() IS NULL)
      LET _didAccept = TRUE
      CALL acceptNew(_server, selector)
    ELSE
      CALL handleConnection(key, selector)
    END IF
  END WHILE
END FUNCTION

FUNCTION printSel(sel TSelectionRec)
  DEFINE diff INTERVAL MINUTE TO FRACTION(1)
  IF NOT _verbose THEN
    RETURN ""
  END IF
  LET diff = CURRENT - sel.starttime
  CASE
    WHEN sel.isHTTP
      RETURN SFMT("{HTTP id:%1 s:%2 p:%3 t:%4}",
          sel.id, sel.state, sel.path, diff)
    OTHERWISE
      RETURN SFMT("{_ id:%1 s:%2 t:%3}", sel.id, sel.state, diff)
  END CASE
END FUNCTION

FUNCTION printKey(key SelectionKey)
  DEFINE sel TSelectionRec
  IF key.equals(_serverkey) THEN
    RETURN "{serverkey}"
  ELSE
    LET sel = CAST(key.attachment() AS TSelectionRec)
    RETURN printSel(sel.*)
  END IF
END FUNCTION

FUNCTION printKeys(what STRING, keys Set)
  DEFINE it Iterator
  DEFINE o STRING
  DEFINE key SelectionKey
  LET it = keys.iterator()
  WHILE it.hasNext()
    LET key = CAST(it.next() AS SelectionKey);
    LET o = o, " ", printKey(key)
  END WHILE
  DISPLAY what, o
END FUNCTION

PRIVATE FUNCTION myErr(errstr STRING)
  DEFINE ch base.Channel
  LET ch = base.Channel.create()
  CALL ch.openFile("<stderr>", "w")
  CALL ch.writeLine(
      SFMT("ERROR:%1 stack:\n%2", errstr, base.Application.getStackTrace()))
  CALL ch.close()
  EXIT PROGRAM 1
END FUNCTION

FUNCTION acceptNew(server, selector)
  DEFINE server ServerSocketChannel
  DEFINE selector Selector
  DEFINE chan SocketChannel
  DEFINE clientkey SelectionKey
  DEFINE ins InputStream
  DEFINE dIn DataInputStream
  DEFINE sel TSelectionRec
  LET chan = server.accept()
  IF chan IS NULL THEN
    CALL log("acceptNew: chan is NULL")
    RETURN
  END IF
  LET ins = chan.socket().getInputStream()
  LET dIn = DataInputStream.create(ins);
  CALL chan.configureBlocking(FALSE);
  LET clientkey = chan.register(selector, SelectionKey.OP_READ);
  LET sel.state = S_INIT
  LET sel.chan = chan
  LET _selId = _selId + 1
  LET sel.id = _selId
  LET sel.dIn = dIn
  LET sel.starttime = CURRENT
  CALL clientkey.attach(sel)
END FUNCTION

FUNCTION removeCR(s STRING)
  IF s.getCharAt(s.getLength()) == '\r' THEN
    LET s = s.subString(1, s.getLength() - 1)
  END IF
  RETURN s
END FUNCTION

FUNCTION splitHTTPLine(s)
  DEFINE a DYNAMIC ARRAY OF STRING
  DEFINE s STRING
  DEFINE t base.StringTokenizer
  LET t = base.StringTokenizer.create(s, ' ')
  LET a[1] = t.nextToken()
  LET a[2] = t.nextToken()
  LET a[3] = t.nextToken()
  RETURN a
END FUNCTION

FUNCTION parseHttpLine(s STRING)
  DEFINE a DYNAMIC ARRAY OF STRING
  LET s = removeCR(s)
  LET a = splitHTTPLine(s)
  LET _sel.method = a[1]
  LET _sel.path = a[2]
  CALL log(SFMT("parseHttpLine:%1 %2", s, printSel(_sel.*)))
  IF a[3] <> "HTTP/1.1" THEN
    CALL myErr(SFMT("'%1' must be HTTP/1.1", a[3]))
  END IF
END FUNCTION

FUNCTION parseHttpHeader(s STRING)
  DEFINE cIdx INT
  DEFINE key, val STRING
  LET s = removeCR(s)
  LET cIdx = s.getIndexOf(":", 1)
  MYASSERT(cIdx > 0)
  LET key = s.subString(1, cIdx - 1)
  LET key = key.toLowerCase()
  LET val = s.subString(cIdx + 2, s.getLength())
  --DISPLAY "key:",key,",val:'",val,"'"
  CASE key
    WHEN "content-length"
      LET _sel.contentLen = val
      --DISPLAY "Content-Length:", _sel.contentLen
    WHEN "if-none-match"
      LET _sel.clitag = val
      --DISPLAY "If-None-Match", _sel.clitag
  END CASE
  LET _sel.headers[key] = val
END FUNCTION

FUNCTION getCacheHeaders(cache BOOLEAN, etag STRING)
  DEFINE hdrs DYNAMIC ARRAY OF STRING
  IF cache THEN
    LET hdrs[hdrs.getLength() + 1] = "Cache-Control: max-age=1,public"
    LET hdrs[hdrs.getLength() + 1] = SFMT("ETag: %1", etag)
  ELSE
    LET hdrs[hdrs.getLength() + 1] = "Cache-Control: no-cache"
    LET hdrs[hdrs.getLength() + 1] = "Pragma: no-cache"
    LET hdrs[hdrs.getLength() + 1] = "Expires: -1"
  END IF
  RETURN hdrs
END FUNCTION

FUNCTION sendNotModified(fname STRING, etag STRING)
  DEFINE hdrs DYNAMIC ARRAY OF STRING
  LET hdrs[hdrs.getLength() + 1] = "Cache-Control: max-age=1,public"
  LET hdrs[hdrs.getLength() + 1] = SFMT("ETag: %1", etag)
  CALL log(SFMT("sendNotModified:%1", fname))
  CALL writeResponseInt2(
      "", "text/plain; charset=UTF-8", hdrs, "304 Not Modified")
END FUNCTION

FUNCTION httpHandler()
  DEFINE text, path STRING
  LET path = _sel.path
  CALL log(SFMT("httpHandler '%1' for:%2", path, printSel(_sel.*)))
  CASE
    WHEN path == "/"
      DISPLAY "send root"
      LET text = "<!DOCTYPE html><html><body>Hello root</body></html>"
      CALL writeResponse(text)
    WHEN path == "/exit"
      CALL writeResponseCt("Exit seen", "text/plain")
      DISPLAY "Finished in :", CURRENT - _starttime
      EXIT PROGRAM
    OTHERWISE
      IF NOT findFile(path) THEN
        CALL http404(path)
      END IF
  END CASE
END FUNCTION

FUNCTION findFile(path STRING)
  DEFINE qidx INT
  LET qidx = path.getIndexOf("?", 1)
  IF qidx > 0 THEN
    LET path = path.subString(1, qidx - 1)
  END IF
  LET path = ".", path
  IF NOT os.Path.exists(path) THEN
    CALL log(SFMT("findFile:'%1' doesn't exist", path))
    RETURN FALSE
  END IF
  CALL processFile(path, TRUE)
  RETURN TRUE
END FUNCTION

FUNCTION readTextFile(fname)
  DEFINE fname, res STRING
  DEFINE t TEXT
  LOCATE t IN FILE fname
  LET res = t
  RETURN res
END FUNCTION

FUNCTION processFile(fname STRING, cache BOOLEAN)
  DEFINE ext, ct, txt STRING
  DEFINE etag STRING
  DEFINE hdrs TStringArr
  IF NOT os.Path.exists(fname) THEN
    CALL http404(fname)
    RETURN
  END IF
  --DISPLAY "processFile:",fname
  IF cache THEN
    LET etag = SFMT("%1.%2", os.Path.mtime(fname), os.Path.size(fname))
    IF _sel.clitag IS NOT NULL AND _sel.clitag == etag THEN
      CALL sendNotModified(fname, etag)
      RETURN
    END IF
  END IF
  LET ext = os.Path.extension(fname)
  LET ct = NULL
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
      LET txt = readTextFile(fname)
      LET hdrs = getCacheHeaders(cache, etag)
      CALL writeResponseCtHdrs(txt, ct, hdrs)
    OTHERWISE
      CASE
        WHEN ext == "gif"
          LET ct = "image/gif"
        WHEN ext == "woff"
          LET ct = "application/font-woff"
        WHEN ext == "ttf"
          LET ct = "application/octet-stream"
      END CASE
      LET hdrs = getCacheHeaders(cache, etag)
      CALL writeResponseFileHdrs(fname, ct, hdrs)
  END CASE
END FUNCTION

FUNCTION http404(fn STRING)
  DEFINE content STRING
  LET content =
      SFMT("<!DOCTYPE html><html><body>Can't find: '%1'</body></html>", fn)
  CALL log(SFMT("http404:%1", fn))
  CALL writeResponseInt(content, "text/html", "404 Not Found")
END FUNCTION

FUNCTION createDout(chan SocketChannel)
  DEFINE dOut DataOutputStream
  LET dOut = DataOutputStream.create(chan.socket().getOutputStream())
  RETURN dOut
END FUNCTION

FUNCTION writeHTTPLine(s STRING)
  --DEFINE js java.lang.String
  LET s = s, "\r\n"
  CALL writeHTTP(s)
  --DISPLAY "did write:'", s, "'"
END FUNCTION

FUNCTION writeHTTP(s STRING)
  DEFINE js java.lang.String
  LET js = s
  --CALL _sel.dOut.writeBytes(js.getBytes())
  IF s IS NULL THEN
    RETURN
  END IF
  --MYASSERT(s IS NOT NULL)
  LET _sel.dOut = IIF(_sel.dOut IS NOT NULL, _sel.dOut, createDout(_sel.chan))
  MYASSERT(_sel.dOut IS NOT NULL)
  CALL _sel.dOut.write(js.getBytes(StandardCharsets.UTF_8))
END FUNCTION

FUNCTION writeHTTPFile(fn STRING)
  DEFINE f java.io.File
  LET f = File.create(fn)
  LET _sel.dOut = IIF(_sel.dOut IS NOT NULL, _sel.dOut, createDout(_sel.chan))
  CALL _sel.dOut.write(Files.readAllBytes(f.toPath()))
END FUNCTION

FUNCTION writeResponse(content STRING)
  CALL writeResponseInt(content, "text/html; charset=UTF-8", "200 OK")
END FUNCTION

FUNCTION writeResponseCtHdrs(
    content STRING, ct STRING, headers DYNAMIC ARRAY OF STRING)
  CALL writeResponseInt2(content, ct, headers, "200 OK")
END FUNCTION

FUNCTION writeResponseCt(content STRING, ct STRING)
  CALL writeResponseInt(content, ct, "200 OK")
END FUNCTION

FUNCTION writeHTTPCommon()
  DEFINE h STRING
  LET h = "Date: ", TODAY USING "DDD, DD MMM YYY", " ", TIME, " GMT"
  CALL writeHTTPLine(h)
  CALL writeHTTPLine(
      IIF(_keepalive, "Connection: keep-alive", "Connection: close"))
END FUNCTION

FUNCTION writeResponseInt(content STRING, ct STRING, code STRING)
  DEFINE headers DYNAMIC ARRAY OF STRING
  CALL writeResponseInt2(content, ct, headers, code)
END FUNCTION

FUNCTION writeHTTPHeaders(headers TStringArr)
  DEFINE i, len INT
  LET len = headers.getLength()
  FOR i = 1 TO len
    CALL writeHTTPLine(headers[i])
  END FOR
END FUNCTION

FUNCTION writeResponseInt2(
    content STRING, ct STRING, headers DYNAMIC ARRAY OF STRING, code STRING)
  DEFINE content_length INT

  CALL writeHTTPLine(SFMT("HTTP/1.1 %1", code))
  CALL writeHTTPCommon()

  LET content_length = content.getLength()
  CALL writeHTTPHeaders(headers)
  IF content_length > 0 THEN
    CALL writeHTTPLine(SFMT("Content-Length: %1", content_length))
    --CALL writeHTTPLine("Content-Type: text/html; charset=UTF-8")
    CALL writeHTTPLine(SFMT("Content-Type: %1", ct))
  END IF
  CALL writeHTTPLine("")
  CALL writeHTTP(content)
END FUNCTION

FUNCTION writeResponseFileHdrs(fn STRING, ct STRING, headers TStringArr)
  IF NOT os.Path.exists(fn) THEN
    CALL http404(fn)
    RETURN
  END IF

  CALL writeHTTPLine("HTTP/1.1 200 OK")
  CALL writeHTTPCommon()

  CALL writeHTTPHeaders(headers)
  CALL writeHTTPLine(SFMT("Content-Length: %1", os.Path.size(fn)))
  CALL writeHTTPLine(SFMT("Content-Type: %1", ct))
  CALL writeHTTPLine("")
  CALL writeHTTPFile(fn)
END FUNCTION

FUNCTION handleConnection(key SelectionKey, selector Selector)
  DEFINE chan SocketChannel
  DEFINE readable BOOLEAN
  DEFINE sel TSelectionRec
  TRY
    LET readable = key.isReadable()
  CATCH
    LET sel = CAST(key.attachment() AS TSelectionRec)
    DISPLAY "handleConnection:", printSel(sel.*), ",err:",err_get(status)
    MYASSERT(false)
  END TRY
  IF NOT readable THEN
    CALL warning("handleConnection: NOT key.isReadable()")
    RETURN
  END IF
  LET chan = CAST(key.channel() AS SocketChannel)
  MYASSERT(key.attachment() INSTANCEOF FglRecord)
  LET _sel = CAST(key.attachment() AS TSelectionRec)
  CALL handleConnectionInt(key, chan, selector)
END FUNCTION

FUNCTION reRegister(chan SocketChannel, selector Selector)
  DEFINE newkey SelectionKey
  --DEFINE key SelectionKey
  --DEFINE o java.lang.Object
  --DEFINE it Iterator
  DEFINE numKeys INT
  --DISPLAY "re register:", printSel(_sel.*)
  --re register the channel again
  CALL chan.configureBlocking(FALSE)
  LET numKeys = selector.selectNow()
  {
  IF numKeys > 0 THEN
    DISPLAY "  selectNow:",numKeys
    LET it = selector.selectedKeys().iterator()
    WHILE it.hasNext()
      LET o = it.next()
      LET key = CAST(o AS SelectionKey);
      IF NOT _pendingKeys.contains(key) THEN
        CALL log(SFMT("reRegister:add to PendingKeys:%1", printKey(key)))
        CALL _pendingKeys.add(o)
      END IF
    END WHILE
  END IF
  }
  LET newkey = chan.register(selector, SelectionKey.OP_READ);
  CALL newkey.attach(_sel)
END FUNCTION

FUNCTION handleConnectionInt(
    key SelectionKey, chan SocketChannel, selector Selector)
  DEFINE dIn DataInputStream
  DEFINE line STRING
  DEFINE bytearr ByteArray
  DEFINE jstring java.lang.String
  CALL log(sfmt("handleConnectionInt:%1",printSel(_sel.*)))
  LET dIn = _sel.dIn
  CALL key.interestOps(0)
  CALL key.cancel()
  CALL chan.configureBlocking(TRUE)
  WHILE TRUE
    IF _sel.isHTTP AND _sel.state == S_WAITCONTENT THEN
      CALL log(SFMT("S_WAITCONTENT of :%1", _sel.path))
      LET bytearr = ByteArray.create(_sel.contentLen)
      CALL dIn.read(bytearr)
      LET jstring = java.lang.String.create(bytearr, StandardCharsets.UTF_8)
      LET _sel.body = jstring
      LET _sel.state = S_FINISH
      CALL httpHandler()
      EXIT WHILE
    END IF
    TRY
      LET line = dIn.readLine()
    CATCH
      CALL log(SFMT("readLine error:%1", err_get(status)))
      CALL chan.close()
      RETURN
    END TRY
    --DISPLAY "line:",limitPrintStr(line)
    IF line.getLength() == 0 THEN
      MYASSERT(_sel.isHTTP AND _sel.state == S_HEADERS)
      IF _sel.contentLen > 0 THEN
        LET _sel.state = S_WAITCONTENT
        EXIT WHILE
      ELSE
        --DISPLAY "Finish of :", _sel.path
        LET _sel.state = S_FINISH
        CALL httpHandler()
        EXIT WHILE
      END IF
    END IF
    CASE
      WHEN NOT _sel.isHTTP
        CASE
          WHEN line.getIndexOf("GET ", 1) == 1
              OR line.getIndexOf("PUT ", 1) == 1
              OR line.getIndexOf("POST ", 1) == 1
              OR line.getIndexOf("HEAD ", 1) == 1
            CALL parseHttpLine(line)
            LET _sel.isHTTP = TRUE
            LET _sel.state = S_HEADERS
          OTHERWISE
            CALL myErr(SFMT("Unexpected connection handshake:%1", line))
        END CASE
      WHEN _sel.isHTTP
        CASE _sel.state
          WHEN S_HEADERS
            CALL parseHttpHeader(line)
        END CASE
    END CASE
  END WHILE
  CALL checkReRegister(chan, selector)
END FUNCTION

FUNCTION checkReRegister(chan SocketChannel, selector Selector)
  DEFINE newChan BOOLEAN
  IF (_sel.state <> S_FINISH)
      OR (newChan := (_keepalive AND _sel.state == S_FINISH AND _sel.isHTTP))
          == TRUE THEN
    IF newChan THEN
      --DISPLAY "re register id:", _sel.id,",available:", _sel.dIn.available()
      LET _sel.starttime = CURRENT
      LET _sel.state = S_INIT
      LET _sel.isHTTP = FALSE
      LET _sel.method = ""
      LET _sel.path = ""
      LET _sel.clitag = NULL
      LET _sel.body = NULL
      CALL _sel.headers.clear()
      LET _sel.contentLen = 0
    END IF
    CALL reRegister(chan, selector)
  END IF
END FUNCTION

FUNCTION createOutputStream(fn STRING) RETURNS FileChannel
  DEFINE f java.io.File
  DEFINE fc FileChannel
  LET f = File.create(fn)
  TRY
    LET fc = FileOutputStream.create(f, FALSE).getChannel()
    CALL log(
        SFMT("createOutputStream:did create file output stream for:%1", fn))
  CATCH
    CALL warning(SFMT("createOutputStream:%1", err_get(status)))
    RETURN NULL
  END TRY
  RETURN fc
END FUNCTION

FUNCTION createInputStream(fn STRING) RETURNS FileChannel
  DEFINE readC FileChannel
  TRY
    LET readC = FileInputStream.create(fn).getChannel()
    --DISPLAY "createInputStream: did create file input stream for:", fn
  CATCH
    CALL warning(SFMT("createInputStream:%1", err_get(status)))
  END TRY
  RETURN readC
END FUNCTION

FUNCTION getLastModified(fn STRING)
  DEFINE m INT
  LET m = util.Datetime.toSecondsSinceEpoch(os.Path.mtime(fn))
  RETURN m
END FUNCTION

FUNCTION limitPrintStr(s STRING)
  DEFINE len INT
  LET len = s.getLength()
  IF len > 323 THEN
    RETURN s.subString(1, 160) || "..." || s.subString(len - 160, len)
  ELSE
    RETURN s
  END IF
END FUNCTION

FUNCTION writeToLog(s STRING)
  DEFINE diff INTERVAL MINUTE TO FRACTION(1)
  DEFINE chan base.Channel
  LET diff = CURRENT - _starttime
  CALL checkStderr()
  LET chan = _stderr
  CALL chan.writeNoNL(diff)
  CALL chan.writeNoNL(" ")
  CALL chan.writeLine(s)
END FUNCTION

FUNCTION checkStderr()
  IF _stderr IS NULL THEN
    LET _stderr = base.Channel.create()
    CALL _stderr.openFile("<stderr>", "w")
  END IF
END FUNCTION

FUNCTION log(s STRING)
  IF NOT _verbose THEN
    RETURN
  END IF
  CALL writeToLog(s)
END FUNCTION

FUNCTION warning(s STRING)
  DISPLAY "!!!!!!!!WARNING:", s
END FUNCTION
