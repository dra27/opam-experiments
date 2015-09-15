#Temporary makefile

PACKAGES=extlib,curl,sha.sha512
FLAGS=-g

PACKAGES_SWITCH:=
FLAGS_SWITCH:=
ifneq ($(PACKAGES),)
	PACKAGES_SWITCH+= -package $(PACKAGES)
endif
ifneq ($(FLAGS),)
	FLAGS_SWITCH+= $(FLAGS)
endif

all: test.exe

test.exe: CygLexer.cmx CygParser.cmx CygRepository.cmx Test.cmx
	ocamlfind ocamlopt$(PACKAGES_SWITCH)$(FLAGS_SWITCH) -linkpkg -o $@ $^

include .depend

.depend: *.ml *.mli CygLexer.ml CygParser.ml
	ocamldep *.ml *.mli > .depend

%.cmi: %.mli
	ocamlfind ocamlopt$(PACKAGES_SWITCH)$(FLAGS_SWITCH) -c $*.mli

%.cmx: %.ml
	ocamlfind ocamlopt$(PACKAGES_SWITCH)$(FLAGS_SWITCH) -c $*.ml -bin-annot

%.cmo: %.ml
	ocamlfind ocamlc$(PACKAGES_SWITCH)$(FLAGS_SWITCH) -c $*.ml -bin-annot

%.cmx %.cmi: %.ml
	ocamlfind ocamlopt$(PACKAGES_SWITCH)$(FLAGS_SWITCH) -c $*.ml -bin-annot

%.ml %.mli: %.mly
	ocamlyacc $*.mly

%.ml: %.mll
	ocamllex $*.mll

%.cmxs: %.cmx
	ocamlfind ocamlopt$(PACKAGES_SWITCH)$(FLAGS_SWITCH) -shared -o $*.cmxs $*.cmx
