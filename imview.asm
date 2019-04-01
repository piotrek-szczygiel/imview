; vim: syntax=fasm
;
; Simple BMP image viewer for DOS
; Piotr Szczygieł - Assemblery 2019
;

format MZ                       ; DOS MZ executable
entry main:start

segment main
start:
    mov ax, word stack1         ; point stack segment address
    mov ss, ax
    mov sp, word stack_tail

    call argument_read

    mov ax, word text1          ; set data segment address
    mov ds, ax

    mov ax, word 0xa000         ; set VGA buffer address
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

; Switch to text mode and exit
exit:
    call mode_text
    jmp dos_exit

; Switch to text mode, print an error and exit
;   DX - error string
error:
    call mode_text
    call print

; Exit the application
dos_exit:
    mov al, byte 0
    mov ah, 0x4c
    int 0x21

; Draw the bitmap on screen
bmp_draw:
    mov di, word 0      ; offset in VGA memory
    call bmp_set_pos

    mov [zoom.skip_y], byte 0
    mov ax, word [read.height]
    mov [i], word ax    ; row read counter
    mov ax, word [display.zoom_height]
    mov [k], word ax    ; row display counter
    .for_each_row:
        dec word [i]

        cmp [zoom], byte 0              ; draw row
        je .row_draw
        cmp [zoom.skip_y], byte 0
        je .row_draw
        mov cx, [bmp.skip_whole_row]
        call file_skip                  ; or skip it when zoomed out
        mov ah, byte [zoom]
        cmp [zoom.skip_y], byte ah
        jb .for_each_row_end
        mov [zoom.skip_y], byte 0
        jmp .for_each_row_end_dont_inc

        .row_draw:
        mov cx, word [bmp.skip_column_before]
        call file_skip

        dec word [k]        ; position VGA pointer on current row
        mov ax, word [k]
        mov dx, ax
        shl ax, 8           ;   k << 8 + k << 6
        shl dx, 6           ; = 256 * k + 64 * k
        add ax, dx          ; = 320 * k
        mov di, ax

        mov [zoom.skip_x], byte 0
        mov ax, word [read.width]
        mov [j], word ax    ; cell read counter
        .for_each_cell:
            dec word [j]

            cmp [bmp.depth], word 8
            jne .24_bit

            .8_bit:
                mov cx, word 1
                mov dx, word c
                call file_read      ; read 1 byte and store it
                mov al, byte [c]    ; in the AL register
                jmp .handle_zoom

            .24_bit:
                mov cx, word 3
                mov dx, word bgr            ; read 3 bytes into bgr structure
                call file_read
                mov al, byte [bgr.r]        ; convert bgr into 332 format
                and al, 11100000b           ; and store it in the AL register
                and [bgr.g], byte 11100000b
                shr [bgr.g], 3
                or al, byte [bgr.g]
                shr [bgr.b], 6
                or al, byte [bgr.b]

            .handle_zoom:
            cmp [zoom], byte 0
            je .write_vga                   ; draw current cell
            cmp [zoom.skip_x], byte 0
            je .write_vga
            mov ah, byte [zoom]
            cmp [zoom.skip_x], byte ah
            jb .for_each_cell_end           ; or skip it when zoomed out
            mov [zoom.skip_x], byte 0
            jmp .for_each_cell_end_dont_inc

            .write_vga:
            mov [es:di], byte al            ; draw pixel on screen
            inc di                          ; move to next cell in VGA buffer

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

; Handle keyboard input
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
    je .zoom_in         ; or
    cmp ax, 0x0d2b      ; +
    je .zoom_in

    cmp ax, 0x0c2d      ; -
    je .zoom_out        ; or
    cmp ax, 0x0c5f      ; _
    je .zoom_out

    je .invalid         ; unknown key

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
        mov [cursor.jump_x], word 80 * 2
        mov [cursor.jump_y], word 50 * 2
        ret
        .zoom_in_0:
        mov [zoom], byte 0
        mov [cursor.jump_x], word 80
        mov [cursor.jump_y], word 50
        ret

    .zoom_out:
        cmp [zoom], byte 0
        je .zoom_out_1
        cmp [zoom], byte 1
        je .zoom_out_3
        ret

        .zoom_out_1:
        mov [zoom], byte 1
        mov [cursor.jump_x], word 80 * 2
        mov [cursor.jump_y], word 50 * 2
        mov ax, 320 * 2
        mov dx, 200 * 2
        jmp .zoom_clear
        .zoom_out_3:
        mov [zoom], byte 3
        mov [cursor.jump_x], word 80 * 4
        mov [cursor.jump_y], word 50 * 4
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

; Correct the cursor position if it went out of bounds
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

; Calculate some needed variables depending on zoom, color depth, etc.
calculate_dimensions:
    mov ax, word 320
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

    mov ax, word 200
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

    mov ax, word [bmp.height]
    cmp ax, word 200
    jae .higher_than_200
    jmp .after_height_trim
    .higher_than_200:
    mov ax, word 200
    .after_height_trim:
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

; Set file position so it matches cursor position and current zoom
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

; Read and apply palette from 256-color bitmap
bmp_read_palette:
    mov dx, 0x03c8              ; tell dos that you will now pass
    mov al, 0                   ; all 256 elements of color palette
    out dx, al

    mov [i], word 256
    .loop:
        mov cx, word 3          ; read 3 bytes into bgr structure
        mov dx, word bgr
        call file_read
        mov cx, word 1          ; skip 1 padding byte
        call file_skip

        mov dx, 0x03c9
        mov al, byte [bgr.r]
        shr al, 2               ; shift every byte by 2 left
        out dx, al              ; output it to 0x03c9 port
        mov al, byte [bgr.g]
        shr al, 2
        out dx, al
        mov al, byte [bgr.b]
        shr al, 2
        out dx, al

        dec word [i]
        cmp [i], word 0
        ja .loop
    ret

