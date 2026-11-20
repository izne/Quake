;=============================================================================
; d_draw.asm - x86 assembly-language horizontal 8-bpp span-drawing code
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/d_draw.s.
; Two routines + 7 entry points:
;   D_DrawSpans8   (arg EAX = espan_t *pspans) - textured spans
;   Entry2_8 .. Entry8_8 - jump targets for last-segment pixel counts
;   D_DrawZSpans   (arg EAX = espan_t *pzspans) - z-buffer spans
;
; Calling convention (Watcom 32-bit register ABI, verified by probe):
;   EAX volatile; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> all preserved.
;   C data: leading underscore (_d_sdivzstepu). ASM-only: plain (fp_8, pbase).
;
; gas mangled names like _d_sdivzstepu) are C(d_sdivzstepu) artifacts -> plain.
;
; FPU mapping (derived from stack comments, verified in d_polysa/math.asm):
;   faddp %st(0),%st(N) -> faddp st(N),st(0)
;   fdivr %st(0),%st(1) -> fdiv   st(1),st(0)   (st1 = st1/st0)
;   fdiv  %st(1),%st(0) -> fdiv   st(0),st(1)   (st0 = st0/st1)
;   fmul  %st(a),%st(0) -> fmul   st(0),st(a)
;   fcoms mem           -> fcom   dword ptr [mem]   (no pop)
;
; 486 OPTIMIZATIONS applied (see OPT notes inline):
;   - Z-span dword packing uses SHLD+ROR instead of MOV+AND+OR, eliminating
;     the scratch regs the original flagged with 'FIXME: register contention'.
;=============================================================================

.386
.model  small

; ---- espan_t offsets --------------------------------------------------------
espan_t_u       equ 0
espan_t_v       equ 4
espan_t_count   equ 8
espan_t_pnext   equ 12
espan_t_size    equ 16

; ---- C globals (leading underscore) ----------------------------------------
extrn   _d_sdivzstepu:dword, _d_tdivzstepu:dword, _d_zistepu:dword
extrn   _d_sdivzstepv:dword, _d_tdivzstepv:dword, _d_zistepv:dword
extrn   _d_sdivzorigin:dword, _d_tdivzorigin:dword, _d_ziorigin:dword
extrn   _cacheblock:dword, _cachewidth:dword, _sadjust:dword, _tadjust:dword
extrn   _bbextents:dword, _bbextentt:dword, _d_viewbuffer:dword
extrn   _d_scantable:dword, _d_pzbuffer:dword, _d_zrowbytes:dword

; ---- ASM-only globals (plain names, from d_varsa/r_varsa) -------------------
extrn   fp_8:dword, fp_64k:dword, float_point5:dword
extrn   Float2ToThe31nd:dword, FloatMinus2ToThe31nd:dword
extrn   pbase:dword, zi8stepu:dword, sdivz8stepu:dword, tdivz8stepu:dword
extrn   s:dword, t:dword, snext:dword, tnext:dword, spancountminus1:dword
extrn   sfracf:dword, tfracf:dword, pspantemp:dword, counttemp:dword
extrn   jumptemp:dword, advancetable:dword, tstep:dword
extrn   reciprocal_table:dword, entryvec_table:dword
extrn   izistep:dword, izi:dword

; ---- exports ----------------------------------------------------------------
public  D_DrawSpans8_
public  Entry2_8, Entry3_8, Entry4_8, Entry5_8, Entry6_8, Entry7_8, Entry8_8
public  D_DrawZSpans_

.code

;------------------------------------------------------------------------------
; out-of-line, rarely-needed clamping code (textured spans)
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
        mov     ebp, 2048
        jmp     LClampReentry2
LClampHigh2:
        mov     ebp, [_bbextents]
        jmp     LClampReentry2

LClampLow3:
        mov     ecx, 2048
        jmp     LClampReentry3
LClampHigh3:
        mov     ecx, [_bbextentt]
        jmp     LClampReentry3

LClampLow4:
        mov     eax, 2048
        jmp     LClampReentry4
LClampHigh4:
        mov     eax, [_bbextents]
        jmp     LClampReentry4

LClampLow5:
        mov     ebx, 2048
        jmp     LClampReentry5
LClampHigh5:
        mov     ebx, [_bbextentt]
        jmp     LClampReentry5


;=============================================================================
; D_DrawSpans8_  (was: _D_DrawSpans8)  -- 8-bpp textured spans
; C: void D_DrawSpans8(espan_t *pspans)  -- pspans in EAX
;=============================================================================
D_DrawSpans8_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx                     ; callee-saved, clobbered as scratch
        push    edx                     ; callee-saved, clobbered as scratch
        mov     ebx, eax                ; point to the first span descriptor

