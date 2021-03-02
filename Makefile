ifdef windir
WINDIR=$(windir)
endif

%.42f: %.per 
	fglform -M $<

%.42m: %.4gl 
	fglcomp -Wall -r -M $*


MODS=$(patsubst %.4gl,%.42m,$(wildcard *.4gl))
FORMS=$(patsubst %.per,%.42f,$(wildcard *.per))

all:: $(MODS) $(FORMS)

perf: all
	BROWSER=default fglrun -p fglproxy simpleform

miniws.42m: fglproxy.42m

fgl_http_server.42m: fglproxy.42m

genstress: genstress.42m miniws.42m endStress.js
	fglrun genstress
	fglrun miniws

genstressf: genstress.42m fgl_http_server.42m endStress.js
	fglrun genstress
	fglrun fgl_http_server

genstressj: genstress.42m minijws.42m endStress.js
	fglrun genstress
	fglrun minijws

fglwebrun:
	git clone https://github.com/FourjsGenero/tool_fglwebrun.git fglwebrun

fc1000: fc1000.42m fglwebrun
ifdef WINDIR
	set GDC=1&&fglwebrun\fglwebrun fc1000
else
	GDC=1 fglwebrun/fglwebrun fc1000
endif

clean:
	rm -rf *.42? FontAwesome.ttf stress*.js stress.html priv
