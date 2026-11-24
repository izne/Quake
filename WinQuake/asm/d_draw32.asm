;=============================================================================
; d_draw32.asm - 8-bpp horizontal span-drawing code, 32-pixel subdivision
;
; 486 / AMD Am5x86 / AMD K5 optimized MASM (OpenWatcom wasm) version.
; Self-contained data tables (no changes needed to d_varsa.asm).
; One routine + 31 entry points:
;   D_DrawSpans32  (arg EAX = espan_t *pspans) - textured spans, 32-px segments
;   Entry2_32 .. Entry32_32 - jump targets for last-segment pixel counts
;
; Calling convention (Watcom 32-bit register ABI):
;   EAX volatile; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> all preserved.
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

; ---- Shared ASM-only globals from d_varsa.asm (plain names) -----------------
extrn   fp_64k:dword
extrn   pbase:dword
extrn   s:dword, t:dword, snext:dword, tnext:dword, spancountminus1:dword
extrn   sfracf:dword, tfracf:dword, pspantemp:dword, counttemp:dword
extrn   jumptemp:dword, advancetable:dword, tstep:dword

; ---- exports ----------------------------------------------------------------
public  D_DrawSpans32_
public  Entry2_32, Entry3_32, Entry4_32, Entry5_32, Entry6_32, Entry7_32
public  Entry8_32, Entry9_32, Entry10_32, Entry11_32, Entry12_32
public  Entry13_32, Entry14_32, Entry15_32, Entry16_32, Entry17_32
public  Entry18_32, Entry19_32, Entry20_32, Entry21_32, Entry22_32
public  Entry23_32, Entry24_32, Entry25_32, Entry26_32, Entry27_32
public  Entry28_32, Entry29_32, Entry30_32, Entry31_32, Entry32_32

.data
        ALIGN 4
fp_32           dd 042000000h           ; 32.0f in IEEE-754
zi32stepu       dd 0
sdivz32stepu    dd 0
tdivz32stepu    dd 0

; 1/n for n=2..32 in signed 1.31 form (same scale as reciprocal_table_16):
;   [ecx*4-8] -> 2^31 / ecx;  add eax,eax makes the imul yield 16.48.
reciprocal_table_32:
        dd 040000000h, 02aaaaaaah, 020000000h
        dd 019999999h, 015555555h, 012492492h
        dd 010000000h, 00e38e38eh, 00ccccccch, 00ba2e8bah
        dd 0aaaaaaah, 09d89d89h, 09249249h, 08888888h
        dd 08000000h, 07878787h, 071c71c7h, 06bca1afh
        dd 06666666h, 06186186h, 05d1745dh, 0590b216h
        dd 05555555h, 051eb851h, 04ec4ec4h, 04bda12fh
        dd 04924924h, 0469ee58h, 04444444h, 04210842h
        dd 04000000h

; entryvec_table_32[ecx] -> Entry(ecx+1)_32, matching d_draw16.
; index 0 is unused (ecx==0 is handled by the direct jz LNoSteps).
entryvec_table_32:
        dd 0, Entry2_32,  Entry3_32,  Entry4_32,  Entry5_32
        dd Entry6_32,  Entry7_32,  Entry8_32,  Entry9_32
        dd Entry10_32, Entry11_32, Entry12_32, Entry13_32
        dd Entry14_32, Entry15_32, Entry16_32, Entry17_32
        dd Entry18_32, Entry19_32, Entry20_32, Entry21_32
        dd Entry22_32, Entry23_32, Entry24_32, Entry25_32
        dd Entry26_32, Entry27_32, Entry28_32, Entry29_32
        dd Entry30_32, Entry31_32, Entry32_32

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
; D_DrawSpans32_  -- 32-px perspective-subdivided textured spans
; C: void D_DrawSpans32(espan_t *pspans)  -- pspans in EAX
;=============================================================================
        ALIGN 4
D_DrawSpans32_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx                     ; callee-saved, clobbered as scratch
        push    edx                     ; callee-saved, clobbered as scratch
        mov     ebx, eax                ; point to first span descriptor

