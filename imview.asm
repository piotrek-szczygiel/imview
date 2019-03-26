; vim: syntax=fasm
; Simple calculator
; Piotr Szczygieł - Assemblery 2019
format MZ                                   ; DOS MZ executable
entry main:start                            ; specify an application entry point

segment main
start:
    mov ax, word stack1                     ; point stack segment address
    mov ss, ax
    mov sp, word stack1_tail

    call argument_read

    mov ax, word text1                      ; point data segment address
    mov ds, ax

    mov ax, word 0xa000                     ; point VGA memory address
    mov es, ax

    call mode_vga
    call file_open

    call bmp_prepare
    call bmp_palette

    mov ax, word [bmp.height]
    mov [esp], word ax
    .loop:
        dec word [esp]

        mov cx, word [bmp.width]
        mov dx, word bmp.row
        call file_read

        mov cx, word [bmp.width]
        mov si, word bmp.row

        mov ax, word [esp]
        mov bx, word 320
        mul bx

        mov di, ax
        rep movsb

        mov ax, [esp]
        cmp ax, word 0
        ja .loop

    call read_char
    call file_close
    call mode_text

    mov al, byte 0
    jmp exit

; Print error and exit
;   DS:DX - error string
error:
    call mode_text                          ; switch back to text mode
    call print

; Terminate the program
;   AL - exit code
exit:
    mov ah, 0x4c                            ; terminates the program by
    int 0x21                                ; invoking DOS interruption


bmp_palette:
    mov cx, word 256
    .loop1:
        push cx
        mov cx, word 4
        mov dx, word palette.quad
        call file_read

        mov dx, 0x03c9
        mov al, byte [palette.r]
        shr al, 2
        out dx, al
        mov al, byte [palette.g]
        shr al, 2
        out dx, al
        mov al, byte [palette.b]
        shr al, 2
        out dx, al

        pop cx
        loop .loop1

    ret

bmp_prepare:
    mov cx, word 2
    mov dx, word bmp.header
    call file_read

    mov dx, word str_error_bmp_header
    cmp [bmp.header], byte "B"
    jne error
    cmp [bmp.header + 1], byte "M"
    jne error

    mov al, byte 1
    xor cx, cx
    mov dx, word 16
    call file_seek

    mov cx, word 2
    mov dx, word bmp.width
    call file_read

    mov al, byte 1
    xor cx, cx
    mov dx, word 2
    call file_seek

    mov cx, word 2
    mov dx, word bmp.height
    call file_read

    mov al, byte 1
    xor cx, cx
    mov dx, word 22
    call file_seek

    mov cx, word 2
    mov dx, word bmp.num_colors
    call file_read

    mov al, byte 1
    xor cx, cx
    mov dx, word 6
    call file_seek

    mov dx, 0x03c8
    mov al, 0
    out dx, al

    ret

; Print string on standard output with newline
;   DS:DX - string
print:
    mov ah, 0x09
    int 0x21
    mov dx, word str_crlf
    int 0x21
    ret

; Copy filename provided in argument to our filename address
argument_read:
    mov ax, word text1
    mov es, ax

    mov si, 0x82                            ; offset to first letter of arguments
    mov di, file.name

    xor ch, ch
    mov cl, byte [0x80]
    dec cl

    cld

    rep movsb
    mov [di], byte 0xab
    ret

; Read from file
;   CX - number of bytes to read
;   DS:DX - buffer for data
file_read:
    mov ah, 0x3f
    mov bx, word [file.handle]
    int 0x21
    mov dx, word str_error_file_read
    jc error
    ret

; Set current file position
;   AL: 0 - start
;       1 - current
;       2 - end
;   CX:DX - offset
file_seek:
    mov ah, 0x42
    mov bx, word [file.handle]
    int 0x21
    mov dx, word str_error_file_seek
    jc error
    ret

; Open the file
file_open:
    xor al, al
    mov ah, 0x3d
    mov dx, word file.name
    int 0x21
    mov dx, word str_error_file_open
    jc error
    mov [file.handle], word ax
    ret

; Close the file
file_close:
    mov bx, word [file.handle]
    mov ah, 0x3e
    int 0x21
    mov dx, word str_error_file_close
    jc error
    ret

; Switch video mode to VGA 320x200, 256 colors
mode_vga:
    mov ax, 0x0013
    int 0x10
    ret

; Switch video mode to text
mode_text:
    mov ax, 0x0003
    int 0x10
    ret

; Read character from standard input
;
; return:
;   AL - character read
read_char:
    mov ah, 0x08
    int 0x21
    ret

segment text1
str_crlf                db 13, 10, "$"

str_error_file_open     db "Unable to open the file!$"
str_error_file_close    db "Unable to close the file!$"
str_error_file_seek     db "Error while seeking the file!$"
str_error_file_read     db "Error while reading from file!$"

str_error_bmp_header    db "Invalid BMP header!$"

file.name               db 128 dup 0
file.handle             rw 1

bmp.header              rb 2
bmp.width               rw 1
bmp.height              rw 1
bmp.num_colors          rw 1
bmp.row                 rb 2048

palette.quad:
palette.b               rb 1
palette.g               rb 1
palette.r               rb 1
palette.padding         rb 1

; 128 bytes stack
segment stack1
stack1_head:    rb 126
stack1_tail:    rb 2