# Makefile — build the workshop slides (Beamer + metropolis, XeLaTeX).
#
#   make            build slides.pdf
#   make watch      rebuild automatically on every save
#   make clean      remove LaTeX aux files (keeps the PDF)
#   make distclean  remove aux files AND the PDF
#
# latexmk reruns XeLaTeX as many times as needed to converge the table of
# contents / cross-references, so we never have to count passes by hand.

MAIN    := slides
ENGINE  := xelatex
LATEXMK := latexmk -$(ENGINE) -interaction=nonstopmode -halt-on-error -file-line-error

.PHONY: all watch clean distclean

all: $(MAIN).pdf

$(MAIN).pdf: $(MAIN).tex
	$(LATEXMK) $(MAIN).tex

watch:
	$(LATEXMK) -pvc $(MAIN).tex

clean:
	latexmk -c $(MAIN).tex
	rm -f $(MAIN).nav $(MAIN).snm $(MAIN).vrb

distclean:
	latexmk -C $(MAIN).tex
	rm -f $(MAIN).nav $(MAIN).snm $(MAIN).vrb