; set up scaled-by-8 steps and cacheblock / span list pointers
        fld     dword ptr [_d_sdivzstepu]
        fmul    dword ptr [fp_8]
        mov     edx, [_cacheblock]
        fld     dword ptr [_d_tdivzstepu]
        fmul    dword ptr [fp_8]
        fld     dword ptr [_d_zistepu]
        fmul    dword ptr [fp_8]
        mov     [pbase], edx
        fstp    dword ptr [zi8stepu]
        fstp    dword ptr [tdivz8stepu]
        fstp    dword ptr [sdivz8stepu]

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
        cmp     ecx, 8
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

        fadd    dword ptr [zi8stepu]
        fxch    st(2)
        fadd    dword ptr [sdivz8stepu]
        fxch    st(2)
        fld     dword ptr [tdivz8stepu]
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
        add     esi, eax                     ; psource = pbase + (sfrac>>16) + ...

; determine whether last span or not
        cmp     ecx, 8
        jna     LLastSegment

; not the last segment; do full 8-wide segment
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
        sub     ecx, 8
        mov     ebp, [_sadjust]
        mov     [counttemp], ecx
        mov     ecx, [_tadjust]
        mov     [edi], bl                    ; first dest pixel
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

; set up advancetable
        mov     eax, ecx
        mov     edx, ebp
        sar     eax, 19                      ; tstep >>= 16 (signed)
        jz      LZero
        sar     edx, 19                      ; sstep >>= 16
        mov     ebx, [_cachewidth]
        imul    eax, ebx
        jmp     LSetUp1
LZero:
        sar     edx, 19
        mov     ebx, [_cachewidth]
LSetUp1:
        add     eax, edx
        mov     edx, [tfracf]
        mov     [advancetable+4], eax
        add     eax, ebx
        shl     ebp, 13                      ; left-justify sstep fraction
        mov     ebx, [sfracf]
        shl     ecx, 13                      ; left-justify tstep fraction
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

; start FDIV for end of next segment
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

        fdiv    st(0), st(1)                 ; overlap FDIV
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

        add     edi, 8
        mov     [tfracf], edx
        mov     edx, [snext]
        mov     [sfracf], ebx
        mov     ebx, [tnext]
        mov     [s], edx
        mov     [t], ebx

        mov     ecx, [counttemp]
        cmp     ecx, 8
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
        cmp     eax, 2048
        jl      LClampLow4
        cmp     eax, ebp
        ja      LClampHigh4
LClampReentry4:
        mov     [snext], eax
        cmp     ebx, 2048
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
        imul    dword ptr [reciprocal_table+ecx*4-8]   ; EDX:EAX = sstep
        mov     ebp, edx
        mov     eax, ebx
        imul    dword ptr [reciprocal_table+ecx*4-8]   ; EDX:EAX = tstep

LSetEntryvec:
        mov     ebx, [entryvec_table+ecx*4]
        mov     eax, edx
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
        sub     edi, 7
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
Entry2_8:
        sub     edi, 6
        mov     al, [esi]
        jmp     LLEntry2_8

Entry3_8:
        sub     edi, 5
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        jmp     LLEntry3_8

Entry4_8:
        sub     edi, 4
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LLEntry4_8

Entry5_8:
        sub     edi, 3
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LLEntry5_8

Entry6_8:
        sub     edi, 2
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LLEntry6_8

Entry7_8:
        dec     edi
        add     edx, eax
        mov     al, [esi]
        sbb     ecx, ecx
        add     ebx, ebp
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
        jmp     LLEntry7_8

Entry8_8:
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
LLEntry7_8:
        sbb     ecx, ecx
        mov     [edi+2], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LLEntry6_8:
        sbb     ecx, ecx
        mov     [edi+3], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LLEntry5_8:
        sbb     ecx, ecx
        mov     [edi+4], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
        add     edx, [tstep]
LLEntry4_8:
        sbb     ecx, ecx
        mov     [edi+5], al
        add     ebx, ebp
        mov     al, [esi]
        adc     esi, [advancetable+4+ecx*4]
LLEntry3_8:
        mov     [edi+6], al
        mov     al, [esi]
LLEntry2_8:

LEndSpan:
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)
        mov     ebx, [pspantemp]
        mov     ebx, [ebx+espan_t_pnext]
        test    ebx, ebx
        mov     [edi+7], al
        jnz     LSpanLoop

        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret
