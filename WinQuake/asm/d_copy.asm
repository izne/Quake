;=============================================================================
; d_copy.asm - screen copy routines (replaces the old placeholder stub)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/d_copy.s.
; Two routines:
;   VGA_UpdatePlanarScreen  (1 arg: bufptr in EAX) - planar VGA copy (port I/O)
;   VGA_UpdateLinearScreen  (6 args) - linear framebuffer copy via REP MOVSD
;
; Watcom register ABI: EAX volatile; EBX/ECX/EDX/ESI/EDI/EBP callee-saved.
; For VGA_UpdateLinearScreen the probe showed: EAX=srcptr, EDX=destptr,
; EBX=width, ECX=height, and args 5/6 (srcrowbytes/destrowbytes) on the stack.
; C data uses leading underscore. Local data labels are private to this module.
;=============================================================================

.386
.model  small

; ---- C globals (leading underscore) ----------------------------------------
extrn   _VGA_bufferrowbytes:dword, _VGA_rowbytes:dword
extrn   _VGA_pagebase:dword, _VGA_height:dword, _VGA_width:dword

public  VGA_UpdatePlanarScreen_, VGA_UpdateLinearScreen_

.data
LCopyWidth      dd 0
LBlockSrcStep   dd 0
LBlockDestStep  dd 0
LSrcDelta       dd 0
LDestDelta      dd 0

.code

;=============================================================================
; VGA_UpdatePlanarScreen_  (was: _VGA_UpdatePlanarScreen)
; C: void VGA_UpdatePlanarScreen(void *srcbuffer)  -- srcbuffer in EAX
;=============================================================================
VGA_UpdatePlanarScreen_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx                     ; callee-saved in Watcom
        push    edx                     ; callee-saved in Watcom
        push    eax                     ; save srcbuffer -> [esp]

        mov     eax, [_VGA_bufferrowbytes]
        shl     eax, 1
        mov     [LBlockSrcStep], eax
        mov     eax, [_VGA_rowbytes]
        shl     eax, 1
        mov     [LBlockDestStep], eax

        mov     edx, 03C4h
        mov     al, 2
        out     dx, al                  ; point SC to Map Mask register
        inc     edx

        mov     esi, [esp]              ; srcbuffer
        mov     edi, [_VGA_pagebase]
        mov     ebp, [_VGA_height]
        shr     ebp, 1

        mov     ecx, [_VGA_width]
        mov     eax, [_VGA_bufferrowbytes]
        sub     eax, ecx
        mov     [LSrcDelta], eax
        mov     eax, [_VGA_rowbytes]
        shl     eax, 2
        sub     eax, ecx
        mov     [LDestDelta], eax
        shr     ecx, 4
        mov     [LCopyWidth], ecx

LRowLoop:
        mov     al, 1
LPlaneLoop:
        out     dx, al
        mov     ah, 2
        push    esi
        push    edi
LRowSetLoop:
        mov     ecx, [LCopyWidth]
LColumnLoop:
        mov     bh, [esi+12]
        mov     bl, [esi+8]
        shl     ebx, 16
        mov     bh, [esi+4]
        mov     bl, [esi]
        mov     [edi], ebx
        add     esi, 16
        add     edi, 4
        dec     ecx
        jnz     LColumnLoop

        add     edi, [LDestDelta]
        add     esi, [LSrcDelta]
        dec     ah
        jnz     LRowSetLoop

        pop     edi
        pop     esi
        inc     esi
        shl     al, 1
        cmp     al, 16
        jnz     LPlaneLoop

        sub     esi, 4
        add     esi, [LBlockSrcStep]
        add     edi, [LBlockDestStep]
        dec     ebp
        jnz     LRowLoop

        pop     eax
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret
VGA_UpdatePlanarScreen_ endp


;=============================================================================
; VGA_UpdateLinearScreen_  (was: _VGA_UpdateLinearScreen)
; C: void VGA_UpdateLinearScreen(void *srcptr, void *destptr, int width,
;                                int height, int srcrowbytes, int destrowbytes)
; Register args: EAX=srcptr, EDX=destptr, EBX=width, ECX=height;
; stack args: [esp+4]=srcrowbytes, [esp+8]=destrowbytes (at entry).
;=============================================================================
VGA_UpdateLinearScreen_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx                     ; saved height
        push    edx                     ; saved destptr
        ; [esp+0]=destptr, [esp+4]=height, [esp+8]=width,
        ; [esp+28]=srcrowbytes, [esp+32]=destrowbytes
        mov     esi, eax                ; esi = srcptr
        mov     edi, [esp+0]            ; edi = destptr
        mov     ebx, [esp+8]            ; ebx = width
        mov     ebp, [esp+4]            ; ebp = height
        mov     eax, [esp+28]           ; eax = srcrowbytes
        sub     eax, ebx
        mov     edx, [esp+32]           ; edx = destrowbytes
        sub     edx, ebx
        shr     ebx, 2                  ; dword count
        cld
LLRowLoop:
        mov     ecx, ebx
        rep     movsd
        add     esi, eax
        add     edi, edx
        dec     ebp
        jnz     LLRowLoop

        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret     8                       ; callee pops the 2 stack-passed args (5,6)
VGA_UpdateLinearScreen_ endp

end
