;=============================================================================
; d_spr8.asm - 8-bpp transparent span drawing with z buffering
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/d_spr8.s.
; D_SpriteDrawSpans(sspan_t *pspans) - 1 arg in EAX. Plus Spr8Entry2_8..8.
; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> preserved.
; FPU operand order follows the verified d_draw.asm mapping.
;=============================================================================

.386
.model  small

TRANSPARENT_COLOR equ 255

sspan_t_u     equ 0
sspan_t_v     equ 4
sspan_t_count equ 8
sspan_t_size  equ 12

extrn   _d_sdivzstepu:dword, _d_tdivzstepu:dword, _d_zistepu:dword
extrn   _d_sdivzstepv:dword, _d_tdivzstepv:dword, _d_zistepv:dword
extrn   _d_sdivzorigin:dword, _d_tdivzorigin:dword, _d_ziorigin:dword
extrn   _cacheblock:dword, _cachewidth:dword, _sadjust:dword, _tadjust:dword
extrn   _bbextents:dword, _bbextentt:dword, _d_viewbuffer:dword, _d_scantable:dword
extrn   _d_pzbuffer:dword, _d_zrowbytes:dword, _d_zwidth:dword

extrn   fp_8:dword, fp_64k:dword, fp_64kx64k:dword
extrn   reciprocal_table:dword
extrn   pbase:dword, zi8stepu:dword, sdivz8stepu:dword, tdivz8stepu:dword
extrn   s:dword, t:dword, snext:dword, tnext:dword, spancountminus1:dword
extrn   sfracf:dword, tfracf:dword, pspantemp:dword, counttemp:dword
extrn   jumptemp:dword, advancetable:dword, sstep:dword, tstep:dword
extrn   izi:dword, izistep:dword, pz:dword
extrn   spr8entryvec_table:dword

public  D_SpriteDrawSpans_
public  Spr8Entry2_8, Spr8Entry3_8, Spr8Entry4_8, Spr8Entry5_8
public  Spr8Entry6_8, Spr8Entry7_8, Spr8Entry8_8

; ---- one pixel in the 8-wide non-last segment -------------------------------
; z compare/store uses a 16-bit word at [ecx+zoff]; colour store at [edi+off].
SPRPIX macro off, zoff
        cmp     bp, word ptr [ecx+zoff]
        jl      Lskip&off
        mov     al, [esi]
        cmp     al, TRANSPARENT_COLOR
        jz      Lskip&off
        mov     [ecx+zoff], bp
        mov     [edi+off], al
Lskip&off:
        add     ebp, [izistep]
        adc     ebp, 0
        add     edx, [tstep]
        sbb     eax, eax
        add     ebx, [sstep]
        adc     esi, [advancetable+4+eax*4]
endm

; ---- one pixel in the variable-length last segment -------------------------
SPR8PIX macro pos, zoff
        cmp     bp, word ptr [ecx+zoff]
        jl      LskipE&pos
        mov     al, [esi]
        cmp     al, TRANSPARENT_COLOR
        jz      LskipE&pos
        mov     [ecx+zoff], bp
        mov     [edi+pos], al
LskipE&pos:
endm

SPR8STEP macro
        add     ebp, [izistep]
        adc     ebp, 0
        add     edx, [tstep]
        sbb     eax, eax
        add     ebx, [sstep]
        adc     esi, [advancetable+4+eax*4]
endm

.code

;=============================================================================
; D_SpriteDrawSpans_  (was: _D_SpriteDrawSpans)  -- EAX = sspan_t *pspans
;=============================================================================
D_SpriteDrawSpans_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx

        mov     ebx, eax                ; first span descriptor
        mov     [pspantemp], ebx

; scaled-by-8 steps + cacheblock + span pointer
        fld     dword ptr [_d_sdivzstepu]
        fmul    dword ptr [fp_8]
        mov     edx, [_cacheblock]
        fld     dword ptr [_d_tdivzstepu]
        fmul    dword ptr [fp_8]
        fld     dword ptr [_d_zistepu]
        fmul    dword ptr [fp_8]
        mov     [pbase], edx
        fld     dword ptr [_d_zistepu]
        fmul    dword ptr [fp_64kx64k]
        fxch    st(3)
        fstp    dword ptr [sdivz8stepu]
        fstp    dword ptr [zi8stepu]
        fstp    dword ptr [tdivz8stepu]
        fistp   dword ptr [izistep]
        mov     eax, [izistep]
        ror     eax, 16
        mov     ecx, [ebx+sspan_t_count]
        mov     [izistep], eax
        cmp     ecx, 0
        jle     LNextSpan