D_DrawSpans8_ endp


;=============================================================================
; D_DrawZSpans_  (was: _D_DrawZSpans)  -- z-buffer spans
; C: void D_DrawZSpans(espan_t *pzspans)  -- pzspans in EAX
;=============================================================================
; z-clamp on a non-negative gradient span
LClamp:
        mov     edx, 040000000h
        xor     ebx, ebx
        fstp    st(0)
        jmp     LZDraw

LClampNeg:
        mov     edx, 040000000h
        xor     ebx, ebx
        fstp    st(0)
        jmp     LZDrawNeg

D_DrawZSpans_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx                     ; callee-saved, clobbered as scratch
        push    edx                     ; callee-saved, clobbered as scratch
        mov     esi, eax                ; pzspans

        fld     dword ptr [_d_zistepu]
        mov     eax, [_d_zistepu]
        test    eax, eax
        jz      LFNegSpan

        fmul    dword ptr [Float2ToThe31nd]
        fistp   dword ptr [izistep]
        mov     ebx, [izistep]

LFSpanLoop:
        fild    dword ptr [esi+espan_t_v]
        fild    dword ptr [esi+espan_t_u]
        mov     ecx, [esi+espan_t_v]
        mov     edi, [_d_pzbuffer]
        fmul    dword ptr [_d_zistepu]
        fxch    st(1)
        fmul    dword ptr [_d_zistepv]
        fxch    st(1)
        fadd    dword ptr [_d_ziorigin]
        imul    ecx, [_d_zrowbytes]
        faddp   st(1), st(0)

        fcom    dword ptr [float_point5]
        add     edi, ecx
        mov     edx, [esi+espan_t_u]
        add     edx, edx                     ; word count
        mov     ecx, [esi+espan_t_count]
        add     edi, edx                     ; pdest
        push    esi
        fnstsw  ax
        test    ah, 045h
        jz      LClamp

        fmul    dword ptr [Float2ToThe31nd]
        fistp   dword ptr [izi]
        mov     edx, [izi]

; ebx=izistep, ecx=count, edx=izi, edi=pdest
LZDraw:
; single pixel up front to dword-align destination
        test    edi, 2
        jz      LFMiddle
        mov     eax, edx
        add     edx, ebx
        shr     eax, 16
        dec     ecx
        mov     [edi], ax
        add     edi, 2

; middle: aligned dwords, two pixels each
LFMiddle:
        push    ecx
        shr     ecx, 1
        jz      LFLast
        shr     ecx, 1
        jnc     LFMiddleLoop

; odd number of dwords: do one first (cold path - keep original and/or)
        mov     eax, edx
        add     edx, ebx
        shr     eax, 16
        mov     esi, edx
        add     edx, ebx
        and     esi, 0FFFF0000h
        or      eax, esi
        mov     [edi], eax
        add     edi, 4
        test    ecx, ecx
        jz      LFLast

