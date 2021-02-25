function endStress(x) {
  if (x != cnt) {
    alert("error x:"+x+"<>"+cnt);
    return
  }
  //alert("ok");
  sendAjax("/exit");
}

function mylog(msg) {
  console.log(msg);
}
 

function createXmlHttp(){
  if( typeof XMLHttpRequest == "undefined" ) XMLHttpRequest = function() {
    try { return new ActiveXObject("Msxml2.XMLHTTP.6.0") } catch(e) {}
    try { return new ActiveXObject("Msxml2.XMLHTTP.3.0") } catch(e) {}
    try { return new ActiveXObject("Msxml2.XMLHTTP") } catch(e) {}
    try { return new ActiveXObject("Microsoft.XMLHTTP") } catch(e) {}
    alert( "This browser does not support XMLHttpRequest." );
  };
  return new XMLHttpRequest();
}

function getUrlBase(qaport) {
  var l=window.location;
  var p=l.pathname;
  var base=p.substring(0,p.lastIndexOf('/',p.length));
  //hack for fglmux
  //base="";
  var baseurl=l.protocol+"//"+l.host+base;
  return baseurl;
}

function getAJAXAnswer( req ) {
  mylog("getAJAXAnswer readyState:"+req.readyState+",status:"+req.status);
  if (req.readyState != 4 ) {return;}
  if (req.status != 200) {
    mylog("AJAX status:"+req.status);
    return;
  }
  var currtime=new Date().getTime();
  var diff = (currtime-starttime);
  mylog("getAjaxAnswer status 200, time:"+diff);
  document.body.innerHTML="The Application ended with:"+req.responseText+ ",cnt="+cnt+",time diff:" + diff + " ms";
}

function sendAjax(cmd) {
  var req=createXmlHttp();
  var url=getUrlBase()+cmd;
  //alert(url);
  req.open("GET",url,true);
  req.setRequestHeader("Content-type","text/plain");
  req.setRequestHeader("Pragma","no-cache");
  req.setRequestHeader("Cache-Control","no-store, no-cache, must-revalidate");
  req.onreadystatechange = function () { getAJAXAnswer( req ) };
  req.send(cmd);
}
