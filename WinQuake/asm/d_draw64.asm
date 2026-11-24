;=============================================================================
; d_draw32.asm - 8-bpp horizontal span-drawing code, 64-pixel subdivision
;
; 486 / AMD Am5x86 / AMD K5 optimized MASM (OpenWatcom wasm) version.
; Self-contained data tables (no changes needed to d_varsa.asm).
; One routine + 31 entry points:
;   D_DrawSpans64  (arg EAX = espan_t *pspans) - textured spans, 64-px segments
;   Entry2_64 .. Entry64_64 - jump targets for last-segment pixel counts
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
public  D_DrawSpans64_
public  Entry2_64, Entry3_64, Entry4_64, Entry5_64, Entry6_64, Entry7_64
public  Entry8_64, Entry9_64, Entry10_64, Entry11_64, Entry12_64, Entry13_64
public  Entry14_64, Entry15_64, Entry16_64, Entry17_64, Entry18_64, Entry19_64
public  Entry20_64, Entry21_64, Entry22_64, Entry23_64, Entry24_64, Entry25_64
public  Entry26_64, Entry27_64, Entry28_64, Entry29_64, Entry30_64, Entry31_64
public  Entry32_64, Entry33_64, Entry34_64, Entry35_64, Entry36_64, Entry37_64
public  Entry38_64, Entry39_64, Entry40_64, Entry41_64, Entry42_64, Entry43_64
public  Entry44_64, Entry45_64, Entry46_64, Entry47_64, Entry48_64, Entry49_64
public  Entry50_64, Entry51_64, Entry52_64, Entry53_64, Entry54_64, Entry55_64
public  Entry56_64, Entry57_64, Entry58_64, Entry59_64, Entry60_64, Entry61_64
public  Entry62_64, Entry63_64, Entry64_64

.data
        ALIGN 4
fp_64           dd 042800000h           ; 64.0f in IEEE-754
zi64stepu       dd 0
sdivz64stepu    dd 0
tdivz64stepu    dd 0

; 1/n for n=2..64 in signed 1.31 form (same scale as reciprocal_table_16):
;   [ecx*4-8] -> 2^31 / ecx;  add eax,eax makes the imul yield 16.48.
reciprocal_table_64:
        dd 0x40000000h, 0x2AAAAAAAh, 0x20000000h, 0x19999999h
        dd 0x15555555h, 0x12492492h, 0x10000000h, 0x0E38E38Eh
        dd 0x0CCCCCCCh, 0x0BA2E8BAh, 0x0AAAAAAAh, 0x09D89D89h
        dd 0x09249249h, 0x08888888h, 0x08000000h, 0x07878787h
        dd 0x071C71C7h, 0x06BCA1AFh, 0x06666666h, 0x06186186h
        dd 0x05D1745Dh, 0x0590B216h, 0x05555555h, 0x051EB851h
        dd 0x04EC4EC4h, 0x04BDA12Fh, 0x04924924h, 0x0469EE58h
        dd 0x04444444h, 0x04210842h, 0x04000000h, 0x03E0F83Eh
        dd 0x03C3C3C3h, 0x03A83A83h, 0x038E38E3h, 0x03759F22h
        dd 0x035E50D7h, 0x03483483h, 0x03333333h, 0x031F3831h
        dd 0x030C30C3h, 0x02FA0BE8h, 0x02E8BA2Eh, 0x02D82D82h
        dd 0x02C8590Bh, 0x02B93105h, 0x02AAAAAAh, 0x029CBC14h
        dd 0x028F5C28h, 0x02828282h, 0x02762762h, 0x026A439Fh
        dd 0x025ED097h, 0x0253C825h, 0x02492492h, 0x023EE08Fh
        dd 0x0234F72Ch, 0x022B63CBh, 0x02222222h, 0x02192E29h
        dd 0x02108421h, 0x02082082h, 0x02000000h

; entryvec_table_64[ecx] -> Entry(ecx+1)_64, matching d_draw32.
; index 0 is unused (ecx==0 is handled by the direct jz LNoSteps).
entryvec_table_64:
        dd 0, Entry2_64, Entry3_64, Entry4_64, Entry5_64
        dd Entry6_64, Entry7_64, Entry8_64, Entry9_64, Entry10_64
        dd Entry11_64, Entry12_64, Entry13_64, Entry14_64, Entry15_64
        dd Entry16_64, Entry17_64, Entry18_64, Entry19_64, Entry20_64
        dd Entry21_64, Entry22_64, Entry23_64, Entry24_64, Entry25_64
        dd Entry26_64, Entry27_64, Entry28_64, Entry29_64, Entry30_64
        dd Entry31_64, Entry32_64, Entry33_64, Entry34_64, Entry35_64
        dd Entry36_64, Entry37_64, Entry38_64, Entry39_64, Entry40_64
        dd Entry41_64, Entry42_64, Entry43_64, Entry44_64, Entry45_64
        dd Entry46_64, Entry47_64, Entry48_64, Entry49_64, Entry50_64
        dd Entry51_64, Entry52_64, Entry53_64, Entry54_64, Entry55_64
        dd Entry56_64, Entry57_64, Entry58_64, Entry59_64, Entry60_64
        dd Entry61_64, Entry62_64, Entry63_64, Entry64_64

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
; D_DrawSpans64_  -- 64-px perspective-subdivided textured spans
; C: void D_DrawSpans64(espan_t *pspans)  -- pspans in EAX
;=============================================================================
        ALIGN 4
