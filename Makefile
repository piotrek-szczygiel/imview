NAME := imview
OUT  := $(NAME).exe

$(OUT): $(NAME).asm
	fasm $(NAME).asm

clean:
	rm $(OUT)

test: $(OUT)
	dosbox -c "mount c ." -c "c:" -c "$(OUT) images\test.bmp"

debug: $(OUT)
	dosbox -c "mount c ." -c "c:" -c "d:\td.exe $(OUT) images\test.bmp"

dosbox: $(OUT)
	dosbox .
