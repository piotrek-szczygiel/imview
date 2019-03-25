NAME := imview
OUT  := $(NAME).exe

$(OUT): $(NAME).asm
	fasm $(NAME).asm

clean:
	rm $(OUT)

test: $(OUT)
	dosbox "$(OUT)"

debug: $(OUT)
	dosbox -c "mount c ." -c "d:\td.exe c:\$(OUT)"
