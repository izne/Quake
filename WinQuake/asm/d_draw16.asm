;=============================================================================
; d_draw16.asm - 8-bpp horizontal span-drawing code, 16-pixel subdivision
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/d_draw16.s.
; One routine + 15 entry points:
;   D_DrawSpans16  (arg EAX = espan_t *pspans) - textured spans, 16-px segments
;   Entry2_16 .. Entry16_16 - jump targets for last-segment pixel counts
;
; Calling convention (Watcom 32-bit register ABI, verified by probe):
;   EAX volatile; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> all preserved.
;   C data uses leading underscore; ASM-only globals use plain names.
;
; FPU mapping (verified in math/d_polysa/d_draw translations):
;   faddp %st(0),%st(N) -> faddp st(N),st(0)
;   fdivr %st(0),%st(1) -> fdiv   st(1),st(0)   (st1 = st1/st0)
;   fdiv  %st(1),%st(0) -> fdiv   st(0),st(1)   (st0 = st0/st1)
;   fmul  %st(a),%st(0) -> fmul   st(0),st(a)
;=============================================================================

.386
.model  small

; ---- espan_t offsets --------------------------------------------------------
espan_t_u       equ 0
espan_t_v       equ 4
espan_t_count   equ 8
espan_t_pnext   equ 12

; ---- C globals (leading underscore) ----------------------------------------
extrn   _d_sdivzstepu:dword, _d_tdivzstepu:dword, _d_zistepu:dword
extrn   _d_sdivzstepv:dword, _d_tdivzstepv:dword, _d_zistepv:dword
extrn   _d_sdivzorigin:dword, _d_tdivzorigin:dword, _d_ziorigin:dword
extrn   _cacheblock:dword, _cachewidth:dword, _sadjust:dword, _tadjust:dword
extrn   _bbextents:dword, _bbextentt:dword, _d_viewbuffer:dword, _d_scantable:dword

; ---- ASM-only globals (plain names, from d_varsa/r_varsa) -------------------
extrn   fp_16:dword, fp_64k:dword
extrn   pbase:dword, zi16stepu:dword, sdivz16stepu:dword, tdivz16stepu:dword
extrn   s:dword, t:dword, snext:dword, tnext:dword, spancountminus1:dword
extrn   sfracf:dword, tfracf:dword, pspantemp:dword, counttemp:dword
extrn   jumptemp:dword, advancetable:dword, tstep:dword
extrn   reciprocal_table_16:dword, entryvec_table_16:dword

; ---- exports ----------------------------------------------------------------
public  D_DrawSpans16_
public  Entry2_16, Entry3_16, Entry4_16, Entry5_16, Entry6_16, Entry7_16
public  Entry8_16, Entry9_16, Entry10_16, Entry11_16, Entry12_16
public  Entry13_16, Entry14_16, Entry15_16, Entry16_16

.code

;------------------------------------------------------------------------------
; out-of-line, rarely-needed clamping code
;------------------------------------------------------------------------------
LClampHigh0:
        mov     esi, [_bbextents]
        jmp     LClampReentry0
LClampHighOrLow0:
        jg      LClampHigh0
        xor     esi, esi
        jmp     LClampReentry0

LClampHigh1:
        mov     edx, [_bbextentt]
        jmp     LClampReentry1
LClampHighOrLow1:
        jg      LClampHigh1
        xor     edx, edx
        jmp     LClampReentry1

LClampLow2:
        mov     ebp, 4096
        jmp     LClampReentry2
LClampHigh2:
        mov     ebp, [_bbextents]
        jmp     LClampReentry2

LClampLow3:
        mov     ecx, 4096
        jmp     LClampReentry3
LClampHigh3:
        mov     ecx, [_bbextentt]
        jmp     LClampReentry3

LClampLow4:
        mov     eax, 4096
        jmp     LClampReentry4
LClampHigh4:
        mov     eax, [_bbextents]
        jmp     LClampReentry4

LClampLow5:
        mov     ebx, 4096
        jmp     LClampReentry5
LClampHigh5:
        mov     ebx, [_bbextentt]
        jmp     LClampReentry5


;=============================================================================
; D_DrawSpans16_  (was: _D_DrawSpans16)  -- 16-px textured spans
; C: void D_DrawSpans16(espan_t *pspans)  -- pspans in EAX
;=============================================================================
D_DrawSpans16_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx                     ; callee-saved, clobbered as scratch
        push    edx                     ; callee-saved, clobbered as scratch
        mov     ebx, eax                ; point to first span descriptor

