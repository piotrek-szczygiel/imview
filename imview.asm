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
    call bmp_read

    .main_loop:
        call bmp_draw
        call handle_keyboard
        jmp .main_loop

error:
    call mode_text
    call print

exit:
    call file_close
    call mode_text

    mov al, byte 0
    mov ah, 0x4c
    int 0x21

bmp_draw:
    mov cx, word [bmp.data_offset]
    call file_set_pos

    mov di, word 0      ; offset in VGA memory

    mov ax, word [bmp.height]
    cmp ax, word 200
    jbe .after_row_offset
    sub ax, word 200
    sub ax, word [cursor.y]
    mov dx, word [bmp.width]
    mul dx
    mov cx, dx
    mov dx, ax
    call file_skip_far
    .after_row_offset:

    mov ax, word [min_height]
    mov [i], word ax
    .for_each_row:
        dec word [i]

        cmp [bmp.width], word 320
        jbe .after_cursor_x_offset
        mov cx, word [cursor.x]
        call file_skip
        .after_cursor_x_offset:

        mov ax, word [i]
        mov dx, ax
        shl ax, 8
        shl dx, 6
        add ax, dx
        mov di, ax

        mov ax, word [min_width]
        mov [j], word ax
        .for_each_cell:
            dec word [j]

            mov cx, word 1
            mov dx, word char
            call file_read

            mov al, byte [char]
            mov [es:di], byte al
            inc di

            cmp [j], word 0
            ja .for_each_cell

        mov ax, word 320
        sub ax, word [min_width]
        add di, ax

        cmp [bmp.width], word 320
        jbe .after_col_offset
        mov cx, word [bmp.width]
        sub cx, word 320
        sub cx, word [cursor.x]
        call file_skip
        .after_col_offset:

        cmp [i], word 0
        ja .for_each_row
    ret

handle_keyboard:
    xor ah, ah
    int 0x16

    cmp ax, 0x011b      ; ESC
    je exit
    cmp ax, 0x1071      ; Q
    je exit

    cmp ax, 0x4800      ; UP
    je .cursor_up

    cmp ax, 0x5000      ; DOWN
    je .cursor_down

    cmp ax, 0x4d00      ; RIGHT
    je .cursor_right

    cmp ax, 0x4b00      ; LEFT
    je .cursor_left

    cmp ax, 0x0d3d      ; =
    je .zoom_in
    cmp ax, 0x0d2b      ; +
    je .zoom_in

    cmp ax, 0x0c2d      ; -
    je .zoom_out
    cmp ax, 0x0c5f      ; _
    je .zoom_out

    je .invalid

    .cursor_up:
        mov ax, word [cursor.y]
        cmp ax, word 40
        jb .invalid
        sub [cursor.y], word 40
        ret

    .cursor_down:
        mov ax, word [cursor.y]
        mov dx, word [bmp.height]
        sub dx, word 240
        cmp ax, dx
        ja .invalid
        add [cursor.y], word 40
        ret

    .cursor_left:
        mov ax, word [cursor.x]
        cmp ax, 40
        jb .invalid
        sub [cursor.x], word 40
        ret

    .cursor_right:
        mov ax, word [cursor.x]
        mov dx, word [bmp.width]
        sub dx, word 360
        cmp ax, dx
        ja .invalid
        add [cursor.x], word 40
        ret

    .zoom_in:
    .zoom_out:

    .invalid:
        ret

bmp_read_palette:
    mov dx, 0x03c8
    mov al, 0
    out dx, al

    mov [i], word 256
    .loop:
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

        dec word [i]
        cmp [i], word 0
        ja .loop
    ret

generate_332_palette:
    mov dx, 0x03c8
    mov al, 0
    out dx, al

    mov dx, 0x03c9
    mov cl, 0
    .332_palette:
        mov al, cl
        and al, 11100000b
        shr al, 5
        mov bl, 9
        mul bl
        out dx, al

        mov al, cl
        and al, 00011100b
        shr al, 2
        mov bl, 9
        mul byte bl
        out dx, al

        mov al, cl
        and al, 00000011b
        mov bl, 21
        mul byte bl
        out dx, al

        inc cl
        cmp cl, 0
        jne .332_palette
    ret

bmp_read:
    mov cx, word 2
    mov dx, word bmp.header
    call file_read

    mov dx, word str_error_bmp_header
    cmp [bmp.header], byte "B"
    jne error
    cmp [bmp.header + 1], byte "M"
    jne error

    mov cx, word 8
    call file_skip

    mov cx, word 4
    mov dx, word bmp.data_offset
    call file_read

    mov cx, word 4
    call file_skip

    mov cx, word 2
    mov dx, word bmp.width
    call file_read

    mov cx, word 2
    call file_skip

    mov cx, word 2
    mov dx, word bmp.height
    call file_read

    mov cx, word 2
    call file_skip

    cmp [bmp.width], word 320
    ja .after_min_width
    mov ax, word [bmp.width]
    mov [min_width], word ax
    .after_min_width:

    cmp [bmp.height], word 200
    ja .after_min_height
    mov ax, word [bmp.height]
    mov [min_height], word ax
    .after_min_height:

    mov cx, word 2
    call file_skip
    mov cx, 2

    mov dx, word bmp.depth
    call file_read

    cmp [bmp.depth], word 8
    je .8_bit
    cmp [bmp.depth], word 24
    je .24_bit
    mov dx, word str_error_bmp_depth
    jmp error

    .8_bit:
        mov cx, 24
        call file_skip
        call bmp_read_palette
        ret

    .24_bit:
        call generate_332_palette
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

; Skip bytes in current file
;   CX - offset
file_skip:
    mov dx, cx
    xor cx, cx

; Skip bytes in current file
;   CX:DX - offset
file_skip_far:
    mov ah, 0x42
    mov al, 1
    mov bx, word [file.handle]
    int 0x21
    mov dx, word str_error_file_seek
    jc error
    ret

; Set position in current file
;   CX - offset
file_set_pos:
    mov ah, 0x42
    mov al, 0
    mov dx, cx
    xor cx, cx
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

segment text1
str_crlf                db 13, 10, "$"

str_error_file_open     db "Unable to open the file!$"
str_error_file_close    db "Unable to close the file!$"
str_error_file_seek     db "Error while seeking the file!$"
str_error_file_read     db "Error while reading from file!$"

str_error_bmp_header    db "Invalid BMP header!$"
str_error_bmp_depth     db "This program only handles 8bit and 24bit bitmaps!$"

file.name               db 128 dup 0
file.handle             dw 0

cursor.x                dw 0
cursor.y                dw 0

min_width               dw 320
min_height              dw 200

i                       rw 1
j                       rw 1

char                    rb 1

bgr:
bgr.b                   rb 1
bgr.g                   rb 1
bgr.r                   rb 1

bmp.header              rb 2
bmp.data_offset         rd 1
bmp.width               rw 1
bmp.height              rw 1
bmp.depth               rw 1

row                     rb 5760

palette.quad:
palette.b               rb 1
palette.g               rb 1
palette.r               rb 1
palette.padding         rb 1

; 128 bytes stack
segment stack1
stack1_head            rb 126
stack1_tail            rb 2
