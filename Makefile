
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

clean:
	rm -rf *.42? FontAwesome.ttf stress*.js stress.html priv
