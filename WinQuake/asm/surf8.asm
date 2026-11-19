;=============================================================================
; surf8.asm - 8 bpp surface block drawing (replaces the old placeholder stub)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/surf8.s.
; Four mip-level routines + R_Surf8Patch + R_Surf8Start/End code labels.
; Each mip draws 16/8/4/2-pixel blocks with self-modifying colormap lookups.
; Self-modifying 'mov al,[eax+12345678h]' disp32 fields are patched by
; R_Surf8Patch via the 32-entry LPatchTable8.
; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> preserved.
;=============================================================================

.386
.model  small

extrn   _r_lightptr:dword, _r_numvblocks:dword, _prowdestbase:dword
extrn   _pbasesource:dword, _r_lightwidth:dword, _lightright:dword
extrn   _lightrightstep:dword, _lightdeltastep:dword, _lightdelta:dword
extrn   _sourcetstep:dword, _surfrowbytes:dword, _r_sourcemax:dword
extrn   _r_stepback:dword, _colormap:dword

public  R_Surf8Start_, R_Surf8End_, R_Surf8Patch_
public  R_DrawSurfaceBlock8_mip0_, R_DrawSurfaceBlock8_mip1_
public  R_DrawSurfaceBlock8_mip2_, R_DrawSurfaceBlock8_mip3_

; ---- per-mip block-pixel lookups ------------------------------------------
; Two colormap lookups packed into EAX (ah from EBX-index, al from ECX-index),
; rotated, then stored. 'num' selects the patch label number.
LOOKUP2 macro num0, num1
        mov     ah, [ebx+12345678h]
LBPatch&num0&:
        mov     al, [ecx+12345678h]
LBPatch&num1&:
endm

.data
        ALIGN 4
sb_v    dd 0

        ALIGN 4
LPatchTable8:
        dd LBPatch0-4,  LBPatch1-4,  LBPatch2-4,  LBPatch3-4
        dd LBPatch4-4,  LBPatch5-4,  LBPatch6-4,  LBPatch7-4
        dd LBPatch8-4,  LBPatch9-4,  LBPatch10-4, LBPatch11-4
        dd LBPatch12-4, LBPatch13-4, LBPatch14-4, LBPatch15-4
        dd LBPatch16-4, LBPatch17-4, LBPatch18-4, LBPatch19-4
        dd LBPatch20-4, LBPatch21-4, LBPatch22-4, LBPatch23-4
        dd LBPatch24-4, LBPatch25-4, LBPatch26-4, LBPatch27-4
        dd LBPatch28-4, LBPatch29-4, LBPatch30-4, LBPatch31-4

.code

        ALIGN 4
public R_Surf8Start_
R_Surf8Start_:

;=============================================================================
; MIP0 - 16 pixels/block
;=============================================================================
        ALIGN 4
public R_DrawSurfaceBlock8_mip0_
R_DrawSurfaceBlock8_mip0_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx
        mov     ebx, [_r_lightptr]
        mov     eax, [_r_numvblocks]
        mov     [sb_v], eax
        mov     edi, [_prowdestbase]
        mov     esi, [_pbasesource]
Lv_loop_mip0:
        mov     eax, [ebx]
        mov     edx, [ebx+4]
        mov     ebp, eax
        mov     ecx, [_r_lightwidth]
        mov     [_lightright], edx
        sub     ebp, edx
        and     ebp, 0FFFFFh
        lea     ebx, [ebx+ecx*4]
        mov     [_r_lightptr], ebx
        mov     ecx, [ebx+4]
        mov     ebx, [ebx]
        sub     ebx, eax
        sub     ecx, edx
        sar     ecx, 4
        or      ebp, 0F0000000h
        sar     ebx, 4
        mov     [_lightrightstep], ecx
        sub     ebx, ecx
        and     ebx, 0FFFFFh
        or      ebx, 0F0000000h
        xor     ecx, ecx
        mov     [_lightdeltastep], ebx
        xor     ebx, ebx

Lblockloop8_mip0:
        mov     [_lightdelta], ebp
        mov     cl, [esi+14]
        sar     ebp, 4
        mov     bh, dh
        mov     bl, [esi+15]
        add     edx, ebp
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 0, 1
        mov     bl, [esi+13]
        mov     cl, [esi+12]
        mov     bh, dh
        add     edx, ebp
        ror     eax, 16
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 2, 3
        mov     [edi+12], eax
        mov     bh, dh
        add     edx, ebp
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 4, 5
        mov     bl, [esi+9]
        mov     cl, [esi+8]
        mov     bh, dh
        add     edx, ebp
        ror     eax, 16
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 6, 7
        mov     [edi+8], eax
        mov     bh, dh
        add     edx, ebp
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 8, 9
        mov     bl, [esi+5]
        mov     cl, [esi+4]
        mov     bh, dh
        add     edx, ebp
        ror     eax, 16
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 10, 11
        mov     [edi+4], eax
        mov     bh, dh
        add     edx, ebp
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 12, 13
        ror     eax, 16
        LOOKUP2 14, 15
        mov     edx, [_lightright]
        mov     ebp, [_lightdelta]
        mov     [edi], eax
        add     esi, [_sourcetstep]
        add     edi, [_surfrowbytes]
        add     edx, [_lightrightstep]
        add     ebp, [_lightdeltastep]
        mov     [_lightright], edx
        jc      Lblockloop8_mip0
        cmp     esi, [_r_sourcemax]
        jb      LSkip_mip0
        sub     esi, [_r_stepback]