D_DrawSpans64_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx                     ; callee-saved, clobbered as scratch
        push    edx                     ; callee-saved, clobbered as scratch
        mov     ebx, eax                ; point to first span descriptor

; set up scaled-by-64 steps and cacheblock / span list pointers
        fld     dword ptr [_d_sdivzstepu]
        fmul    dword ptr [fp_64]
        mov     edx, [_cacheblock]
        fld     dword ptr [_d_tdivzstepu]
        fmul    dword ptr [fp_64]
        fld     dword ptr [_d_zistepu]
        fmul    dword ptr [fp_64]
        mov     [pbase], edx
        fstp    dword ptr [zi64stepu]
        fstp    dword ptr [tdivz64stepu]
        fstp    dword ptr [sdivz64stepu]

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
        cmp     ecx, 64
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

        fadd    dword ptr [zi64stepu]
        fxch    st(2)
        fadd    dword ptr [sdivz64stepu]
        fxch    st(2)
        fld     dword ptr [tdivz64stepu]
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
		cmp     ecx, 64
		jna     LLastSegment
		; not the last segment; do full 64-wide segment
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
		sub     ecx, 64                      ; count off this segment's pixels
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
; set up advancetable (64-px scaling: sar 21, shl 11)
		mov     eax, ecx
		mov     edx, ebp
		sar     eax, 22                      ; tstep >>= 16 (64px scaling)
		jz      LZero
		sar     edx, 22                      ; sstep >>= 16
		mov     ebx, [_cachewidth]
		imul    eax, ebx
		jmp     LSetUp1
LZero:
		sar     edx, 22
		mov     ebx, [_cachewidth]
LSetUp1:
		add     eax, edx
		mov     edx, [tfracf]
		mov     [advancetable+4], eax
		add     eax, ebx
		shl     ebp, 10                      ; left-justify sstep fraction
		mov     ebx, [sfracf]
		shl     ecx, 10                      ; left-justify tstep fraction
		mov     [advancetable], eax
		mov     [tstep], ecx
		add     edx, ecx                     ; tfrac += tstep frac
		sbb     ecx, ecx                     ; carry -> -1
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
; pixels 1..31 (32 integer pixels before launching next segment's FDIV)
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
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+31], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
; start FDIV for end of next segment (overlaps with pixels 16..31)
		mov     ecx, [counttemp]
		cmp     ecx, 64
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
		fadd    dword ptr [zi64stepu]
		fxch    st(2)
		fadd    dword ptr [sdivz64stepu]
		fxch    st(2)
		fld     dword ptr [tdivz64stepu]
		faddp   st(2), st(0)
		fld     dword ptr [fp_64k]
		fdiv    st(0), st(1)
LFDIVInFlight2:
		mov     [counttemp], ecx
; pixels 32..62
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+32], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+33], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+34], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+35], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+36], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+37], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+38], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+39], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+40], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+41], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+42], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+43], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+44], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+45], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+46], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+47], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+48], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+49], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+50], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+51], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+52], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+53], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+54], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+55], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+56], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+57], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+58], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+59], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+60], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+61], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		sbb     ecx, ecx
		mov     [edi+62], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edi, 64
		mov     [tfracf], edx
		mov     edx, [snext]
		mov     [sfracf], ebx
		mov     ebx, [tnext]
		mov     [s], edx
		mov     [t], ebx
		mov     ecx, [counttemp]
		cmp     ecx, 64
		mov     [edi-1], al
		ja      LNotLastSegment
; last segment of scan (1..64 pixels)
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
		imul    dword ptr [reciprocal_table_64+ecx*4-8]   ; EDX:EAX = sstep
		mov     ebp, edx
		mov     eax, ebx
		imul    dword ptr [reciprocal_table_64+ecx*4-8]   ; EDX:EAX = tstep
LSetEntryvec:
		mov     ebx, [entryvec_table_64+ecx*4]
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
		sub     edi, 63                      ; adjust for [edi+63] store at LEndSpan
		jmp     LEndSpan
