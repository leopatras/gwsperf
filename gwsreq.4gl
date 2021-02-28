OPTIONS
SHORT CIRCUIT
&define MYASSERT(x) IF NOT NVL(x,0) THEN CALL myErr("ASSERTION failed in line:"||__LINE__||":"||#x) END IF
IMPORT com
IMPORT os
IMPORT FGL utils
IMPORT FGL fglproxy
--DEFINE m_starttime DATETIME HOUR TO FRACTION(1)

MAIN
  DEFINE url,base STRING
  DEFINE i,num INT
  MYASSERT(arg_val(1) IS NOT NULL)
  --MYASSERT(arg_val(2) IS NOT NULL)
  LET url=arg_val(1)
  LET num=arg_val(2)
  LET num=IIF(num IS NULL,1,num)
  CALL req(url)
  LET base =os.Path.dirName(url)
  FOR i=1 TO num
    LET url=base,sfmt("/stress%1.js",i)
    CALL req(url)
  END FOR
  LET url=base,"/exit"
  CALL req(url)
END MAIN

FUNCTION req(url STRING)
  DEFINE req com.HTTPRequest
  DEFINE resp com.HTTPResponse
  DEFINE txt STRING
  --DISPLAY "url:'",url,"'"
  LET req = com.HTTPRequest.Create(url)
  CALL req.doRequest()
  LET resp = req.getResponse()
  MYASSERT( resp.getStatusCode() == 200 )
  LET txt=resp.getTextResponse()
  --DISPLAY "HTTP Response is : ",txt
END FUNCTION
