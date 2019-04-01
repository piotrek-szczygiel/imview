NAME := imview
OUT  := $(NAME).exe
IMG  := images\t256_1~1.bmp

$(OUT): $(NAME).asm
	fasm $(NAME).asm

clean:
	rm -f $(OUT)

test: $(OUT)
	dosbox -c "mount c ." -c "c:" -c "$(OUT) $(IMG)"

debug: $(OUT)
	dosbox -c "mount c ." -c "c:" -c "d:\td.exe $(OUT) $(IMG)"
