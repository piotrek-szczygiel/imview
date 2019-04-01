; vim: syntax=fasm
; Simple BMP image viewer for DOS
; Piotr Szczygieł - Assemblery 2019
format MZ                                   ; DOS MZ executable
entry main:start                            ; specify an application entry point

segment main
start:
    mov ax, word stack1                     ; point stack segment address
    mov ss, ax
    mov sp, word stack_tail

    call argument_read

    mov ax, word text1                      ; point data segment address
    mov ds, ax

    mov ax, word 0xa000                     ; point VGA memory address
    mov es, ax

    call mode_vga
    call file_open
    call bmp_read

    .main_loop:
        call calculate_dimensions
        call bmp_draw
        call handle_keyboard
        call correct_cursor
        jmp .main_loop

exit:
    call mode_text
    jmp dos_exit

error:
    call mode_text
    call print

dos_exit:
    mov al, byte 0
    mov ah, 0x4c
    int 0x21

bmp_draw:
    mov di, word 0      ; offset in VGA memory
    call bmp_set_pos

    mov [zoom.skip_y], byte 0
    mov ax, word [read.height]
    mov [i], word ax
    mov ax, word [display.zoom_height]
    mov [k], word ax
    .for_each_row:
        dec word [i]

        cmp [zoom], byte 0
        je .row_draw
        cmp [zoom.skip_y], byte 0
        je .row_draw
        mov cx, [bmp.skip_whole_row]
        call file_skip
        mov ah, byte [zoom]
        cmp [zoom.skip_y], byte ah
        jb .for_each_row_end
        mov [zoom.skip_y], byte 0
        jmp .for_each_row_end_dont_inc

        .row_draw:
        mov cx, word [bmp.skip_column_before]
        call file_skip

        dec word [k]
        mov ax, word [k]
        mov dx, ax
        shl ax, 8
        shl dx, 6
        add ax, dx
        mov di, ax

        mov [zoom.skip_x], byte 0
        mov ax, word [read.width]
        mov [j], word ax
        .for_each_cell:
            dec word [j]

            cmp [bmp.depth], word 8
            jne .24_bit

            .8_bit:
                mov cx, word 1
                mov dx, word char
                call file_read
                mov al, byte [char]
                jmp .handle_zoom

            .24_bit:
                mov cx, word 3
                mov dx, word bgr
                call file_read
                mov al, byte [bgr.r]
                and al, 11100000b
                and [bgr.g], byte 11100000b
                shr [bgr.g], 3
                or al, byte [bgr.g]
                shr [bgr.b], 6
                or al, byte [bgr.b]

            .handle_zoom:
            cmp [zoom], byte 0
            je .write_vga
            cmp [zoom.skip_x], byte 0
            je .write_vga
            mov ah, byte [zoom]
            cmp [zoom.skip_x], byte ah
            jb .for_each_cell_end
            mov [zoom.skip_x], byte 0
            jmp .for_each_cell_end_dont_inc

            .write_vga:
            mov [es:di], byte al
            inc di

            .for_each_cell_end:
            inc byte [zoom.skip_x]
            .for_each_cell_end_dont_inc:
            cmp [j], word 0
            ja .for_each_cell

        mov cx, word [bmp.skip_column_after]
        call file_skip

        .for_each_row_end:
        inc byte [zoom.skip_y]
        .for_each_row_end_dont_inc:
        cmp [i], word 0
        ja .for_each_row
    ret

clear_vga:
    mov di, 0
    mov cx, word 32000
    mov ax, word 0
    rep stosw
    ret

correct_cursor:
    cmp [zoom], byte 0
    je .zoom_x_0
    cmp [zoom], byte 1
    je .zoom_x_1
    mov ax, word [cursor.max_x_zoom2]
    jmp .check_cursor_x
    .zoom_x_1:
    mov ax, word [cursor.max_x_zoom1]
    jmp .check_cursor_x
    .zoom_x_0:
    mov ax, word [cursor.max_x]
    .check_cursor_x:
    cmp [cursor.x], ax
    jbe .cursor_x_ok
    mov [cursor.x], ax
    .cursor_x_ok:

    cmp [zoom], byte 0
    je .zoom_y_0
    cmp [zoom], byte 1
    je .zoom_y_1
    mov ax, word [cursor.max_y_zoom2]
    jmp .check_cursor_y
    .zoom_y_1:
    mov ax, word [cursor.max_y_zoom1]
    jmp .check_cursor_y
    .zoom_y_0:
    mov ax, word [cursor.max_y]
    .check_cursor_y:
    cmp [cursor.y], ax
    jbe .cursor_y_ok
    mov [cursor.y], ax
    .cursor_y_ok:
    ret