LOnlyOneStep:
		sub     eax, [s]
		sub     ebx, [t]
		mov     ebp, eax
		mov     edx, ebx
		jmp     LSetEntryvec
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; last-segment pixel-count handlers (Entry2_64 .. Entry64_64)
;------------------------------------------------------------------------------
Entry2_64:
		sub     edi, 62
		mov     al, [esi]
		jmp     LEntry2_64
Entry3_64:
		sub     edi, 61
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry3_64
Entry4_64:
		sub     edi, 60
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry4_64
Entry5_64:
		sub     edi, 59
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry5_64
Entry6_64:
		sub     edi, 58
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry6_64
Entry7_64:
		sub     edi, 57
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry7_64
Entry8_64:
		sub     edi, 56
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry8_64
Entry9_64:
		sub     edi, 55
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry9_64
Entry10_64:
		sub     edi, 54
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry10_64
Entry11_64:
		sub     edi, 53
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry11_64
Entry12_64:
		sub     edi, 52
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry12_64
Entry13_64:
		sub     edi, 51
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry13_64
Entry14_64:
		sub     edi, 50
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry14_64
Entry15_64:
		sub     edi, 49
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry15_64
Entry16_64:
		sub     edi, 48
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry16_64
Entry17_64:
		sub     edi, 47
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry17_64
Entry18_64:
		sub     edi, 46
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry18_64
Entry19_64:
		sub     edi, 45
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry19_64
Entry20_64:
		sub     edi, 44
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry20_64
Entry21_64:
		sub     edi, 43
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry21_64
Entry22_64:
		sub     edi, 42
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry22_64
Entry23_64:
		sub     edi, 41
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry23_64
Entry24_64:
		sub     edi, 40
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry24_64
Entry25_64:
		sub     edi, 39
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry25_64
Entry26_64:
		sub     edi, 38
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry26_64
Entry27_64:
		sub     edi, 37
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry27_64
Entry28_64:
		sub     edi, 36
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry28_64
Entry29_64:
		sub     edi, 35
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry29_64
Entry30_64:
		sub     edi, 34
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry30_64
Entry31_64:
		sub     edi, 33
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry31_64
Entry32_64:
		sub     edi, 32
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry32_64
Entry33_64:
		sub     edi, 31
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry33_64
Entry34_64:
		sub     edi, 30
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry34_64
Entry35_64:
		sub     edi, 29
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry35_64
Entry36_64:
		sub     edi, 28
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry36_64
Entry37_64:
		sub     edi, 27
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry37_64
Entry38_64:
		sub     edi, 26
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry38_64
Entry39_64:
		sub     edi, 25
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry39_64
Entry40_64:
		sub     edi, 24
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry40_64
Entry41_64:
		sub     edi, 23
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry41_64
Entry42_64:
		sub     edi, 22
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry42_64
Entry43_64:
		sub     edi, 21
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry43_64
Entry44_64:
		sub     edi, 20
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry44_64
Entry45_64:
		sub     edi, 19
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry45_64
Entry46_64:
		sub     edi, 18
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry46_64
Entry47_64:
		sub     edi, 17
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry47_64
Entry48_64:
		sub     edi, 16
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry48_64
Entry49_64:
		sub     edi, 15
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry49_64
Entry50_64:
		sub     edi, 14
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry50_64
Entry51_64:
		sub     edi, 13
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry51_64
Entry52_64:
		sub     edi, 12
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry52_64
Entry53_64:
		sub     edi, 11
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry53_64
Entry54_64:
		sub     edi, 10
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry54_64
Entry55_64:
		sub     edi, 9
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry55_64
Entry56_64:
		sub     edi, 8
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry56_64
Entry57_64:
		sub     edi, 7
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry57_64
Entry58_64:
		sub     edi, 6
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry58_64
Entry59_64:
		sub     edi, 5
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry59_64
Entry60_64:
		sub     edi, 4
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry60_64
Entry61_64:
		sub     edi, 3
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry61_64
Entry62_64:
		sub     edi, 2
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry62_64
Entry63_64:
		sub     edi, 1
		add     edx, eax
		mov     al, [esi]
		sbb     ecx, ecx
		add     ebx, ebp
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
		jmp     LEntry63_64
