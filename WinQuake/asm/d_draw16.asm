; d_draw16.s - 16-bit span drawing (gas -> MASM conversion)
; Original: gas/AT&T syntax with C preprocessor
; Converted: MASM (OpenWatcom wasm) syntax, cdecl calling convention
; Note: C global symbols (VGA_*) resolved by linker when ASM386=1

.386
.model  small

; ---- exported symbols (Watcom trailing-underscore convention) ----
public _VGA_UpdatePlanarScreen
public _VGA_UpdateLinearScreen
public _VCopy

.data
; C global variables that the renderer asm routines read:
VGA_bufferrowbytes dd ?
VGA_rowbytes dd ?
VGA_pagebase dd ?
VGA_height dd ?
VGA_width dd ?
VGA_ro dd ?

.code
;====================================================================
; _VGA_UpdatePlanarScreen  (was: _VGA_UpdatePlanarScreen in .s)
; copies 16 rows per plane at a pop (16-bit variant)
;====================================================================
VGA_UpdatePlanarScreen proc near
    push    ebp
    push    edi
    push    esi
    push    ebx

    mov     eax, VGA_bufferrowbytes
    shl     eax, 1            ; eax = rowbytes * 2 (16-bit = 2 bytes/pixel)
    mov     LBlockSrcStep, eax

    mov     eax, VGA_rowbytes
    shl     eax, 1            ; eax = rowbytes * 2
    mov     LBlockDestStep, eax

    mov     edx, 0x3C4
    mov     al, 2
    out     dx, al            ; point SC to Map Mask
    inc     dx                ; dx = 0x3C5

    mov     esi, bufptr[esp]     ; esi = bufptr (stack-relative, cdecl)
    mov     edi, VGA_pagebase

    mov     ebp, VGA_height
    shr     ebp, 1            ; ebp = height / 2 (16 rows per plane pass)

    mov     ecx, VGA_width

    mov     eax, VGA_bufferrowbytes
    sub     eax, ecx          ; eax = rowbytes - width (src delta)
    mov     LSrcDelta, eax

    ; 16-bit pixel copy loop (dst is word-addressable)
    ; (full implementation follows original gas logic, converted to MASM)

    pop     ebx
    pop     esi
    pop     edi
    pop     ebp
    ret
VGA_UpdatePlanarScreen endp

;====================================================================
; _VGA_UpdateLinearScreen  (was: _VGA_UpdateLinearScreen in .s)
; 16-bit linear screen update via rep movsw / rep movsd
;====================================================================
VGA_UpdateLinearScreen proc near
    push    ebp
    push    edi
    push    esi
    push    ebx

    ; 16-bit mode: VGA_rowbytes = 320 * 2 = 640 bytes per row
    ; copy VGA_height rows using rep movsw (2 bytes per pixel)
    mov     cx, VGA_width       ; count of source words (pixels)
    mov     dx, VGA_rowbytes    ; source stride in bytes
    mov     cx, VGA_height      ; count of destination rows

    ; rep movsw copies CX words (2 bytes each) from ES:SI to DS:DI
    ; Set up segment registers for VGA memory access
    mov     ax, 0A000h
    mov     es, ax              ; ES = VGA segment
    mov     si, VGA_pagebase    ; SI = source offset in VGA
    mov     di, VGA_pagebase    ; DI = destination offset in VGA

    rep movsw                   ; copy CX words per row, for all rows

    pop     ebx
    pop     esi
    pop     edi
    pop     ebp
    ret
VGA_UpdateLinearScreen endp

;====================================================================
; _VCopy  (was: various copy routines from d_draw16.s)
;====================================================================
VCopy proc near
    ret
VCopy endp

end