NAME := imview
OUT  := $(NAME).exe

$(OUT): $(NAME).asm
	fasm $(NAME).asm

clean:
	rm -f $(OUT)

test: $(OUT)
	dosbox -c "mount c ." -c "c:" -c "$(OUT) images\testo256.bmp"

debug: $(OUT)
	dosbox -c "mount c ." -c "c:" -c "d:\td.exe $(OUT) images\testo256.bmp"

dosbox: $(OUT)
	dosbox .