; set up scaled-by-16 steps and cacheblock / span list pointers
        fld     dword ptr [_d_sdivzstepu]
        fmul    dword ptr [fp_16]
        mov     edx, [_cacheblock]
        fld     dword ptr [_d_tdivzstepu]
        fmul    dword ptr [fp_16]
        fld     dword ptr [_d_zistepu]
        fmul    dword ptr [fp_16]
        mov     [pbase], edx
        fstp    dword ptr [zi16stepu]
        fstp    dword ptr [tdivz16stepu]
        fstp    dword ptr [sdivz16stepu]

LSpanLoop:
; initial s/z, t/z, 1/z on FP stack; generate initial s and t
        fild    dword ptr [ebx+espan_t_v]
        fild    dword ptr [ebx+espan_t_u]

        fld     st(1)                        ; dv | du | dv
        fmul    dword ptr [_d_sdivzstepv]
        fld     st(1)                        ; du | dv*sstepv | du | dv
        fmul    dword ptr [_d_sdivzstepu]
        fld     st(2)                        ; du | du*sstepu | dv*sstepv | du | dv
        fmul    dword ptr [_d_tdivzstepu]
        fxch    st(1)                        ; du*sstepu | du*tstepu | dv*sstepv | du | dv
        faddp   st(2), st(0)                 ; du*tstepu | du*sstepu+dv*sstepv | du | dv
        fxch    st(1)                        ; du*sstepu+dv*sstepv | du*tstepu | du | dv
        fld     st(3)                        ; dv | ...
        fmul    dword ptr [_d_tdivzstepv]
        fxch    st(1)                        ; du*sstepu+dv*sstepv | dv*tstepv | du*tstepu | du | dv
        fadd    dword ptr [_d_sdivzorigin]   ; s/z stays in st(2)
        fxch    st(4)                        ; dv | dv*tstepv | du*tstepu | du | s/z
        fmul    dword ptr [_d_zistepv]
        fxch    st(1)                        ; dv*tstepv | dv*zstepv | du*tstepu | du | s/z
        faddp   st(2), st(0)                 ; dv*zstepv | dv*tstepv+du*tstepu | du | s/z
        fxch    st(2)                        ; du | dv*tstepv+du*tstepu | dv*zstepv | s/z
        fmul    dword ptr [_d_zistepu]
        fxch    st(1)                        ; dv*tstepv+du*tstepu | du*zstepu | dv*zstepv | s/z
        fadd    dword ptr [_d_tdivzorigin]   ; t/z stays in st(1)
        fxch    st(2)                        ; dv*zstepv | du*zstepu | t/z | s/z
        faddp   st(1), st(0)                 ; dv*zstepv+du*zstepu | t/z | s/z

        fld     dword ptr [fp_64k]           ; 64k | zi_part | t/z | s/z
        fxch    st(1)                        ; zi_part | 64k | t/z | s/z
        fadd    dword ptr [_d_ziorigin]      ; zi (1/z) in st0
        fdiv    st(1), st(0)                 ; st1 = 64k / (1/z) = z*64k

; point edi to first pixel in the span
        mov     ecx, [_d_viewbuffer]
        mov     eax, [ebx+espan_t_v]
        mov     [pspantemp], ebx
        mov     edx, [_tadjust]
        mov     esi, [_sadjust]
        mov     edi, [_d_scantable+eax*4]
        add     edi, ecx
        mov     ecx, [ebx+espan_t_u]
        add     edi, ecx                     ; pdest
        mov     ecx, [ebx+espan_t_count]

; start the FDIV for the end of the span (overlap with integer work)
        cmp     ecx, 16
        ja      LSetupNotLast1
        dec     ecx
        jz      LCleanup1                    ; one pixel: no FDIV needed
        mov     [spancountminus1], ecx

        fxch    st(1)                        ; z*64k | 1/z | t/z | s/z
        fld     st(0)
        fmul    st(0), st(4)                 ; s | z*64k | 1/z | t/z | s/z
        fxch    st(1)
        fmul    st(0), st(3)                 ; t | s | 1/z | t/z | s/z
        fxch    st(1)
        fistp   dword ptr [s]                ; 1/z | t | t/z | s/z
        fistp   dword ptr [t]

        fild    dword ptr [spancountminus1]
        fld     dword ptr [_d_tdivzstepu]
        fld     dword ptr [_d_zistepu]
        fmul    st(0), st(2)                 ; zi*scm1
        fxch    st(1)
        fmul    st(0), st(2)                 ; tdiv*scm1
        fxch    st(2)
        fmul    dword ptr [_d_sdivzstepu]    ; sdiv*scm1
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(1)
        faddp   st(3), st(0)
        faddp   st(3), st(0)

        fld     dword ptr [fp_64k]
        fdiv    st(0), st(1)                 ; overlap FDIV
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

        fadd    dword ptr [zi16stepu]
        fxch    st(2)
        fadd    dword ptr [sdivz16stepu]
        fxch    st(2)
        fld     dword ptr [tdivz16stepu]
        faddp   st(2), st(0)
        fld     dword ptr [fp_64k]
        fdiv    st(0), st(1)                 ; z = 1/1/z
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
        mov     esi, [s]                     ; sfrac = s
        shl     edx, 16
        mov     eax, [t]                     ; tfrac = t
        sar     esi, 16
        mov     [tfracf], edx