LSkip_mip0:
        mov     ebx, [_r_lightptr]
        dec     dword ptr [sb_v]
        jnz     Lv_loop_mip0
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret
R_DrawSurfaceBlock8_mip0_ endp

;=============================================================================
; MIP1 - 8 pixels/block (patch labels 22-29)
;=============================================================================
        ALIGN 4
public R_DrawSurfaceBlock8_mip1_
R_DrawSurfaceBlock8_mip1_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx
        mov     ebx, [_r_lightptr]
        mov     eax, [_r_numvblocks]
        mov     [sb_v], eax
        mov     edi, [_prowdestbase]
        mov     esi, [_pbasesource]
Lv_loop_mip1:
        mov     eax, [ebx]
        mov     edx, [ebx+4]
        mov     ebp, eax
        mov     ecx, [_r_lightwidth]
        mov     [_lightright], edx
        sub     ebp, edx
        and     ebp, 0FFFFFh
        lea     ebx, [ebx+ecx*4]
        mov     [_r_lightptr], ebx
        mov     ecx, [ebx+4]
        mov     ebx, [ebx]
        sub     ebx, eax
        sub     ecx, edx
        sar     ecx, 3
        or      ebp, 070000000h
        sar     ebx, 3
        mov     [_lightrightstep], ecx
        sub     ebx, ecx
        and     ebx, 0FFFFFh
        or      ebx, 0F0000000h
        xor     ecx, ecx
        mov     [_lightdeltastep], ebx
        xor     ebx, ebx
Lblockloop8_mip1:
        mov     [_lightdelta], ebp
        mov     cl, [esi+6]
        sar     ebp, 3
        mov     bh, dh
        mov     bl, [esi+7]
        add     edx, ebp
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 22, 23
        mov     bl, [esi+5]
        mov     cl, [esi+4]
        mov     bh, dh
        add     edx, ebp
        ror     eax, 16
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 24, 25
        mov     bl, [esi+3]
        mov     cl, [esi+2]
        mov     [edi+4], eax
        mov     bh, dh
        add     edx, ebp
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 26, 27
        mov     bl, [esi+1]
        mov     cl, [esi]
        ror     eax, 16
        LOOKUP2 28, 29
        mov     edx, [_lightright]
        mov     ebp, [_lightdelta]
        mov     [edi], eax
        add     esi, [_sourcetstep]
        add     edi, [_surfrowbytes]
        add     edx, [_lightrightstep]
        add     ebp, [_lightdeltastep]
        mov     [_lightright], edx
        jc      Lblockloop8_mip1
        cmp     esi, [_r_sourcemax]
        jb      LSkip_mip1
        sub     esi, [_r_stepback]
LSkip_mip1:
        mov     ebx, [_r_lightptr]
        dec     dword ptr [sb_v]
        jnz     Lv_loop_mip1
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret
R_DrawSurfaceBlock8_mip1_ endp

;=============================================================================
; MIP2 - 4 pixels/block (patch labels 18-21)
;=============================================================================
        ALIGN 4
public R_DrawSurfaceBlock8_mip2_
R_DrawSurfaceBlock8_mip2_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx
        mov     ebx, [_r_lightptr]
        mov     eax, [_r_numvblocks]
        mov     [sb_v], eax
        mov     edi, [_prowdestbase]
        mov     esi, [_pbasesource]
Lv_loop_mip2:
        mov     eax, [ebx]
        mov     edx, [ebx+4]
        mov     ebp, eax
        mov     ecx, [_r_lightwidth]
        mov     [_lightright], edx
        sub     ebp, edx
        and     ebp, 0FFFFFh
        lea     ebx, [ebx+ecx*4]
        mov     [_r_lightptr], ebx
        mov     ecx, [ebx+4]
        mov     ebx, [ebx]
        sub     ebx, eax
        sub     ecx, edx
        sar     ecx, 2
        or      ebp, 030000000h
        sar     ebx, 2
        mov     [_lightrightstep], ecx
        sub     ebx, ecx
        and     ebx, 0FFFFFh
        or      ebx, 0F0000000h
        xor     ecx, ecx
        mov     [_lightdeltastep], ebx
        xor     ebx, ebx
