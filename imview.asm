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

    .main_loop:
        call bmp_draw
        xor ah, ah
        int 0x16

        cmp ax, 0x011b
        je .exit

;       cmp ax, 0x4800
;       je .cursor_up

;       cmp ax, 0x5000
;       je .cursor_down

;       cmp ax, 0x4d00
;       je .cursor_right

;       cmp ax, 0x4b00
;       je .cursor_left

        jmp .main_loop

.exit:
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

; Display row
;   AX - row number
display_row:
    mov dx, ax
    shl ax, 8
    shl dx, 6
    add ax, dx

    mov cx, word [row.width]
    mov si, word row
    mov di, ax
    rep movsb
    ret

bmp_draw:
    mov cx, word [bmp.data_offset]
    call file_set_pos

    cmp [bmp.depth], word 8
    je .8_bit
    cmp [bmp.depth], word 24
    je .24_bit
    mov dx, word str_error_bmp_depth
    jmp error

    .24_bit:
        mov ax, word [bmp.height]
        mov [counter], word ax
        .loop_24_bit:
            dec word [counter]

            mov [counter2], word 0
            .loop_row:
                mov cx, word 3
                mov dx, word bgr
                call file_read

                mov al, [bgr.r]
                and al, 11100000b

                mov bl, [bgr.g]
                and bl, 11100000b
                shr bl, 3

                mov dl, [bgr.b]
                shr dl, 6

                or al, bl
                or al, dl

                mov bx, word row
                add bx, word [counter2]

                mov [bx], byte al

                inc word [counter2]
                mov ax, word [bmp.width]
                cmp [counter2], word ax
                jb .loop_row

            mov ax, word [counter]
            call display_row

            cmp [counter], word 0
            ja .loop_24_bit
        ret

    .8_bit:
        mov ax, word [bmp.height]
        mov [counter], word ax
        .loop_8_bit:
            dec word [counter]

            mov cx, word [bmp.width]
            mov dx, word row
            call file_read

            mov ax, word [counter]
            call display_row

            cmp [counter], word 0
            ja .loop_8_bit
        ret

bmp_read_palette:
    mov dx, 0x03c8
    mov al, 0
    out dx, al

    mov [counter], word 256
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

        dec word [counter]
        cmp [counter], word 0
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

bmp_prepare:
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

    mov cx, word 4
    mov dx, word bmp.width
    call file_read

    mov [row.width], word 320

    mov ax, word [bmp.width]
    cmp ax, word 320
    jae .continue
    mov [row.width], word ax

.continue:
    mov cx, word 4
    mov dx, word bmp.height
    call file_read

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
    mov ah, 0x42
    mov al, 1
    mov dx, cx
    xor cx, cx
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

bgr:
bgr.b                   rb 1
bgr.g                   rb 1
bgr.r                   rb 1

bmp.header              rb 2
bmp.data_offset         rd 1
bmp.width               rd 1
bmp.height              rd 1
bmp.depth               rw 1

row.width               rw 1
row                     rb 2048

palette.quad:
palette.b               rb 1
palette.g               rb 1
palette.r               rb 1
palette.padding         rb 1

counter                 rw 1
counter2                rw 1

; 128 bytes stack
segment stack1
stack1_head            rb 126
stack1_tail            rb 2
