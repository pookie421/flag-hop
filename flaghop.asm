; Flag Hop, a 16-bit DOS .COM game for a 386+ with VGA and an AT BIOS.
; Assemble with NASM or Yasm:
;   nasm -f bin flaghop.asm -o flaghop.com
; Hold Left/Right to run and Space to jump. Reach the flag to win.
; Enter replays a cleared level. Esc returns to DOS.

bits 16
org 0x100

pitch    equ 320
sky      equ 11
flag     equ 14
coin     equ 15
wide     equ 4
tall     equ 6
keys     equ 0x300                 ; Zeroed scratch RAM beyond the file image.

    cld
    push ds
    pop es
    xor ax, ax
    mov di, keys
    mov cx, 64
    rep stosw

    ; Keep the original keyboard vector on the stack across restarts.
    mov fs, ax
    cli
    push dword [fs:9*4]
    mov word [fs:9*4], keyboard
    mov [fs:9*4+2], cs
    sti

restart:
    mov ax, 0x13
    int 0x10
    push word 0xa000
    pop es
    xor di, di
    mov cx, pitch*200
    mov al, sky
    rep stosb

    mov si, terrain
.strip:
    lodsw
    xchg ax, di
    lodsw                           ; Low byte is width, high byte is height.
    movzx cx, al
    mov al, 6
    call rectangle
    mov ax, 0x0202
    call rectangle                  ; Grass shares the same origin as the dirt.
    cmp si, terrain_end
    jb .strip

    mov cx, wide
.coin:
    lodsw
    xchg ax, di
    mov ax, (tall << 8) | coin
    call rectangle
    cmp si, coins_end
    jb .coin

    mov di, 303+138*pitch
    mov cx, 2
    mov ax, (38 << 8) | flag
    call rectangle
    mov cx, 12
    mov ah, 7
    call rectangle

    mov si, title
    call message
    mov si, 16+(176-tall)*pitch
    xor bp, bp
    jmp draw

frame:
    mov ax, 0x8600                   ; AT BIOS wait in microseconds.
    xor cx, cx
    mov dx, 28000
    int 0x15

    mov ax, (tall << 8) | sky
    call player
    cmp byte [keys+1], 0
    js exit
    cmp byte [keys+0x39], 0
    jns .horizontal
    mov di, si
    test byte [es:di+tall*pitch], 1
    jz .jump
    test byte [es:di+tall*pitch+wide-1], 1
    jnz .horizontal
.jump:
    mov bp, -10
.horizontal:
    xor bx, bx
    cmp byte [keys+0x4b], 0
    jns .right
    dec bx
.right:
    cmp byte [keys+0x4d], 0
    jns .run
    inc bx
.run:
    call move
    call move

    inc bp
    mov cx, bp
    jcxz draw
    mov bx, pitch
    jns .vertical
    neg cx
    neg bx
.vertical:
    call move
    jz .land
    cmp si, 192*pitch
    jae restart
    loop .vertical
    jmp draw
.land:
    xor bp, bp

draw:
    mov ax, (tall << 8) | 12
    call player
    mov ax, 0x0204
    call player
    jmp frame

; SI is a framebuffer address. Adding +/-1 or +/-320 gives a trial move.
; Test all four corners and commit SI only if the new position is clear.
move:
    lea di, [bx+si]
    call probe
    jz .blocked
    add di, wide-1
    call probe
    jz .blocked
    add di, (tall-1)*pitch
    call probe
    jz .blocked
    sub di, wide-1
    call probe
    jz .blocked
    lea si, [bx+si]
.blocked:
    ret

probe:
    mov al, [es:di]
    cmp al, flag
    je win
    cmp al, coin
    jne .solid
    ; Find the pickup's top-left pixel in VRAM. The strip table is draw-only.
    push di
    and di, -wide
.top:
    sub di, pitch
    cmp [es:di], al
    je .top
    add di, pitch
    push cx
    mov ax, (tall << 8) | sky
    mov cx, wide
    call rectangle
    pop cx
    pop di
.solid:
    test al, 1                      ; Even palette indices are solid.
    ret

player:
    mov cx, wide
    mov di, si
rectangle:                         ; AX = height:color, CX = width, ES:DI = origin.
    pusha
.row:
    push cx
    rep stosb
    pop cx
    sub di, cx
    add di, pitch
    dec ah
    jnz .row
    popa
    ret

win:
    pop ax                          ; Drop the return addresses of probe and move.
    pop ax
    mov si, victory
    call message
.wait:
    cmp byte [keys+1], 0
    js exit
    cmp byte [keys+0x1c], 0
    jns .wait
    jmp restart

message:
    mov bx, 15
.letter:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0e
    int 0x10
    jmp .letter
.done:
    ret

exit:
    mov ax, 3
    int 0x10
    cli
    pop dword [fs:9*4]
    sti
    ret

keyboard:
    pusha
    in al, 0x60
    movzx bx, al
    and bl, 0x7f
    xor al, 0x80                    ; The sign bit now means the key is down.
    mov [cs:bx+keys], al
    mov al, 0x20
    out 0x20, al
    popa
    iret

%macro strip 4
    dw %1 + %2*pitch
    db %3, %4
%endmacro

terrain:
    strip   0,   0,  1, 200        ; Solid borders prevent scanline wraparound.
    strip 319,   0,  1, 200
    strip   1, 176, 62,  24
    strip  92, 176, 51,  24
    strip 121, 156, 32,   8
    strip 188, 176, 38,  24
    strip 199, 153, 33,   8
    strip 248, 138, 36,   8
    strip 272, 176, 47,  24
terrain_end:
    dw 100+168*pitch, 168+111*pitch, 268+125*pitch
coins_end:
title   db 'FLAG HOP', 13, 10, 0
victory db 'CLEAR! ENTER=REPLAY', 0

; A negative TIMES count is an assembly error at 512 bytes and above.
times -(($-$$)/512) db 0
