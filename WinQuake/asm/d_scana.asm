;=============================================================================
; d_scana.asm - turbulent texture mapping (replaces the old placeholder stub)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/d_scana.s.
; D_DrawTurbulent8Span is void (all state in C globals with leading underscore).
; Watcom: EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> all preserved.
;=============================================================================

.386
.model  small

CYCLE           equ 128
TURB_TEX_SIZE   equ 64

; ---- C globals (leading underscore) ----------------------------------------
extrn   _r_turb_s:dword, _r_turb_t:dword, _r_turb_pdest:dword
extrn   _r_turb_spancount:dword, _r_turb_turb:dword
extrn   _r_turb_pbase:dword, _r_turb_sstep:dword, _r_turb_tstep:dword

public  D_DrawTurbulent8Span_

.code

;=============================================================================
; D_DrawTurbulent8Span_  (was: _D_DrawTurbulent8Span)  -- void
;=============================================================================
D_DrawTurbulent8Span_ proc near
        push    ebp
        push    esi
        push    edi
        push    ebx
        push    ecx                     ; callee-saved
        push    edx                     ; callee-saved

        mov     esi, [_r_turb_s]
        mov     ecx, [_r_turb_t]
        mov     edi, [_r_turb_pdest]
        mov     ebx, [_r_turb_spancount]

Llp:
        mov     eax, ecx
        mov     edx, esi
        sar     eax, 16
        mov     ebp, [_r_turb_turb]
        sar     edx, 16
        and     eax, CYCLE-1
        and     edx, CYCLE-1
        mov     eax, [ebp+eax*4]
        mov     edx, [ebp+edx*4]
        add     eax, esi
        sar     eax, 16
        add     edx, ecx
        sar     edx, 16
        and     eax, TURB_TEX_SIZE-1
        and     edx, TURB_TEX_SIZE-1
        shl     edx, 6
        mov     ebp, [_r_turb_pbase]
        add     edx, eax
        inc     edi
        add     esi, [_r_turb_sstep]
        add     ecx, [_r_turb_tstep]
        mov     dl, [ebp+edx]
        dec     ebx
        mov     [edi-1], dl
        jnz     Llp

        mov     [_r_turb_pdest], edi

        pop     edx
        pop     ecx
        pop     ebx
        pop     edi
        pop     esi
        pop     ebp
        ret
D_DrawTurbulent8Span_ endp

end