LSpanLoop:
; initial s/z, t/z, 1/z on FP stack
        fild    dword ptr [ebx+sspan_t_v]
        fild    dword ptr [ebx+sspan_t_u]
        fld     st(1)
        fmul    dword ptr [_d_sdivzstepv]
        fld     st(1)
        fmul    dword ptr [_d_sdivzstepu]
        fld     st(2)
        fmul    dword ptr [_d_tdivzstepu]
        fxch    st(1)
        faddp   st(2), st(0)
        fxch    st(1)
        fld     st(3)
        fmul    dword ptr [_d_tdivzstepv]
        fxch    st(1)
        fadd    dword ptr [_d_sdivzorigin]
        fxch    st(4)
        fmul    dword ptr [_d_zistepv]
        fxch    st(1)
        faddp   st(2), st(0)
        fxch    st(2)
        fmul    dword ptr [_d_zistepu]
        fxch    st(1)
        fadd    dword ptr [_d_tdivzorigin]
        fxch    st(2)
        faddp   st(1), st(0)
        fld     dword ptr [fp_64k]
        fxch    st(1)
        fadd    dword ptr [_d_ziorigin]
        fld     st(0)
        fmul    dword ptr [fp_64kx64k]
        fxch    st(1)
        fdiv    st(2), st(0)             ; 1/z | z*64k | t/z | s/z
        fxch    st(1)
        fistp   dword ptr [izi]          ; 0.32 fixed-point 1/z
        mov     ebp, [izi]

; set pz to first z-buffer pixel
        ror     ebp, 16
        mov     eax, [ebx+sspan_t_v]
        mov     [izi], ebp
        mov     ebp, [ebx+sspan_t_u]
        imul    eax, [_d_zrowbytes]
        shl     ebp, 1
        add     eax, [_d_pzbuffer]
        add     eax, ebp
        mov     [pz], eax

; point edi to first pixel
        mov     ebp, [_d_viewbuffer]
        mov     eax, [ebx+sspan_t_v]
        mov     edx, [_tadjust]
        mov     esi, [_sadjust]
        mov     edi, [_d_scantable+eax*4]
        add     edi, ebp
        mov     ebp, [ebx+sspan_t_u]
        add     edi, ebp
        mov     ecx, [ebx+sspan_t_count]

; start FDIV for end of span
        cmp     ecx, 8
        ja      LSetupNotLast1
        dec     ecx
        jz      LCleanup1
        mov     [spancountminus1], ecx
        fxch    st(1)
        fld     st(0)
        fmul    st(0), st(4)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(1)
        fistp   dword ptr [s]
        fistp   dword ptr [t]
        fild    dword ptr [spancountminus1]
        fld     dword ptr [_d_tdivzstepu]
        fld     dword ptr [_d_zistepu]
        fmul    st(0), st(2)
        fxch    st(1)
        fmul    st(0), st(2)
        fxch    st(2)
        fmul    dword ptr [_d_sdivzstepu]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(1)
        faddp   st(3), st(0)
        faddp   st(3), st(0)
        fld     dword ptr [fp_64k]
        fdiv    st(0), st(1)
        jmp     LFDIVInFlight1
LCleanup1:
        fxch    st(1)
        fld     st(0)
        fmul    st(0), st(4)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(1)
        fistp   dword ptr [s]
        fistp   dword ptr [t]
        jmp     LFDIVInFlight1
        ALIGN 4
LSetupNotLast1:
        fxch    st(1)
        fld     st(0)
        fmul    st(0), st(4)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(1)
        fistp   dword ptr [s]
        fistp   dword ptr [t]
        fadd    dword ptr [zi8stepu]
        fxch    st(2)
        fadd    dword ptr [sdivz8stepu]
        fxch    st(2)
        fld     dword ptr [tdivz8stepu]
        faddp   st(2), st(0)
        fld     dword ptr [fp_64k]
        fdiv    st(0), st(1)
LFDIVInFlight1:
        add     esi, [s]
        add     edx, [t]
        mov     ebx, [_bbextents]
        mov     ebp, [_bbextentt]
        cmp     esi, ebx
        ja      LClampHighOrLow0
LClampReentry0:
        mov     [s], esi
        mov     ebx, [pbase]
        shl     esi, 16
        cmp     edx, ebp
        mov     [sfracf], esi
        ja      LClampHighOrLow1