Entry64_64:
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
LEntry63_64:
		sbb     ecx, ecx
		mov     [edi+2], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry62_64:
		sbb     ecx, ecx
		mov     [edi+3], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry61_64:
		sbb     ecx, ecx
		mov     [edi+4], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry60_64:
		sbb     ecx, ecx
		mov     [edi+5], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry59_64:
		sbb     ecx, ecx
		mov     [edi+6], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry58_64:
		sbb     ecx, ecx
		mov     [edi+7], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry57_64:
		sbb     ecx, ecx
		mov     [edi+8], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry56_64:
		sbb     ecx, ecx
		mov     [edi+9], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry55_64:
		sbb     ecx, ecx
		mov     [edi+10], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry54_64:
		sbb     ecx, ecx
		mov     [edi+11], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry53_64:
		sbb     ecx, ecx
		mov     [edi+12], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry52_64:
		sbb     ecx, ecx
		mov     [edi+13], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry51_64:
		sbb     ecx, ecx
		mov     [edi+14], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry50_64:
		sbb     ecx, ecx
		mov     [edi+15], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry49_64:
		sbb     ecx, ecx
		mov     [edi+16], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry48_64:
		sbb     ecx, ecx
		mov     [edi+17], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry47_64:
		sbb     ecx, ecx
		mov     [edi+18], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry46_64:
		sbb     ecx, ecx
		mov     [edi+19], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry45_64:
		sbb     ecx, ecx
		mov     [edi+20], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry44_64:
		sbb     ecx, ecx
		mov     [edi+21], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry43_64:
		sbb     ecx, ecx
		mov     [edi+22], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry42_64:
		sbb     ecx, ecx
		mov     [edi+23], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry41_64:
		sbb     ecx, ecx
		mov     [edi+24], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry40_64:
		sbb     ecx, ecx
		mov     [edi+25], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry39_64:
		sbb     ecx, ecx
		mov     [edi+26], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry38_64:
		sbb     ecx, ecx
		mov     [edi+27], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry37_64:
		sbb     ecx, ecx
		mov     [edi+28], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry36_64:
		sbb     ecx, ecx
		mov     [edi+29], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry35_64:
		sbb     ecx, ecx
		mov     [edi+30], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry34_64:
		sbb     ecx, ecx
		mov     [edi+31], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry33_64:
		sbb     ecx, ecx
		mov     [edi+32], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry32_64:
		sbb     ecx, ecx
		mov     [edi+33], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry31_64:
		sbb     ecx, ecx
		mov     [edi+34], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry30_64:
		sbb     ecx, ecx
		mov     [edi+35], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry29_64:
		sbb     ecx, ecx
		mov     [edi+36], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry28_64:
		sbb     ecx, ecx
		mov     [edi+37], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry27_64:
		sbb     ecx, ecx
		mov     [edi+38], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry26_64:
		sbb     ecx, ecx
		mov     [edi+39], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry25_64:
		sbb     ecx, ecx
		mov     [edi+40], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry24_64:
		sbb     ecx, ecx
		mov     [edi+41], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry23_64:
		sbb     ecx, ecx
		mov     [edi+42], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry22_64:
		sbb     ecx, ecx
		mov     [edi+43], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry21_64:
		sbb     ecx, ecx
		mov     [edi+44], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry20_64:
		sbb     ecx, ecx
		mov     [edi+45], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry19_64:
		sbb     ecx, ecx
		mov     [edi+46], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry18_64:
		sbb     ecx, ecx
		mov     [edi+47], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry17_64:
		sbb     ecx, ecx
		mov     [edi+48], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry16_64:
		sbb     ecx, ecx
		mov     [edi+49], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry15_64:
		sbb     ecx, ecx
		mov     [edi+50], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry14_64:
		sbb     ecx, ecx
		mov     [edi+51], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry13_64:
		sbb     ecx, ecx
		mov     [edi+52], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry12_64:
		sbb     ecx, ecx
		mov     [edi+53], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry11_64:
		sbb     ecx, ecx
		mov     [edi+54], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry10_64:
		sbb     ecx, ecx
		mov     [edi+55], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry9_64:
		sbb     ecx, ecx
		mov     [edi+56], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry8_64:
		sbb     ecx, ecx
		mov     [edi+57], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry7_64:
		sbb     ecx, ecx
		mov     [edi+58], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry6_64:
		sbb     ecx, ecx
		mov     [edi+59], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry5_64:
		sbb     ecx, ecx
		mov     [edi+60], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry4_64:
		sbb     ecx, ecx
		mov     [edi+61], al
		add     ebx, ebp
		mov     al, [esi]
		adc     esi, [advancetable+4+ecx*4]
		add     edx, [tstep]
LEntry3_64:
		mov     [edi+62], al
		mov     al, [esi]
LEntry2_64:
LEndSpan:
		fstp    st(0)
		fstp    st(0)
		fstp    st(0)
		mov     ebx, [pspantemp]
		mov     ebx, [ebx+espan_t_pnext]
		test    ebx, ebx
		mov     [edi+63], al
		jnz     LSpanLoop
		pop     edx
		pop     ecx
		pop     ebx
		pop     esi
		pop     edi
		pop     ebp
		ret
D_DrawSpans64_ endp

end