LFMiddleLoop:
; 486 OPT: pack two 16-bit z values per dword via SHLD+ROR, avoiding the
; MOV/AND/OR scratch chain (original's 'FIXME: register contention').
        mov     eax, edx                 ; v0
        add     edx, ebx                 ; v1
        shr     eax, 16                  ; low word = v0>>16
        shld    eax, edx, 16             ; = (v0>>16)<<16 | (v1>>16)  [words swapped]
        ror     eax, 16                  ; = (v1>>16)<<16 | (v0>>16)
        mov     [edi], eax
        add     edx, ebx                 ; v2

        mov     eax, edx                 ; v2
        add     edx, ebx                 ; v3
        shr     eax, 16
        shld    eax, edx, 16
        ror     eax, 16
        mov     [edi+4], eax
        add     edi, 8
        add     edx, ebx                 ; v4

        dec     ecx
        jnz     LFMiddleLoop

LFLast:
        pop     ecx
        pop     esi
        and     ecx, 1
        jz      LFSpanDone
        shr     edx, 16
        mov     [edi], dx

LFSpanDone:
        mov     esi, [esi+espan_t_pnext]
        test    esi, esi
        jnz     LFSpanLoop
        jmp     LFDone

; negative-gradient path
LFNegSpan:
        fmul    dword ptr [FloatMinus2ToThe31nd]
        fistp   dword ptr [izistep]
        mov     ebx, [izistep]

LFNegSpanLoop:
        fild    dword ptr [esi+espan_t_v]
        fild    dword ptr [esi+espan_t_u]
        mov     ecx, [esi+espan_t_v]
        mov     edi, [_d_pzbuffer]
        fmul    dword ptr [_d_zistepu]
        fxch    st(1)
        fmul    dword ptr [_d_zistepv]
        fxch    st(1)
        fadd    dword ptr [_d_ziorigin]
        imul    ecx, [_d_zrowbytes]
        faddp   st(1), st(0)

        fcom    dword ptr [float_point5]
        add     edi, ecx
        mov     edx, [esi+espan_t_u]
        add     edx, edx
        mov     ecx, [esi+espan_t_count]
        add     edi, edx
        push    esi
        fnstsw  ax
        test    ah, 045h
        jz      LClampNeg

        fmul    dword ptr [Float2ToThe31nd]
        fistp   dword ptr [izi]
        mov     edx, [izi]

LZDrawNeg:
        test    edi, 2
        jz      LFNegMiddle
        mov     eax, edx
        sub     edx, ebx
        shr     eax, 16
        dec     ecx
        mov     [edi], ax
        add     edi, 2

LFNegMiddle:
        push    ecx
        shr     ecx, 1
        jz      LFNegLast
        shr     ecx, 1
        jnc     LFNegMiddleLoop

        mov     eax, edx
        sub     edx, ebx
        shr     eax, 16
        mov     esi, edx
        sub     edx, ebx
        and     esi, 0FFFF0000h
        or      eax, esi
        mov     [edi], eax
        add     edi, 4
        test    ecx, ecx
        jz      LFNegLast

LFNegMiddleLoop:
; 486 OPT: SHLD+ROR packing (negative step variant)
        mov     eax, edx
        sub     edx, ebx
        shr     eax, 16
        shld    eax, edx, 16
        ror     eax, 16
        mov     [edi], eax
        sub     edx, ebx

        mov     eax, edx
        sub     edx, ebx
        shr     eax, 16
        shld    eax, edx, 16
        ror     eax, 16
        mov     [edi+4], eax
        add     edi, 8
        sub     edx, ebx

        dec     ecx
        jnz     LFNegMiddleLoop

LFNegLast:
        pop     ecx
        pop     esi
        and     ecx, 1
        jz      LFNegSpanDone
        shr     edx, 16
        mov     [edi], dx

LFNegSpanDone:
        mov     esi, [esi+espan_t_pnext]
        test    esi, esi
        jnz     LFNegSpanLoop

LFDone:
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret
D_DrawZSpans_ endp

;=============================================================================
; Translation notes:
;
; 1. CALLING CONVENTION: Watcom register ABI. Both functions take one pointer
;    arg in EAX; all callee-saved regs (EBX/ECX/EDX/ESI/EDI/EBP) preserved.
;    The original's stack arg at pspans(%esp)=[esp+20] is replaced with EAX->EBX.
;
; 2. FPU: FDIV-overlap structure preserved exactly. gas fdiv/fdivr two-reg
;    forms reversed per AT&T->Intel (fdivr %st(0),%st(1) -> fdiv st(1),st(0)).
;
; 3. 486 OPT (Z-span inner loops): original packed two 16-bit z values into a
;    dword using 'mov edx,esi; and esi,0FFFF0000h; or eax,esi' and carried two
;    scratch regs (esi/ebp) - explicitly flagged 'FIXME: eliminate register
;    contention'. Replaced with SHLD+ROR: 'shld eax,edx,16; ror eax,16' packs
;    the same two values with no scratch regs and one fewer uop. Verified
;    bit-exact against a C oracle over 9 cases (positive/negative gradients,
;    aligned/unaligned starts, odd/even counts, clamping). SHLD is 386+ / fast
;    on 486.
;
; 4. VERIFICATION: D_DrawZSpans fully functionally verified (9 cases). All FPU
;    operand encodings cross-checked via disassembly + focused tests: gas AT&T
;    'fdivr %st(0),%st(1)' -> MASM 'fdiv st(1),st(0)' (st1=st1/st0), and gas
;    'fdiv %st(1),%st(0)' -> MASM 'fdiv st(0),st(1)' (st0=st0/st1). D_DrawSpans8's
;    full pixel pipeline needs the engine's exact cache/span state to exercise,
;    but its FPU sequences use the same mappings verified in math/d_polysa.
;
; 5. ALIGN: gas '.align 4' = 16-byte align; WASM here uses ALIGN 4 (segment
;    alignment limit in this toolchain) - correctness-neutral fetch hint.
;=============================================================================

end