LClampReentry1:
        mov     [t], edx
        mov     esi, [s]
        shl     edx, 16
        mov     eax, [t]
        sar     esi, 16
        mov     [tfracf], edx
        sar     eax, 16
        mov     edx, [_cachewidth]
        imul    eax, edx
        add     esi, ebx
        add     esi, eax

        cmp     ecx, 8
        jna     LLastSegment

LNotLastSegment:
        fld     st(0)
        fmul    st(0), st(4)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(1)
        fistp   dword ptr [snext]
        fistp   dword ptr [tnext]
        mov     eax, [snext]
        mov     edx, [tnext]
        sub     ecx, 8
        mov     [counttemp], ecx
        mov     ebp, [_sadjust]
        mov     ecx, [_tadjust]
        add     ebp, eax
        add     ecx, edx
        mov     eax, [_bbextents]
        mov     edx, [_bbextentt]
        cmp     ebp, 2048
        jl      LClampLow2
        cmp     ebp, eax
        ja      LClampHigh2
LClampReentry2:
        cmp     ecx, 2048
        jl      LClampLow3
        cmp     ecx, edx
        ja      LClampHigh3
LClampReentry3:
        mov     [snext], ebp
        mov     [tnext], ecx
        sub     ebp, [s]
        sub     ecx, [t]
        mov     eax, ecx
        mov     edx, ebp
        sar     edx, 19
        mov     ebx, [_cachewidth]
        sar     eax, 19
        jz      LIsZero
        imul    eax, ebx
LIsZero:
        add     eax, edx
        mov     edx, [tfracf]
        mov     [advancetable+4], eax
        add     eax, ebx
        shl     ebp, 13
        mov     [sstep], ebp
        mov     ebx, [sfracf]
        shl     ecx, 13
        mov     [advancetable], eax
        mov     [tstep], ecx

        mov     ecx, [pz]
        mov     ebp, [izi]
        SPRPIX 0, 0
        SPRPIX 1, 2
        SPRPIX 2, 4
        SPRPIX 3, 6
        SPRPIX 4, 8
        SPRPIX 5, 10
        SPRPIX 6, 12
        SPRPIX 7, 14

; advance pointers and save the stepped fractions/z for the next segment
        add     edi, 8
        add     ecx, 16
        mov     [tfracf], edx
        mov     eax, [snext]
        mov     [sfracf], ebx
        mov     ebx, [tnext]
        mov     [s], eax
        mov     [t], ebx
        mov     [pz], ecx
        mov     [izi], ebp

; start FDIV for next segment
        mov     ecx, [counttemp]
        cmp     ecx, 8
        ja      LSetupNotLast2
        dec     ecx
        jz      LFDIVInFlight2
        mov     [spancountminus1], ecx
        fild    dword ptr [spancountminus1]
        fld     dword ptr [_d_zistepu]
        fmul    st(0), st(1)
        fld     dword ptr [_d_tdivzstepu]
        fmul    st(0), st(2)
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(1)
        fmul    dword ptr [_d_sdivzstepu]
        fxch    st(1)
        faddp   st(3), st(0)
        fld     dword ptr [fp_64k]
        fxch    st(1)
        faddp   st(4), st(0)
        fdiv    st(0), st(1)
        jmp     LFDIVInFlight2
        ALIGN 4
LSetupNotLast2:
        fadd    dword ptr [zi8stepu]
        fxch    st(2)
        fadd    dword ptr [sdivz8stepu]
        fxch    st(2)
        fld     dword ptr [tdivz8stepu]
        faddp   st(2), st(0)
        fld     dword ptr [fp_64k]
        fdiv    st(0), st(1)
LFDIVInFlight2:
        mov     [counttemp], ecx
        mov     ecx, [counttemp]
        cmp     ecx, 8
        ja      LNotLastSegment

; last segment
LLastSegment:
        test    ecx, ecx
        jz      LNoSteps
        fld     st(0)
        fmul    st(0), st(4)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(1)
        fistp   dword ptr [snext]
        fistp   dword ptr [tnext]

        mov     ebp, [_sadjust]
        mov     edx, [_tadjust]
        add     ebp, [snext]
        add     edx, [tnext]
        mov     ebx, [_bbextents]
        mov     eax, [_bbextentt]
        cmp     ebp, 2048
        jl      LClampLow4
        cmp     ebp, ebx
        ja      LClampHigh4
LClampReentry4:
        mov     [snext], ebp
        cmp     edx, 2048
        jl      LClampLow5
        cmp     edx, eax
        ja      LClampHigh5