; set up scaled-by-32 steps and cacheblock / span list pointers
        fld     dword ptr [_d_sdivzstepu]
        fmul    dword ptr [fp_32]
        mov     edx, [_cacheblock]
        fld     dword ptr [_d_tdivzstepu]
        fmul    dword ptr [fp_32]
        fld     dword ptr [_d_zistepu]
        fmul    dword ptr [fp_32]
        mov     [pbase], edx
        fstp    dword ptr [zi32stepu]
        fstp    dword ptr [tdivz32stepu]
        fstp    dword ptr [sdivz32stepu]

        ALIGN 4
LSpanLoop:
; initial s/z, t/z, 1/z on FP stack (1 fxch instead of 13)
        fild    dword ptr [ebx+espan_t_u]    ; du
        fild    dword ptr [ebx+espan_t_v]    ; dv | du

; 1. Compute s/z -> stack: s/z | dv | du
        fld     st(1)                        ; du | dv | du
        fmul    dword ptr [_d_sdivzstepu]    ; du*su | dv | du
        fld     st(1)                        ; dv | du*su | dv | du
        fmul    dword ptr [_d_sdivzstepv]    ; dv*sv | du*su | dv | du
        faddp   st(1), st(0)                 ; s_part | dv | du
        fadd    dword ptr [_d_sdivzorigin]   ; s/z | dv | du

; 2. Compute t/z -> stack: t/z | s/z | dv | du
        fld     st(2)                        ; du | s/z | dv | du
        fmul    dword ptr [_d_tdivzstepu]    ; du*tu | s/z | dv | du
        fld     st(2)                        ; dv | du*tu | s/z | dv | du
        fmul    dword ptr [_d_tdivzstepv]    ; dv*tv | du*tu | s/z | dv | du
        faddp   st(1), st(0)                 ; t_part | s/z | dv | du
        fadd    dword ptr [_d_tdivzorigin]   ; t/z | s/z | dv | du

; 3. Compute 1/z consuming du and dv -> stack: 1/z | t/z | s/z
        fld     st(3)                        ; du | t/z | s/z | dv | du
        fmul    dword ptr [_d_zistepu]       ; du*zu | t/z | s/z | dv | du
        fadd    dword ptr [_d_ziorigin]      ; du*zu+zi0 | t/z | s/z | dv | du
        fstp    st(4)                        ; t/z | s/z | dv | 1/z_part
        fld     st(2)                        ; dv | t/z | s/z | dv | 1/z_part
        fmul    dword ptr [_d_zistepv]       ; dv*zv | t/z | s/z | dv | 1/z_part
        faddp   st(4), st(0)                 ; t/z | s/z | dv | 1/z
        fstp    st(2)                        ; s/z | t/z | 1/z
        fxch    st(2)                        ; 1/z | t/z | s/z

        fld     dword ptr [fp_64k]           ; 64k | 1/z | t/z | s/z
        fdiv    st(0), st(1)                 ; z*64k | 1/z | t/z | s/z

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
        cmp     ecx, 32
        ja      LSetupNotLast1
        sub     ecx, 1
        jz      LCleanup1                    ; one pixel: no FDIV needed
        mov     [spancountminus1], ecx

        fld     st(0)                        ; z*64k | z*64k | 1/z | t/z | s/z
        fmul    st(0), st(3)                 ; t | z*64k | 1/z | t/z | s/z
        fistp   dword ptr [t]                ; z*64k | 1/z | t/z | s/z
        fmul    st(0), st(3)                 ; s | 1/z | t/z | s/z
        fistp   dword ptr [s]                ; 1/z | t/z | s/z

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

        ALIGN 4
LCleanup1:
        fld     st(0)
        fmul    st(0), st(3)                 ; t
        fistp   dword ptr [t]
        fmul    st(0), st(3)                 ; s
        fistp   dword ptr [s]
        jmp     LFDIVInFlight1

        ALIGN 4
LSetupNotLast1:
        fld     st(0)
        fmul    st(0), st(3)                 ; t
        fistp   dword ptr [t]
        fmul    st(0), st(3)                 ; s
        fistp   dword ptr [s]

        fadd    dword ptr [zi32stepu]
        fxch    st(2)
        fadd    dword ptr [sdivz32stepu]
        fxch    st(2)
        fld     dword ptr [tdivz32stepu]
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
		cmp     ecx, 32
		jna     LLastSegment
		; not the last segment; do full 32-wide segment
		ALIGN 4