Lblockloop8_mip2:
        mov     [_lightdelta], ebp
        mov     cl, [esi+2]
        sar     ebp, 2
        mov     bh, dh
        mov     bl, [esi+3]
        add     edx, ebp
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 18, 19
        mov     bl, [esi+1]
        mov     cl, [esi]
        mov     bh, dh
        add     edx, ebp
        ror     eax, 16
        mov     ch, dh
        add     edx, ebp
        LOOKUP2 20, 21
        mov     edx, [_lightright]
        mov     ebp, [_lightdelta]
        mov     [edi], eax
        add     esi, [_sourcetstep]
        add     edi, [_surfrowbytes]
        add     edx, [_lightrightstep]
        add     ebp, [_lightdeltastep]
        mov     [_lightright], edx
        jc      Lblockloop8_mip2
        cmp     esi, [_r_sourcemax]
        jb      LSkip_mip2
        sub     esi, [_r_stepback]
LSkip_mip2:
        mov     ebx, [_r_lightptr]
        dec     dword ptr [sb_v]
        jnz     Lv_loop_mip2
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret
R_DrawSurfaceBlock8_mip2_ endp

;=============================================================================
; MIP3 - 2 pixels/block (patch labels 16,17,30,31)
;=============================================================================
        ALIGN 4
public R_DrawSurfaceBlock8_mip3_
R_DrawSurfaceBlock8_mip3_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx
        mov     ebx, [_r_lightptr]
        mov     eax, [_r_numvblocks]
        mov     [sb_v], eax
        mov     edi, [_prowdestbase]
        mov     esi, [_pbasesource]
Lv_loop_mip3:
        mov     eax, [ebx]
        mov     edx, [ebx+4]
        mov     ebp, eax
        mov     ecx, [_r_lightwidth]
        mov     [_lightright], edx
        sub     ebp, edx
        and     ebp, 0FFFFFh
        lea     ebx, [ebx+ecx*4]
        mov     [_r_lightptr], ebx
        mov     ecx, [ebx+4]
        mov     ebx, [ebx]
        sub     ebx, eax
        sub     ecx, edx
        sar     ecx, 1
        sar     ebx, 1
        mov     [_lightrightstep], ecx
        sub     ebx, ecx
        and     ebx, 0FFFFFh
        sar     ebp, 1
        or      ebx, 0F0000000h
        mov     [_lightdeltastep], ebx
        xor     ebx, ebx                ; high dword must be 0 in loop for addressing
        mov     bl, [esi+1]
        xor     ecx, ecx
        mov     bh, dh
        mov     cl, [esi]
        add     edx, ebp
        mov     ch, dh
Lblockloop8_mip3:
        ; first pixel pair (this block)
        mov     al, [ebx+12345678h]
LBPatch16:
        mov     edx, [_lightright]
        mov     [edi+1], al
        mov     al, [ecx+12345678h]
LBPatch17:
        mov     [edi], al
        mov     eax, [_sourcetstep]
        add     esi, eax
        mov     eax, [_surfrowbytes]
        add     edi, eax
        mov     eax, [_lightdeltastep]
        mov     ebp, [_lightdelta]
        mov     cl, [esi]
        add     ebp, eax
        mov     eax, [_lightrightstep]
        sar     ebp, 1
        add     edx, eax
        mov     bh, dh
        mov     bl, [esi+1]
        add     edx, ebp
        mov     ch, dh
        ; second pixel pair (next block, prefetched)
        mov     al, [ebx+12345678h]
LBPatch30:
        mov     edx, [_sourcetstep]
        mov     [edi+1], al
        mov     al, [ecx+12345678h]
LBPatch31:
        mov     [edi], al
        mov     ebp, [_surfrowbytes]
        add     edx, esi
        add     ebp, edi
        cmp     esi, [_r_sourcemax]
        jb      LSkip_mip3
        sub     esi, [_r_stepback]
LSkip_mip3:
        mov     ebx, [_r_lightptr]
        dec     dword ptr [sb_v]
        jnz     Lv_loop_mip3
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret
R_DrawSurfaceBlock8_mip3_ endp

        ALIGN 4
public R_Surf8End_
R_Surf8End_:

;=============================================================================
; R_Surf8Patch_ - patches the 32 self-modifying colormap displacements
;=============================================================================
        ALIGN 4
public R_Surf8Patch_
R_Surf8Patch_ proc near
        push    ebx
        mov     eax, [_colormap]
        mov     ebx, offset LPatchTable8
        mov     ecx, 32
LPatchLoop8:
        mov     edx, [ebx]
        add     ebx, 4
        mov     [edx], eax
        dec     ecx
        jnz     LPatchLoop8
        pop     ebx
        ret
R_Surf8Patch_ endp

end
