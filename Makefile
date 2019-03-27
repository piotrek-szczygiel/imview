NAME := imview
OUT  := $(NAME).exe

$(OUT): $(NAME).asm
	fasm $(NAME).asm

clean:
	rm $(OUT)

test: $(OUT)
	dosbox -c "mount c ." -c "c:" -c "$(OUT) images\rocket.bmp"

debug: $(OUT)
	dosbox -c "mount c ." -c "c:" -c "d:\td.exe $(OUT) images\rocket.bmp"

dosbox: $(OUT)
	dosbox .