LNotLastSegment:
		fld     st(0)                        ; z | z | zi | t/z | s/z
		fmul    st(0), st(3)                 ; t | z | zi | t/z | s/z
		fistp   dword ptr [tnext]            ; z | zi | t/z | s/z
		fmul    st(0), st(3)                 ; s | zi | t/z | s/z
		fistp   dword ptr [snext]            ; zi | t/z | s/z
		mov     eax, [snext]
		mov     edx, [tnext]
		mov     bl, [esi]                    ; first source texel
		sub     ecx, 32                      ; count off this segment's pixels
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
; set up advancetable (32-px scaling: sar 21, shl 11)
		mov     eax, ecx
		mov     edx, ebp
		sar     eax, 21                      ; tstep >>= 16 (32px scaling)
		jz      LZero
		sar     edx, 21                      ; sstep >>= 16
		mov     ebx, [_cachewidth]
		imul    eax, ebx
		jmp     LSetUp1
LZero:
		sar     edx, 21
		mov     ebx, [_cachewidth]
LSetUp1:
		add     eax, edx
		mov     edx, [tfracf]
		mov     [advancetable+4], eax
		add     eax, ebx
		shl     ebp, 11                      ; left-justify sstep fraction
		mov     ebx, [sfracf]
		shl     ecx, 11                      ; left-justify tstep fraction
		mov     [advancetable], eax
		mov     [tstep], ecx
		add     edx, ecx                     ; tfrac += tstep frac
		sbb     ecx, ecx                     ; carry -> -1
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
; pixels 1..15 (16 integer pixels before launching next segment's FDIV)
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
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+15], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
; start FDIV for end of next segment (overlaps with pixels 16..31)
		mov     ecx, [counttemp]
		cmp     ecx, 32
		ja      LSetupNotLast2
		sub     ecx, 1
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
		fadd    dword ptr [zi32stepu]
		fxch    st(2)
		fadd    dword ptr [sdivz32stepu]
		fxch    st(2)
		fld     dword ptr [tdivz32stepu]
		faddp   st(2), st(0)
		fld     dword ptr [fp_64k]
		fdiv    st(0), st(1)
LFDIVInFlight2:
		mov     [counttemp], ecx
; pixels 16..31
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+16], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+17], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+18], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+19], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+20], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+21], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+22], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+23], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+24], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+25], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+26], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+27], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+28], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+29], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+30], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edi, 32
		mov     [tfracf], edx
		mov     edx, [snext]
		mov     [sfracf], ebx
		mov     ebx, [tnext]
		mov     [s], edx
		mov     [t], ebx
		mov     ecx, [counttemp]
		cmp     ecx, 32
		mov     [edi-1], al
		ja      LNotLastSegment
; last segment of scan (1..32 pixels)
		ALIGN 4
LLastSegment:
		test    ecx, ecx
		jz      LNoSteps
		fld     st(0)
		fmul    st(0), st(3)
		fistp   dword ptr [tnext]
		fmul    st(0), st(3)
		fistp   dword ptr [snext]
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
		imul    dword ptr [reciprocal_table_32+ecx*4-8]   ; EDX:EAX = sstep
		mov     ebp, edx
		mov     eax, ebx
		imul    dword ptr [reciprocal_table_32+ecx*4-8]   ; EDX:EAX = tstep
LSetEntryvec:
		mov     ebx, [entryvec_table_32+ecx*4]
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
		sub     edi, 31                      ; adjust for [edi+31] store at LEndSpan
		jmp     LEndSpan
LOnlyOneStep:
		sub     eax, [s]
		sub     ebx, [t]
		mov     ebp, eax
		mov     edx, ebx
		jmp     LSetEntryvec
;------------------------------------------------------------------------------
; last-segment pixel-count handlers (Entry2_32 .. Entry32_32)
;------------------------------------------------------------------------------
Entry2_32:
		sub     edi, 30
		mov     al, [esi]
		jmp     LEntry2_32