; calculate the texture starting address
        sar     eax, 16
        mov     edx, [_cachewidth]
        imul    eax, edx                     ; (tfrac>>16)*cachewidth
        add     esi, ebx
        add     esi, eax                     ; psource = pbase + (sfrac>>16)+...

; determine whether last span or not
        cmp     ecx, 16
        jna     LLastSegment

; not the last segment; do full 16-wide segment
LNotLastSegment:
        fld     st(0)                        ; pick up FDIV result
        fmul    st(0), st(4)                 ; s = s/z * z
        fxch    st(1)
        fmul    st(0), st(3)                 ; t = t/z * z
        fxch    st(1)
        fistp   dword ptr [snext]
        fistp   dword ptr [tnext]
        mov     eax, [snext]
        mov     edx, [tnext]

        mov     bl, [esi]                    ; first source texel
        sub     ecx, 16                      ; count off this segment's pixels
        mov     ebp, [_sadjust]
        mov     [counttemp], ecx
        mov     ecx, [_tadjust]
        mov     [edi], bl                    ; first dest pixel
        add     ebp, eax
        add     ecx, edx
        mov     eax, [_bbextents]
        mov     edx, [_bbextentt]
        cmp     ebp, 4096
        jl      LClampLow2
        cmp     ebp, eax
        ja      LClampHigh2
LClampReentry2:
        cmp     ecx, 4096
        jl      LClampLow3
        cmp     ecx, edx
        ja      LClampHigh3
LClampReentry3:
        mov     [snext], ebp
        mov     [tnext], ecx
        sub     ebp, [s]
        sub     ecx, [t]

; set up advancetable
        mov     eax, ecx
        mov     edx, ebp
        sar     eax, 20                      ; tstep >>= 16 (16px scaling)
        jz      LZero
        sar     edx, 20                      ; sstep >>= 16
        mov     ebx, [_cachewidth]
        imul    eax, ebx
        jmp     LSetUp1
LZero:
        sar     edx, 20
        mov     ebx, [_cachewidth]
LSetUp1:
        add     eax, edx
        mov     edx, [tfracf]
        mov     [advancetable+4], eax
        add     eax, ebx
        shl     ebp, 12                      ; left-justify sstep fraction
        mov     ebx, [sfracf]
        shl     ecx, 12                      ; left-justify tstep fraction
        mov     [advancetable], eax

        mov     [tstep], ecx
        add     edx, ecx                     ; tfrac += tstep frac
        sbb     ecx, ecx                     ; carry -> -1
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     al, [esi]
        add     ebx, ebp
        mov     [edi+1], al
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+2], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+3], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+4], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+5], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+6], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+7], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

; start FDIV for end of next segment
        mov     ecx, [counttemp]
        cmp     ecx, 16
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

        fdiv    st(0), st(1)                 ; overlap FDIV
        jmp     LFDIVInFlight2

        ALIGN 4
LSetupNotLast2:
        fadd    dword ptr [zi16stepu]
        fxch    st(2)
        fadd    dword ptr [sdivz16stepu]
        fxch    st(2)
        fld     dword ptr [tdivz16stepu]
        faddp   st(2), st(0)
        fld     dword ptr [fp_64k]
        fdiv    st(0), st(1)
LFDIVInFlight2:
        mov     [counttemp], ecx

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+8], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+9], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+10], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+11], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+12], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+13], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+14], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]

        add     edi, 16
        mov     [tfracf], edx
        mov     edx, [snext]
        mov     [sfracf], ebx
        mov     ebx, [tnext]
        mov     [s], edx
        mov     [t], ebx

        mov     ecx, [counttemp]
        cmp     ecx, 16
        mov     [edi-1], al
        ja      LNotLastSegment

; last segment of scan
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

        mov     al, [esi]                    ; first texel in segment
        mov     ebx, [_tadjust]
        mov     [edi], al
        mov     eax, [_sadjust]
        add     eax, [snext]
        add     ebx, [tnext]
        mov     ebp, [_bbextents]
        mov     edx, [_bbextentt]
        cmp     eax, 4096
        jl      LClampLow4
        cmp     eax, ebp
        ja      LClampHigh4
LClampReentry4:
        mov     [snext], eax
        cmp     ebx, 4096
        jl      LClampLow5
        cmp     ebx, edx
        ja      LClampHigh5