; Generate 332 palette to be able to display 24bit bitmaps
generate_332_palette:
    mov dx, 0x03c8          ; tell dos that you will now pass
    mov al, 0               ; all 256 elements of color palette
    out dx, al

    mov dx, 0x03c9
    mov cl, 0               ; index counter
    .332_palette:
        mov al, cl          ; get red value from index
        and al, 11100000b
        shr al, 5
        mov bl, 9           ; multiply it by 9 to make it
        mul bl              ; in [0, 63] range
        out dx, al

        mov al, cl          ; get green value from index
        and al, 00011100b
        shr al, 2
        mov bl, 9           ; 111b * 9 = 255 >> 2
        mul byte bl
        out dx, al

        mov al, cl          ; get blue value from index
        and al, 00000011b
        mov bl, 21          ; 3 * 21 = 255 >> 2
        mul byte bl
        out dx, al

        inc cl              ; increase index
        cmp cl, 0
        jne .332_palette
    ret

; Read and parse the bitmap file structure
bmp_read:
    mov cx, word 2
    mov dx, word bmp.header
    call file_read

    mov dx, word str_error_bmp_header
    cmp [bmp.header], byte "B"          ; first two bytes should be "BM"
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

    mov ax, word [bmp.width]            ; calculate cursor x boundaries
    cmp ax, word 320
    jb .after_cursor_max_x
    sub ax, word 320
    mov [cursor.max_x], word ax
    sub ax, word 320
    js .after_cursor_max_x
    mov [cursor.max_x_zoom1], word ax
    sub ax, word 640
    js .after_cursor_max_x
    mov [cursor.max_x_zoom2], word ax
    .after_cursor_max_x:

    mov ax, word [bmp.height]           ; calculate cursor y boundaries
    cmp ax, word 200
    jb .after_cursor_max_y
    sub ax, word 200
    mov [cursor.max_y], word ax
    sub ax, word 200
    js .after_cursor_max_y
    mov [cursor.max_y_zoom1], word ax
    sub ax, word 400
    js .after_cursor_max_y
    mov [cursor.max_y_zoom2], word ax
    .after_cursor_max_y:

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
    and ax, word 3                  ; calculate end of row byte padding for
    mov dx, word 4                  ; images which width is not divisible by 4
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
    add [bmp.skip_whole_row], ax    ; how many bytes are in a single row

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

    mov si, 0x82            ; offset to beginning of argument
    mov di, file.name

    xor ch, ch
    mov cl, byte [0x80]     ; argument length
    dec cl                  ; ignore first byte which is a space
    cld
    rep movsb
    mov [es:di], byte 0     ; add null delimiter at the end of filename
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

; Clear the VGA buffer with black color
clear_vga:
    mov di, 0
    mov cx, word 32000      ; place 0x0000 * 32000 times in VGA buffer
    mov ax, word 0          ; to clear the whole screen in black
    rep stosw
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

cursor.x                dw 0    ; current cursor x position
cursor.y                dw 0    ; current cursor y position
cursor.jump_x           dw 80   ; how many column to move while panning
cursor.jump_y           dw 50   ; how many rows to move while panning
cursor.max_x            dw 0    ; maximum cursor column while not zoomed out
cursor.max_y            dw 0    ; maximum cursor row while not zoomed out
cursor.max_x_zoom1      dw 0    ; maximum cursor column while zoomed out once
cursor.max_y_zoom1      dw 0    ; maximum cursor row while zoomed out once
cursor.max_x_zoom2      dw 0    ; maximum cursor column while zoomed out twice
cursor.max_y_zoom2      dw 0    ; maximum cursor row while zoomed out twice

zoom                    db 0    ; current zoom factor
zoom.skip_x             rb 1    ; modulo column skipper
zoom.skip_y             rb 1    ; modulo row skipper

file.handle             rw 1    ; dos file handle to loaded bmp file
file.name               rb 128  ; filename retrieved from program argument

display.zoom_height     rw 1    ; height of the image on current zoom level

read.width              rw 1    ; how many bytes to read for each row
read.height             rw 1    ; how many rows to read

c                       rb 1    ; byte helper variable
i                       rw 1    ; loop counter
j                       rw 1    ; inner loop counter
k                       rw 1    ; helper variable

bgr:                            ; structure for storing pixel color information
bgr.b                   rb 1    ; blue
bgr.g                   rb 1    ; green
bgr.r                   rb 1    ; red

bmp.header              rb 2    ; two first bytes of the bmp file - "BM"
bmp.data_offset         rd 1    ; file offset at which pixel array begins
bmp.width               rw 1    ; width of the image
bmp.height              rw 1    ; height of the image
bmp.depth               rw 1    ; color depth - 8 or 24
bmp.padding             rw 1    ; how many bytes to ignore on each row end

bmp.skip_whole_row      rw 1    ; how many bytes are in a signle row
bmp.skip_column_before  rw 1    ; how many bytes are in a row before viewport
bmp.skip_column_after   rw 1    ; how many bytes are in a row after viewport

segment stack1                  ; 256 byte stack
stack_head              rw 127
stack_tail              rw 1