handle_keyboard:
    xor ah, ah
    int 0x16

    cmp ax, 0x011b      ; ESC
    je exit
    cmp ax, 0x1071      ; Q
    je exit

    cmp [cursor.max_y], word 0
    je .ignore_up_down

    cmp ax, 0x4800      ; UP
    je .cursor_up

    cmp ax, 0x5000      ; DOWN
    je .cursor_down
    .ignore_up_down:

    cmp [cursor.max_x], word 0
    je .ignore_left_right

    cmp ax, 0x4d00      ; RIGHT
    je .cursor_right

    cmp ax, 0x4b00      ; LEFT
    je .cursor_left
    .ignore_left_right:

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
        sub ax, word [cursor.jump_y]
        jns .cursor_up_free
        mov ax, 0
        .cursor_up_free:
        mov [cursor.y], word ax
        ret

    .cursor_left:
        mov ax, word [cursor.x]
        sub ax, word [cursor.jump_x]
        jns .cursor_left_free
        mov ax, 0
        .cursor_left_free:
        mov [cursor.x], word ax
        ret

    .cursor_down:
        mov ax, word [cursor.jump_y]
        add [cursor.y], ax
        ret


    .cursor_right:
        mov ax, word [cursor.jump_x]
        add [cursor.x], ax
        ret

    .zoom_in:
        cmp [zoom], byte 3
        je .zoom_in_1
        cmp [zoom], byte 1
        je .zoom_in_0
        ret
        .zoom_in_1:
        mov [zoom], byte 1
        mov [cursor.jump_x], word 160 * 2
        mov [cursor.jump_y], word 100 * 2
        ret
        .zoom_in_0:
        mov [zoom], byte 0
        mov [cursor.jump_x], word 160
        mov [cursor.jump_y], word 100
        ret

    .zoom_out:
        cmp [zoom], byte 0
        je .zoom_out_1
        cmp [zoom], byte 1
        je .zoom_out_3
        ret

        .zoom_out_1:
        mov [zoom], byte 1
        mov [cursor.jump_x], word 160 * 2
        mov [cursor.jump_y], word 100 * 2
        mov ax, 320 * 2
        mov dx, 200 * 2
        jmp .zoom_clear
        .zoom_out_3:
        mov [zoom], byte 3
        mov [cursor.jump_x], word 160 * 4
        mov [cursor.jump_y], word 100 * 4
        mov ax, 320 * 4
        mov dx, 200 * 4
        .zoom_clear:
        cmp [bmp.width], ax
        jae .zoom_wide_enough
        call clear_vga
        ret
        .zoom_wide_enough:
        cmp [bmp.height], dx
        jae .zoom_tall_enough
        call clear_vga
        .zoom_tall_enough:
    .invalid:
        ret

calculate_dimensions:
    mov ax, word [display.width]
    mov [read.width], ax
    cmp [zoom], byte 0
    je .after_zoom_x
    add [read.width], ax
    cmp [zoom], byte 1
    je .after_zoom_x
    add [read.width], ax
    add [read.width], ax
    .after_zoom_x:
    mov ax, [bmp.width]
    cmp [read.width], ax
    jbe .after_read_width
    mov [read.width], ax
    .after_read_width:

    mov ax, word [display.height]
    mov [read.height], ax
    cmp [zoom], byte 0
    je .after_zoom_y
    add [read.height], ax
    cmp [zoom], byte 1
    je .after_zoom_y
    add [read.height], ax
    add [read.height], ax
    .after_zoom_y:
    mov ax, [bmp.height]
    cmp [read.height], ax
    jbe .after_read_height
    mov [read.height], ax
    .after_read_height:

    mov ax, word [display.height]
    mov [display.zoom_height], ax
    cmp [zoom], byte 0
    je .after_zoom_height
    mov ax, word [bmp.height]
    shr ax, 1
    cmp [zoom], byte 1
    je .zoom_1
    shr ax, 1
    .zoom_1:
    cmp ax, word 200
    jae .after_zoom_height
    mov [display.zoom_height], word ax
    .after_zoom_height:

    mov [bmp.skip_column_before], word 0
    cmp [bmp.width], word 320
    jbe .after_cursor_x_offset
    mov ax, word [cursor.x]
    cmp [bmp.depth], word 8
    je .dont_m3_x_begin
    mov dx, word 3
    mul dx
    .dont_m3_x_begin:
    mov [bmp.skip_column_before], word ax
    .after_cursor_x_offset:

    mov ax, word 0
    cmp [bmp.width], word 320
    jbe .after_width_sub
    add ax, word [bmp.width]
    sub ax, word [cursor.x]
    sub ax, word [read.width]
    .after_width_sub:
    cmp [bmp.depth], word 8
    je .dont_m3_x_end
    mov dx, word 3
    mul dx
    .dont_m3_x_end:
    add ax, word [bmp.padding]
    mov [bmp.skip_column_after], word ax

    ret