LClampReentry5:
        cmp     ecx, 1
        je      LOnlyOneStep
        sub     eax, [s]
        sub     ebx, [t]
        add     eax, eax                     ; 15.17 format
        add     ebx, ebx
        imul    eax, [reciprocal_table_16+ecx*4-8]   ; sstep
        mov     ebp, edx
        mov     eax, ebx
        imul    eax, [reciprocal_table_16+ecx*4-8]   ; tstep

LSetEntryvec:
        mov     ebx, [entryvec_table_16+ecx*4]
        mov     edx, eax
        mov     [jumptemp], ebx
        mov     ecx, ebp
        sar     edx, 16                      ; tstep >>= 16
        mov     ebx, [_cachewidth]
        sar     ecx, 16                      ; sstep >>= 16
        imul    edx, ebx
        add     edx, ecx
        mov     ecx, [tfracf]
        mov     [advancetable+4], edx
        add     edx, ebx
        shl     ebp, 16                      ; left-justify sstep frac
        mov     ebx, [sfracf]
        shl     eax, 16                      ; left-justify tstep frac
        mov     [advancetable], edx
        mov     [tstep], eax
        mov     edx, ecx
        add     edx, eax
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        jmp     dword ptr [jumptemp]

LNoSteps:
        mov     al, [esi]
        sub     edi, 15                      ; adjust for hardwired offset
        jmp     LEndSpan

LOnlyOneStep:
        sub     eax, [s]
        sub     ebx, [t]
        mov     ebp, eax
        mov     edx, ebx
        jmp     LSetEntryvec

;------------------------------------------------------------------------------
; last-segment pixel-count handlers (entered via jumptemp; RET returns to caller)
;------------------------------------------------------------------------------
Entry2_16:
        sub     edi, 14
        mov     al, [esi]
        jmp     LEntry2_16
Entry3_16:
        sub     edi, 13
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        jmp     LEntry3_16
Entry4_16:
        sub     edi, 12
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry4_16
Entry5_16:
        sub     edi, 11
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry5_16
Entry6_16:
        sub     edi, 10
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry6_16
Entry7_16:
        sub     edi, 9
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry7_16
Entry8_16:
        sub     edi, 8
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry8_16
Entry9_16:
        sub     edi, 7
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry9_16
Entry10_16:
        sub     edi, 6
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry10_16
Entry11_16:
        sub     edi, 5
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry11_16
Entry12_16:
        sub     edi, 4
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry12_16
Entry13_16:
        sub     edi, 3
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry13_16
Entry14_16:
        sub     edi, 2
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry14_16
Entry15_16:
        dec     edi
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LEntry15_16
Entry16_16:
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        sbb     ecx, ecx
        mov     [edi+1], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry15_16:
        sbb     ecx, ecx
        mov     [edi+2], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry14_16:
        sbb     ecx, ecx
        mov     [edi+3], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry13_16:
        sbb     ecx, ecx
        mov     [edi+4], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry12_16:
        sbb     ecx, ecx
        mov     [edi+5], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry11_16:
        sbb     ecx, ecx
        mov     [edi+6], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry10_16:
        sbb     ecx, ecx
        mov     [edi+7], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry9_16:
        sbb     ecx, ecx
        mov     [edi+8], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry8_16:
        sbb     ecx, ecx
        mov     [edi+9], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry7_16:
        sbb     ecx, ecx
        mov     [edi+10], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry6_16:
        sbb     ecx, ecx
        mov     [edi+11], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry5_16:
        sbb     ecx, ecx
        mov     [edi+12], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LEntry4_16:
        sbb     ecx, ecx
        mov     [edi+13], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
LEntry3_16:
        mov     [edi+14], al
        mov     al, [esi]
LEntry2_16:

LEndSpan:
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)
        mov     ebx, [pspantemp]
        mov     ebx, [ebx+espan_t_pnext]
        test    ebx, ebx
        mov     [edi+15], al
        jnz     LSpanLoop

        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret
D_DrawSpans16_ endp

;=============================================================================
; Translation notes:
;
; 1. Nearly identical to d_draw.s (already verified) but with 16-pixel
;    subdivision: fp_16, *16stepu globals, reciprocal_table_16,
;    entryvec_table_16, 15 Entry points, clamp-low=4096, SAR 20 / SHL 12,
;    and 16 pixel stores per full segment. All FPU/addressing mappings are
;    the same verified ones from math/d_polysa/d_draw.
;
; 2. Watcom register ABI: arg in EAX; callee-saved EBX/ECX/EDX/ESI/EDI/EBP
;    preserved. Stack arg pspans(%esp) replaced with EAX->EBX.
;
; 3. No ZSpans routine here, so the SHLD+ROR 486 optimization from d_draw.asm
;    does not apply to this file.
;=============================================================================

end
