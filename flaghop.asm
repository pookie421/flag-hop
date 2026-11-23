; Flag Hop, a 16-bit DOS .COM game for a 386+ with VGA and an AT BIOS.
; Assemble with NASM or Yasm:
;   nasm -f bin flaghop.asm -o flaghop.com
; Hold Left/Right to run and Space to jump. Reach the flag to win.
; Enter generates a new course after clearing one. Esc returns to DOS.

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
    xor ax, ax
    mov di, keys
    mov cx, 64
    rep stosw

    ; Keep the original keyboard vector and the course seed on the stack.
    mov fs, ax
    mov bx, 9*4
    cli
    push dword [fs:bx]
    mov word [fs:bx], keyboard
    mov [fs:bx+2], cs
    sti
    push word [fs:0x46c]            ; Seed the first course from the BIOS timer.

restart:
    mov ax, 0x13
    int 0x10
    push word 0xa000
    pop es
    mov di, 1                       ; Leave the BIOS-cleared black edges solid.
    mov cx, pitch-2
    mov ax, (200 << 8) | sky
    call rectangle

    mov di, 176*pitch
    pop bx
    push bx                         ; Generate from a copy, so respawns repeat.
    mov dl, 3
.bay:
    ror bx, 5                       ; Expose five unused seed bits in BH for this bay.
    mov cl, bh
    and cx, 15
    or cl, 48                       ; Width 48..63 leaves a 17..32 pixel pit.
    call ground

    push di
    sub di, 16*pitch-36
    test bh, 16
    jz .platform
    sub di, 12*pitch
.platform:
    mov cl, 20
    mov ax, 0x0806
    call grass
    sub di, tall*pitch-8            ; Four-aligned so pickup can find its left edge.
    mov cl, wide
    mov ax, (tall << 8) | coin
    call rectangle
    pop di
    add di, 80
    dec dl
    jnz .bay
    mov cl, 80
    call ground

    mov di, 303+138*pitch
    mov cl, 2
    mov ax, (38 << 8) | flag
    call rectangle
    mov cl, 12
    mov ah, 7
    call rectangle

    mov si, title
    call message
    mov si, 16+(176-tall)*pitch
    xor bp, bp

draw:
    mov ax, (tall << 8) | 12
    call player
    mov ax, 0x0204
    call player
frame:
    mov ah, 0x86                    ; AT BIOS wait in microseconds.
    xor cx, cx
    mov dx, 28000
    int 0x15

    mov ax, (tall << 8) | sky
    call player
    or al, [keys+1]
    js exit
    or al, [keys+0x39]
    jns .horizontal
    lea di, [si+tall*pitch]
    mov al, [es:di]
    and al, [es:di+wide-1]
    test al, 1
    jnz .horizontal
    mov bp, -10
.horizontal:
    mov al, [keys+0x4b]
    sub al, [keys+0x4d]              ; Down is -1, up is 0. Both keys cancel out.
    cbw
    xchg ax, bx
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
    jmp draw

exit:
    mov ax, 3
    int 0x10
    cli
    pop ax                          ; Discard the seed before restoring IRQ 1.
    pop dword [fs:9*4]
    sti
    ret

; SI is a framebuffer address. Adding +/-1 or +/-320 gives a trial move.
; Test all four corners and commit SI only if the new position is clear.
move:
    lea di, [bx+si]
    call .edge
    jz .blocked
    add di, (tall-1)*pitch-(wide-1)
    call .edge
    jz .blocked
    lea si, [bx+si]
.blocked:
    ret
.edge:
    call probe
    jz .blocked
    add di, wide-1
    call probe
    ret

probe:
    mov al, [es:di]
    cmp al, flag
    jb .solid
    je win
    ; Coins use the highest palette index in the playfield, just above flag.
    pusha
    and di, -wide
.top:
    sub di, pitch
    cmp [es:di], al
    je .top
    add di, pitch
    mov si, di
    mov ax, (tall << 8) | sky
    call player
    popa
.solid:
    test al, 1                      ; Even palette indices are solid.
    ret

ground:
    mov ax, 0x1806
grass:
    call rectangle
    mov ax, 0x0202
    jmp short rectangle
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
    pop ax                          ; Unwind probe, .edge and move.
    pop ax
    pop ax
    mov si, victory
    call message
.wait:
    hlt
    or al, [keys+1]                 ; Message returned AL=0, as do released keys.
    js exit
    or al, [keys+0x1c]
    jns .wait
    pop ax
    inc ax                          ; Bit 0 flips, changing the first pit width.
    push ax
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

keyboard:
    pusha
    in al, 0x60
    cbw
    mov bl, al
    and bx, 0x7f
    not ah                          ; A make code becomes -1, a break code 0.
    mov [cs:bx+keys], ah
    mov al, 0x20
    out 0x20, al
    popa
    iret

title   db 'FLAG HOP', 13, 10, 0
victory db 'CLEAR! ENTER', 0

; A negative TIMES count is an assembly error at 512 bytes and above.
times -(($-$$)/512) db 0