bmp_set_pos:
    mov cx, word [bmp.data_offset]
    call file_set_pos

    mov dx, word 200
    add dx, word [cursor.y]
    mov ax, word [bmp.height]
    cmp ax, dx
    jbe .after_y_offset
    sub ax, dx
    cmp [zoom], byte 0
    je .after_cursor_zoom
    cmp [zoom], byte 1
    je .zoom_1
    mov dx, word 800
    add dx, word [cursor.y]
    cmp [bmp.height], word dx
    jbe .after_y_offset
    mov ax, word [bmp.height]
    sub ax ,dx
    jmp .after_cursor_zoom
    .zoom_1:
    mov dx, word 400
    add dx, word [cursor.y]
    cmp [bmp.height], word dx
    jbe .after_y_offset
    mov ax, word [bmp.height]
    sub ax, dx
    .after_cursor_zoom:
    mov dx, word [bmp.skip_whole_row]
    mul dx
    mov cx, dx
    mov dx, ax
    call file_skip_far
    .after_y_offset:
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

    nop
    mov ax, word [bmp.width]
    mov [display.width], word 320
    cmp ax, word 320
    jae .wider_than_320
    mov [display.width], word ax
    jmp .after_display_width
    .wider_than_320:
    sub ax, word 320
    mov [cursor.max_x], word ax
    sub ax, word 320
    js .after_display_width
    mov [cursor.max_x_zoom1], word ax
    sub ax, word 640
    js .after_display_width
    mov [cursor.max_x_zoom2], word ax
    .after_display_width:

    mov ax, word [bmp.height]
    mov [display.height], word 200
    cmp ax, word 200
    jae .higher_than_200
    mov [display.height], word ax
    jmp .after_display_height
    .higher_than_200:
    sub ax, word 200
    mov [cursor.max_y], word ax
    sub ax, word 200
    js .after_display_height
    mov [cursor.max_y_zoom1], word ax
    sub ax, word 400
    js .after_display_height
    mov [cursor.max_y_zoom2], word ax
    .after_display_height:

    mov cx, word 4
    call file_skip

    mov cx, 2
    mov dx, word bmp.depth
    call file_read

    mov ax, word [bmp.width]
    cmp [bmp.depth], word 8
    je .dont_m3_padding
    mov dx, word 3
    mul dx
    .dont_m3_padding:
    and ax, word 3
    mov dx, word 4
    sub dx, ax
    and dx, word 3
    mov [bmp.padding], word dx

    mov ax, word [bmp.width]
    mov [bmp.skip_whole_row], word ax
    cmp [bmp.depth], word 8
    je .dont_m3_skip_whole_row
    mov dx, word 3
    mul dx
    mov [bmp.skip_whole_row], word ax
    .dont_m3_skip_whole_row:
    mov ax, word [bmp.padding]
    add [bmp.skip_whole_row], ax

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
    mov [es:di], byte 0
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

cursor.x                dw 0
cursor.y                dw 0
cursor.jump_x           dw 160
cursor.jump_y           dw 100
cursor.max_x            dw 0
cursor.max_y            dw 0
cursor.max_x_zoom1      dw 0
cursor.max_y_zoom1      dw 0
cursor.max_x_zoom2      dw 0
cursor.max_y_zoom2      dw 0

zoom                    db 0
zoom.skip_x             rb 1
zoom.skip_y             rb 1

file.handle             rw 1
file.name               rb 128

display.width           rw 1
display.height          rw 1
display.zoom_height     rw 1

read.width              rw 1
read.height             rw 1

i                       rw 1
j                       rw 1
k                       rw 1

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
bmp.padding             rw 1

bmp.skip_whole_row      rw 1
bmp.skip_column_before  rw 1
bmp.skip_column_after   rw 1

palette.quad:
palette.b               rb 1
palette.g               rb 1
palette.r               rb 1

; 256 bytes stack
segment stack1
stack_head              rw 127
stack_tail              rw 1