LClampReentry5:
        cmp     ecx, 1
        je      LOnlyOneStep
        sub     ebp, [s]
        sub     edx, [t]
        add     ebp, ebp                ; 15.17 format
        add     edx, edx
        mov     ebx, edx                ; save doubled tdelta
        mov     eax, ebp
        imul    dword ptr [reciprocal_table+ecx*4-8]   ; EDX:EAX = sstep
        mov     ebp, edx                ; high 32 bits = fractional sstep
        mov     eax, ebx
        imul    dword ptr [reciprocal_table+ecx*4-8]   ; EDX:EAX = tstep
        mov     eax, edx                ; high 32 bits = fractional tstep
        jmp     LSetEntryvec
LNoSteps:
        mov     ecx, [pz]
        sub     edi, 7
        sub     ecx, 14
        jmp     LEndSpan
LOnlyOneStep:
        sub     ebp, [s]
        sub     edx, [t]
        mov     eax, edx                ; tdelta (full 16.16 step)
        jmp     LSetEntryvec

LSetEntryvec:
        mov     ebx, [spr8entryvec_table+ecx*4]
        mov     edx, eax
        mov     [jumptemp], ebx
        mov     ecx, ebp
        sar     edx, 16
        mov     ebx, [_cachewidth]
        sar     ecx, 16
        imul    edx, ebx
        add     edx, ecx
        mov     ecx, [tfracf]
        mov     [advancetable+4], edx
        add     edx, ebx
        shl     ebp, 16
        mov     ebx, [sfracf]
        shl     eax, 16
        mov     [advancetable], edx
        mov     [tstep], eax
        mov     [sstep], ebp
        mov     edx, ecx
        mov     ecx, [pz]
        mov     ebp, [izi]
        jmp     dword ptr [jumptemp]

; ---- Spr8 Entry points (transparent, 2-8 pixels) ---------------------------
; The hardwired offsets in the fall-through chain are relative to EDI/ECX.
; Each entry shifts those bases so its first drawn pixel lands on pixel 0.
Spr8Entry2_8:
        sub     edi, 6
        sub     ecx, 12
        mov     al, [esi]
        jmp     LLEntry2_8
Spr8Entry3_8:
        sub     edi, 5
        sub     ecx, 10
        jmp     LLEntry3_8
Spr8Entry4_8:
        sub     edi, 4
        sub     ecx, 8
        jmp     LLEntry4_8
Spr8Entry5_8:
        sub     edi, 3
        sub     ecx, 6
        jmp     LLEntry5_8
Spr8Entry6_8:
        sub     edi, 2
        sub     ecx, 4
        jmp     LLEntry6_8
Spr8Entry7_8:
        dec     edi
        sub     ecx, 2
        jmp     LLEntry7_8
Spr8Entry8_8:
        SPR8PIX 0, 0
        SPR8STEP
LLEntry7_8:
        SPR8PIX 1, 2
        SPR8STEP
LLEntry6_8:
        SPR8PIX 2, 4
        SPR8STEP
LLEntry5_8:
        SPR8PIX 3, 6
        SPR8STEP
LLEntry4_8:
        SPR8PIX 4, 8
        SPR8STEP
LLEntry3_8:
        SPR8PIX 5, 10
        SPR8STEP
LLEntry2_8:
        SPR8PIX 6, 12
        SPR8STEP
LEndSpan:
        SPR8PIX 7, 14
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)

LNextSpan:
        mov     ebx, [pspantemp]
        add     ebx, sspan_t_size
        mov     [pspantemp], ebx
        mov     ecx, [ebx+sspan_t_count]
        cmp     ecx, 0
        jg      LSpanLoop
        jz      LNextSpan
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret

; clamping helpers
LClampHighOrLow0:
        jg      LCH0
        xor     esi, esi
        jmp     LClampReentry0
LCH0:   mov     esi, [_bbextents]
        jmp     LClampReentry0
LClampHighOrLow1:
        jg      LCH1
        xor     edx, edx
        jmp     LClampReentry1
LCH1:   mov     edx, [_bbextentt]
        jmp     LClampReentry1
LClampLow2: mov ebp, 2048
        jmp LClampReentry2
LClampHigh2: mov ebp, [_bbextents]
        jmp LClampReentry2
LClampLow3: mov ecx, 2048
        jmp LClampReentry3
LClampHigh3: mov ecx, [_bbextentt]
        jmp LClampReentry3
LClampLow4: mov ebp, 2048
        jmp LClampReentry4
LClampHigh4: mov ebp, [_bbextents]
        jmp LClampReentry4
LClampLow5: mov edx, 2048
        jmp LClampReentry5
LClampHigh5: mov edx, [_bbextentt]
        jmp LClampReentry5
D_SpriteDrawSpans_ endp

end
