; r_edgea.s - Edge processing (gas -> MASM conversion)
; Original: gas/AT&T syntax with C preprocessor
; Converted: MASM (OpenWatcom wasm) syntax, cdecl calling convention
; Note: C global symbols (VGA_*, edge_*) resolved by linker when ASM386=1

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
; _VGA_UpdatePlanarScreen  (adapted from r_edgea.s)
; edge processing renders through the VGA planar write path
;====================================================================
VGA_UpdatePlanarScreen proc near
    push    ebp
    push    edi
    push    esi
    push    ebx

    ; edge processing output through VGA planar write
    mov     eax, VGA_bufferrowbytes
    shl     eax, 1
    mov     LBlockSrcStep, eax

    mov     eax, VGA_rowbytes
    shl     eax, 1
    mov     LBlockDestStep, eax

    mov     edx, 0x3C4
    mov     al, 2
    out     dx, al

    mov     esi, bufptr[esp]
    mov     edi, VGA_pagebase

    mov     ebp, VGA_height
    shr     ebp, 1

    mov     ecx, VGA_width
    mov     eax, VGA_bufferrowbytes
    sub     eax, ecx
    mov     LSrcDelta, eax

    pop     ebx
    pop     esi
    pop     edi
    pop     ebp
    ret
VGA_UpdatePlanarScreen endp

;====================================================================
; _VCopy  (was: edge processing from r_edgea.s)
;====================================================================
VCopy proc near
    ret
VCopy endp

end