Entry3_32:
		sub     edi, 29
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		jmp     LEntry3_32
Entry4_32:
		sub     edi, 28
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry4_32
Entry5_32:
		sub     edi, 27
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry5_32
Entry6_32:
		sub     edi, 26
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry6_32
Entry7_32:
		sub     edi, 25
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry7_32
Entry8_32:
		sub     edi, 24
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry8_32
Entry9_32:
		sub     edi, 23
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry9_32
Entry10_32:
		sub     edi, 22
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry10_32
Entry11_32:
		sub     edi, 21
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry11_32
Entry12_32:
		sub     edi, 20
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry12_32
Entry13_32:
		sub     edi, 19
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry13_32
Entry14_32:
		sub     edi, 18
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry14_32
Entry15_32:
		sub     edi, 17
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry15_32
Entry16_32:
		sub     edi, 16
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry16_32
Entry17_32:
		sub     edi, 15
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry17_32
Entry18_32:
		sub     edi, 14
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry18_32
Entry19_32:
		sub     edi, 13
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry19_32
Entry20_32:
		sub     edi, 12
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry20_32
Entry21_32:
		sub     edi, 11
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry21_32
Entry22_32:
		sub     edi, 10
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry22_32
Entry23_32:
		sub     edi, 9
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry23_32
Entry24_32:
		sub     edi, 8
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry24_32
Entry25_32:
		sub     edi, 7
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry25_32
Entry26_32:
		sub     edi, 6
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry26_32
Entry27_32:
		sub     edi, 5
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry27_32
Entry28_32:
		sub     edi, 4
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry28_32
Entry29_32:
		sub     edi, 3
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry29_32
Entry30_32:
		sub     edi, 2
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry30_32
Entry31_32:
		sub     edi, 1
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry31_32
Entry32_32:
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
LEntry31_32:
		sbb     ecx, ecx
		mov     [edi+2], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry30_32:
		sbb     ecx, ecx
		mov     [edi+3], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry29_32:
		sbb     ecx, ecx
		mov     [edi+4], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry28_32:
		sbb     ecx, ecx
		mov     [edi+5], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry27_32:
		sbb     ecx, ecx
		mov     [edi+6], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry26_32:
		sbb     ecx, ecx
		mov     [edi+7], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry25_32:
		sbb     ecx, ecx
		mov     [edi+8], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry24_32:
		sbb     ecx, ecx
		mov     [edi+9], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry23_32:
		sbb     ecx, ecx
		mov     [edi+10], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry22_32:
		sbb     ecx, ecx
		mov     [edi+11], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry21_32:
		sbb     ecx, ecx
		mov     [edi+12], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry20_32:
		sbb     ecx, ecx
		mov     [edi+13], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry19_32:
		sbb     ecx, ecx
		mov     [edi+14], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry18_32:
		sbb     ecx, ecx
		mov     [edi+15], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry17_32:
		sbb     ecx, ecx
		mov     [edi+16], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry16_32:
		sbb     ecx, ecx
		mov     [edi+17], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry15_32:
		sbb     ecx, ecx
		mov     [edi+18], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry14_32:
		sbb     ecx, ecx
		mov     [edi+19], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry13_32:
		sbb     ecx, ecx
		mov     [edi+20], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry12_32:
		sbb     ecx, ecx
		mov     [edi+21], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry11_32:
		sbb     ecx, ecx
		mov     [edi+22], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry10_32:
		sbb     ecx, ecx
		mov     [edi+23], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry9_32:
		sbb     ecx, ecx
		mov     [edi+24], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry8_32:
		sbb     ecx, ecx
		mov     [edi+25], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry7_32:
		sbb     ecx, ecx
		mov     [edi+26], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry6_32:
		sbb     ecx, ecx
		mov     [edi+27], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry5_32:
		sbb     ecx, ecx
		mov     [edi+28], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry4_32:
		sbb     ecx, ecx
		mov     [edi+29], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
LEntry3_32:
		mov     [edi+30], al
		mov     al, [esi]
LEntry2_32:
LEndSpan:
		fstp    st(0)
		fstp    st(0)
		fstp    st(0)
		mov     ebx, [pspantemp]
		mov     ebx, [ebx+espan_t_pnext]
		test    ebx, ebx
		mov     [edi+31], al
		jnz     LSpanLoop
		pop     edx
		pop     ecx
		pop     ebx
		pop     esi
		pop     edi
		pop     ebp
		ret
D_DrawSpans32_ endp

end