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
    call read_char
    call file_close
    call mode_text
    jmp exit


; Print error and exit
;   DX - error string
error:
    call mode_text                          ; switch back to text mode
    call print


; Terminate the program with 0 exit code.
exit:
    mov ax, 0x4c00                          ; terminates the program by
    int 0x21                                ; invoking DOS interruption


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


; Open the file and exit on error
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

file.name               db 128 dup 0
file.handle             rw 1

; 128 bytes stack
segment stack1
stack1_head:    rb 127
stack1_tail:    rb 1
