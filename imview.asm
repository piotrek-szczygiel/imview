; vim: syntax=fasm
; Simple calculator
; Piotr Szczygieł - Assemblery 2019
format MZ                                   ; DOS MZ executable
entry main:start                            ; specify an application entry point

segment main
start:
    mov ax, word stack1                     ; point program where the
    mov ss, ax                              ; stack segment is
    mov sp, word stack1_tail

    mov ax, word text1                      ; point program where the
    mov ds, ax                              ; data segment is


; Terminate the program with 0 exit code.
exit:
    mov ax, 4c00h                           ; terminates the program by
    int 21h                                 ; invoking DOS interruption


segment text1

; 128 bytes stack
segment stack1
stack1_head: rb 127
stack1_tail: rb 1
