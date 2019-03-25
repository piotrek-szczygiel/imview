imview.exe: imview.asm
	fasm imview.asm

clean:
	rm imview.exe

test: imview.exe
	dosbox imview.exe

debug: calc.exe
	dosbox .
