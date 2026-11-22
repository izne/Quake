;=============================================================================
; d_polysa.asm - x86 assembly-language polygon model drawing code
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/d_polysa.s.
; Nine functions:
;   D_PolysetCalcGradients       (1 arg EAX)
;   D_PolysetRecursiveTriangle   (stdcall stack args, ret 12 - asm-internal)
;   D_PolysetAff8Start/End       (code-range labels for self-modifying patch)
;   D_PolysetDrawSpans8          (1 arg EAX)
;   D_Aff8Patch                  (1 arg EAX)
;   D_PolysetDraw                (void)
;   D_PolysetScanLeftEdge        (1 arg EAX)
;   D_PolysetDrawFinalVerts      (2 args EAX, EDX)
;   D_DrawNonSubdiv              (void, tail-called from D_PolysetDraw)
;
; CALLING CONVENTION (Watcom 32-bit register ABI, verified by probe):
;   EAX = volatile; EBX/ECX/EDX/ESI/EDI/EBP are callee-saved.
;   GPR args: EAX(arg1), EDX(arg2), EBX(arg3), ECX(arg4).
;   C data uses leading underscore (_r_p0); C functions trailing (_name).
;
; FPU gas->MASM mapping (verified against math.asm functional tests and the
; detailed stack-state comments in the original source):
;   fsubp  %st(0),%st(N) -> fsubrp st(N),st(0)   (gas swaps sub/subr!)
;   fsubrp %st(0),%st(N) -> fsubp  st(N),st(0)
;   faddp  %st(0),%st(N) -> faddp  st(N),st(0)
;   fmulp  %st(0),%st(N) -> fmulp  st(N),st(0)
;=============================================================================

.386
.model  small

; ---- constants -------------------------------------------------------------
SPAN_SIZE       equ (1024+1+1+1)*32     ; 32864
CACHE_SIZE      equ 32
ALIAS_ONSEAM    equ 020h

; spanpackage_t offsets
spanpackage_t_pdest  equ 0
spanpackage_t_pz     equ 4
spanpackage_t_count  equ 8
spanpackage_t_ptex   equ 12
spanpackage_t_sfrac  equ 16
spanpackage_t_tfrac  equ 20
spanpackage_t_light  equ 24
spanpackage_t_zi     equ 28
spanpackage_t_size   equ 32

; finalvert_t offsets
fv_v             equ 0
fv_flags         equ 24
fv_size          equ 32

; mtriangle_t offsets
mtri_facesfront  equ 0
mtri_vertindex   equ 4
mtri_size        equ 16
mtri_shift       equ 4

; affinetridesc_t offsets
atd_skinwidth    equ 8
atd_ptriangles   equ 16
atd_pfinalverts  equ 20
atd_numtriangles equ 24
atd_drawtype     equ 28
atd_seamfixupX16 equ 32

; refdef_t offsets
rd_vrectright    equ 40
rd_vrectbottom   equ 44

; ---- C functions (trailing underscore) ------------------------------------
extrn   D_PolysetSetEdgeTable_:near
extrn   D_RasterizeAliasPolySmooth_:near

; ---- C globals (leading underscore) ---------------------------------------
extrn   _r_p0:dword, _r_p1:dword, _r_p2:dword
extrn   _d_xdenom:dword
extrn   _r_lstepx:dword, _r_lstepy:dword
extrn   _r_sstepx:dword, _r_sstepy:dword
extrn   _r_tstepx:dword, _r_tstepy:dword
extrn   _r_zistepx:dword, _r_zistepy:dword
extrn   _a_sstepxfrac:dword, _a_tstepxfrac:dword, _a_ststepxwhole:dword
extrn   _r_affinetridesc:dword
extrn   _d_pcolormap:dword, _acolormap:dword
extrn   _a_spans:dword
extrn   _d_aspancount:dword, _errorterm:dword
extrn   _erroradjustup:dword, _erroradjustdown:dword, _d_countextrastep:dword
extrn   _ubasestep:dword
extrn   _d_pedgespanpackage:dword
extrn   _d_pdest:dword, _d_pz:dword, _d_ptex:dword
extrn   _d_sfrac:dword, _d_tfrac:dword, _d_light:dword, _d_zi:dword
extrn   _d_pdestextrastep:dword, _d_pdestbasestep:dword
extrn   _d_pzextrastep:dword, _d_pzbasestep:dword
extrn   _d_ptexextrastep:dword, _d_ptexbasestep:dword
extrn   _d_sfracextrastep:dword, _d_sfracbasestep:dword
extrn   _d_tfracextrastep:dword, _d_tfracbasestep:dword
extrn   _d_lightextrastep:dword, _d_lightbasestep:dword
extrn   _d_ziextrastep:dword, _d_zibasestep:dword
extrn   _zspantable:dword, _d_scantable:dword, _d_viewbuffer:dword
extrn   _skintable:dword, _r_refdef:dword
extrn   _ceil_cw:word, _single_cw:word

; ---- ASM-only globals from other files (plain names) ----------------------
extrn   advancetable:dword, tstep:dword
extrn   float_1:dword, float_minus_1:dword

; ---- exported functions ----------------------------------------------------
public  D_PolysetCalcGradients_
public  D_PolysetRecursiveTriangle_
public  D_PolysetAff8Start_, D_PolysetAff8End_
public  D_PolysetDrawSpans8_
public  D_Aff8Patch_
public  D_PolysetDraw_
public  D_PolysetScanLeftEdge_
public  D_PolysetDrawFinalVerts_
public  D_DrawNonSubdiv_

.data

    ALIGN 4
p10_minus_p20       dd 0.0
p01_minus_p21       dd 0.0
temp0               dd 0.0
temp1               dd 0.0
Ltemp               dd 0.0

aff8entryvec_table  dd LDraw8, LDraw7, LDraw6, LDraw5
                    dd LDraw4, LDraw3, LDraw2, LDraw1

lzistepx            dd 0

.code

;=============================================================================
; D_PolysetCalcGradients_  (was: _D_PolysetCalcGradients)
; C: void D_PolysetCalcGradients(int skinwidth)   -- skinwidth in EAX
; Preserves ECX, EDX (callee-saved); saves EAX arg on stack.
; The gas source's detailed stack comments are reproduced verbatim for audit.
;=============================================================================
D_PolysetCalcGradients_ proc near
        push    ecx                 ; callee-saved
        push    edx                 ; callee-saved
        push    eax                 ; save skinwidth -> [esp] (gas used [esp+4])

; p00_minus_p20 = r_p0[0]-r_p2[0]; p01_minus_p21 = r_p0[1]-r_p2[1]; etc.
        fild    dword ptr [_r_p0+0]          ; r_p0[0]
        fild    dword ptr [_r_p2+0]          ; r_p2[0] | r_p0[0]
        fild    dword ptr [_r_p0+4]          ; r_p0[1] | r_p2[0] | r_p0[0]
        fild    dword ptr [_r_p2+4]          ; r_p2[1] | r_p0[1] | r_p2[0] | r_p0[0]
        fild    dword ptr [_r_p1+0]          ; r_p1[0] | r_p2[1] | r_p0[1] | r_p2[0] | r_p0[0]
        fild    dword ptr [_r_p1+4]          ; r_p1[1] | r_p1[0] | r_p2[1] | r_p0[1] | ...
        fxch    st(3)                        ; r_p0[1] | r_p1[0] | r_p2[1] | r_p1[1] | ...
        fsub    st(0), st(2)                 ; p01_minus_p21 | ...
        fxch    st(1)                        ; r_p1[0] | p01_minus_p21 | ...
        fsub    st(0), st(4)                 ; p10_minus_p20 | p01_minus_p21 | ...
        fxch    st(5)                        ; r_p0[0] | p01_minus_p21 | r_p2[1] | r_p1[1] | r_p2[0] | p10
        fsubrp  st(4), st(0)                 ; => st4 = st0 - st4 = p00_minus_p20 ; pop
        fxch    st(2)                        ; r_p1[1] | r_p2[1] | p01 | p00 | p10
        fsubrp  st(1), st(0)                 ; => st1 = st0 - st1 = p11_minus_p21 ; pop
        fxch    st(1)                        ; p01 | p11 | p00 | p10
        fld     dword ptr [_d_xdenom]        ; d_xdenom | p01 | p11 | p00 | p10
        fxch    st(4)                        ; p10 | p01 | p11 | p00 | d_xdenom
        fstp    dword ptr [p10_minus_p20]
        fstp    dword ptr [p01_minus_p21]
        fxch    st(2)                        ; xstepdenominv | p00 | p11

; ceil() for light: t0 = r_p0[4]-r_p2[4]; t1 = r_p1[4]-r_p2[4]
        fild    dword ptr [_r_p2+16]
        fild    dword ptr [_r_p0+16]
        fild    dword ptr [_r_p1+16]
        fxch    st(2)
        fld     st(0)
        fsubp   st(2), st(0)                 ; t0
        fsubp   st(2), st(0)                 ; t1

        fld     st(0)
        fmul    st(0), st(5)                 ; t0*p11_minus_p21
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [p01_minus_p21]    ; t1*p01_minus_p21
        fxch    st(2)
        fmul    dword ptr [p10_minus_p20]    ; t0*p10_minus_p20
        fxch    st(1)
        fmul    st(0), st(5)                 ; t1*p00_minus_p20
        fxch    st(2)
        fsubrp  st(3), st(0)                 ; st3 = st0 - st3
        fsubp   st(1), st(0)                 ; st1 = st1 - st0
        fld     st(2)
        fmul    dword ptr [float_minus_1]    ; ystepdenominv
        fxch    st(2)
        fmul    st(0), st(3)
        fxch    st(1)
        fmul    st(0), st(2)
        fldcw   _ceil_cw
        fistp   dword ptr [_r_lstepy]
        fistp   dword ptr [_r_lstepx]
        fldcw   _single_cw

; s steps: t0 = r_p0[2]-r_p2[2]; t1 = r_p1[2]-r_p2[2]
        fild    dword ptr [_r_p2+8]
        fild    dword ptr [_r_p0+8]
        fild    dword ptr [_r_p1+8]
        fxch    st(2)
        fld     st(0)
        fsubp   st(2), st(0)
        fsubp   st(2), st(0)
        fld     st(0)
        fmul    st(0), st(6)
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [p01_minus_p21]
        fxch    st(2)
        fmul    dword ptr [p10_minus_p20]
        fxch    st(1)
        fmul    st(0), st(6)
        fxch    st(2)
        fsubrp  st(3), st(0)
        fsubp   st(1), st(0)
        fmul    st(0), st(2)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(1)
        fistp   dword ptr [_r_sstepy]
        fistp   dword ptr [_r_sstepx]

; t steps: t0 = r_p0[3]-r_p2[3]; t1 = r_p1[3]-r_p2[3]
        fild    dword ptr [_r_p2+12]
        fild    dword ptr [_r_p0+12]
        fild    dword ptr [_r_p1+12]
        fxch    st(2)
        fld     st(0)
        fsubp   st(2), st(0)
        fsubp   st(2), st(0)
        fld     st(0)
        fmul    st(0), st(6)
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [p01_minus_p21]
        fxch    st(2)
        fmul    dword ptr [p10_minus_p20]
        fxch    st(1)
        fmul    st(0), st(6)
        fxch    st(2)
        fsubrp  st(3), st(0)
        fsubp   st(1), st(0)
        fmul    st(0), st(2)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(1)
        fistp   dword ptr [_r_tstepy]
        fistp   dword ptr [_r_tstepx]

; iz steps: t0 = r_p0[5]-r_p2[5]; t1 = r_p1[5]-r_p2[5]
        fild    dword ptr [_r_p2+20]
        fild    dword ptr [_r_p0+20]
        fild    dword ptr [_r_p1+20]
        fxch    st(2)
        fld     st(0)
        fsubp   st(2), st(0)
        fsubp   st(2), st(0)
        fld     st(0)
        fmulp   st(6), st(0)
        fxch    st(1)
        fld     st(0)
        fmul    dword ptr [p01_minus_p21]
        fxch    st(2)
        fmul    dword ptr [p10_minus_p20]
        fxch    st(1)
        fmulp   st(5), st(0)
        fxch    st(5)
        fsubp   st(1), st(0)
        fxch    st(3)
        fsubrp  st(4), st(0)
        fxch    st(1)
        fmulp   st(2), st(0)
        fmulp   st(2), st(0)
        fistp   dword ptr [_r_zistepx]
        fistp   dword ptr [_r_zistepy]

; a_sstepxfrac = r_sstepx<<16; a_tstepxfrac = r_tstepx<<16
; a_ststepxwhole = skinwidth*(r_tstepx>>16) + (r_sstepx>>16)
        mov     eax, [_r_sstepx]
        mov     edx, [_r_tstepx]
        shl     eax, 16
        shl     edx, 16
        mov     [_a_sstepxfrac], eax
        mov     [_a_tstepxfrac], edx

        mov     ecx, [_r_sstepx]
        mov     eax, [_r_tstepx]
        sar     ecx, 16
        sar     eax, 16
        imul    eax, [esp]              ; * skinwidth (saved arg)
        add     eax, ecx
        mov     [_a_ststepxwhole], eax

        pop     eax
        pop     edx
        pop     ecx
        ret
D_PolysetCalcGradients_ endp


;=============================================================================
; D_PolysetRecursiveTriangle_  (was: _D_PolysetRecursiveTriangle)
; NOT C-callable: uses stdcall return (ret 12) and stack args.
; Args: lp1=[esp+20], lp2=[esp+24], lp3=[esp+28] (after 4 reg pushes).
; Preserves EBX/ESI/EDI/EBP (gas pushes) + ECX/EDX (Watcom callee-saved).
;=============================================================================
D_PolysetRecursiveTriangle_ proc near
        push    ebp
        push    esi
        push    edi
        push    ebx
        mov     esi, [esp+24]           ; lp2
        mov     ebx, [esp+20]           ; lp1
        mov     edi, [esp+28]           ; lp3
        push    ecx                     ; callee-saved
        push    edx                     ; callee-saved

; d = lp2[0]-lp1[0]; if (d < -1 || d > 1) goto split
        mov     eax, [esi+0]
        mov     edx, [ebx+0]
        mov     ebp, [esi+4]
        sub     eax, edx
        mov     ecx, [ebx+4]
        sub     ebp, ecx
        inc     eax
        cmp     eax, 2
        ja      LSplit

        mov     eax, [edi+0]
        inc     ebp
        cmp     ebp, 2
        ja      LSplit

; d = lp3[0]-lp2[0]
        mov     edx, [esi+0]
        mov     ebp, [edi+4]
        sub     eax, edx
        mov     ecx, [esi+4]
        sub     ebp, ecx
        inc     eax
        cmp     eax, 2
        ja      LSplit2

; d = lp3[1]-lp2[1]
        mov     eax, [ebx+0]
        inc     ebp
        cmp     ebp, 2
        ja      LSplit2

; d = lp1[0]-lp3[0]
        mov     edx, [edi+0]
        mov     ebp, [ebx+4]
        sub     eax, edx
        mov     ecx, [edi+4]
        sub     ebp, ecx
        inc     eax
        inc     ebp
        mov     edx, ebx
        cmp     eax, 2
        ja      LSplit3

; d = lp1[1]-lp3[1]
        cmp     ebp, 2
        jna     LDone

LSplit3:
        mov     ebx, edi
        mov     edi, esi
        mov     esi, edx
        jmp     LSplit

LSplit2:
        mov     eax, ebx
        mov     ebx, esi
        mov     esi, edi
        mov     edi, eax

LSplit:
        sub     esp, 24                 ; allocate new[6]

; new[0..5] = (lp1[k]+lp2[k]) >> 1  (for k=2,3,5,0,1)
        mov     eax, [ebx+8]
        mov     edx, [esi+8]
        mov     ecx, [ebx+12]
        add     eax, edx
        mov     edx, [esi+12]
        sar     eax, 1
        add     ecx, edx
        mov     [esp+8], eax
        mov     eax, [ebx+20]
        sar     ecx, 1
        mov     edx, [esi+20]
        mov     [esp+12], ecx
        add     eax, edx
        mov     ecx, [ebx+0]
        mov     edx, [esi+0]
        sar     eax, 1
        add     edx, ecx
        mov     [esp+20], eax
        sar     edx, 1
        mov     eax, [ebx+4]
        mov     [esp+0], edx
        mov     ebp, [esi+4]
        add     ebp, eax
        sar     ebp, 1
        mov     [esp+4], ebp

; if (lp2[1] > lp1[1]) goto nodraw
        cmp     [esi+4], eax
        jg      LNoDraw
        mov     edx, [esi+0]
        jnz     LDraw
        cmp     edx, ecx
        jl      LNoDraw

LDraw:
        mov     edx, [esp+20]           ; z = new[5]>>16
        mov     ecx, [esp+4]            ; new[1]
        sar     edx, 16
        mov     ebp, [esp+0]            ; new[0]
        mov     eax, [_zspantable+ecx*4]
        cmp dx, [eax+ebp*2]
        jnge    LNoDraw
        mov     [eax+ebp*2], dx
        mov     eax, [esp+12]           ; new[3]>>16
        sar     eax, 16
        mov     edx, [esp+8]            ; new[2]>>16
        sar     edx, 16
        xor     ecx, ecx
        mov     eax, [_skintable+eax*4]
        mov     ebp, [esp+4]
        mov     cl, [eax+edx]
        mov     edx, [_d_pcolormap]
        mov     dl, [edx+ecx]
        mov     ecx, [esp+0]
        mov     eax, [_d_scantable+ebp*4]
        add     eax, ecx
        mov     ecx, [_d_viewbuffer]
        mov     [ecx+eax], dl

LNoDraw:
; D_PolysetRecursiveTriangle(lp3, lp1, new)
        push    esp
        push    ebx
        push    edi
        call    D_PolysetRecursiveTriangle_
; D_PolysetRecursiveTriangle(lp3, new, lp2)
        mov     ebx, esp
        push    esi
        push    ebx
        push    edi
        call    D_PolysetRecursiveTriangle_
        add     esp, 24

LDone:
        pop     edx
        pop     ecx
        pop     ebx
        pop     edi
        pop     esi
        pop     ebp
        ret     12
D_PolysetRecursiveTriangle_ endp


;=============================================================================
; 8-bpp horizontal span drawing code for affine polygons
;=============================================================================
public  D_PolysetAff8Start_
D_PolysetAff8Start_:

;=============================================================================
; D_PolysetDrawSpans8_  (was: _D_PolysetDrawSpans8)
; C: void D_PolysetDrawSpans8(spanpackage_t *pspanpackage) -- arg in EAX
;=============================================================================
D_PolysetDrawSpans8_ proc near
        ; Watcom __watcall callee-saved: EBX/ECX/EDX/ESI/EDI/EBP.  ECX and
        ; EDX are used as scratch in this routine, so they must be preserved.
        push    eax                     ; save pspanpackage arg
        push    ecx
        push    edx
        push    esi
        push    ebx
        mov     esi, [esp+16]           ; pspanpackage (saved EAX)
        mov     ecx, [_r_zistepx]

        push    ebp
        push    edi

        ror     ecx, 16                 ; high 16 bits of 1/z step in low word
        mov     edx, [esi+spanpackage_t_count]
        mov     [lzistepx], ecx

LSpanLoop:
; lcount = d_aspancount - pspanpackage->count; errorterm adjustment
        mov     eax, [_d_aspancount]
        sub     eax, edx
        mov     edx, [_erroradjustup]
        mov     ebx, [_errorterm]
        add     ebx, edx
        js      LNoTurnover
        mov     edx, [_erroradjustdown]
        mov     edi, [_d_countextrastep]
        sub     ebx, edx
        mov     ebp, [_d_aspancount]
        mov     [_errorterm], ebx
        add     ebp, edi
        mov     [_d_aspancount], ebp
        jmp     LRightEdgeStepped

LNoTurnover:
        mov     edi, [_d_aspancount]
        mov     edx, [_ubasestep]
        mov     [_errorterm], ebx
        add     edi, edx
        mov     [_d_aspancount], edi

LRightEdgeStepped:
        cmp     eax, 1
        jl      LNextSpan
        jz      LExactlyOneLong

; set up advancetable
        mov     ecx, [_a_ststepxwhole]
        mov     edx, [_r_affinetridesc+atd_skinwidth]
        mov     [advancetable+4], ecx
        add     ecx, edx
        mov     [advancetable], ecx
        mov     ecx, [_a_tstepxfrac]
        mov     cx, word ptr [_r_lstepx]
        mov     edx, eax                 ; count
        mov     [tstep], ecx
        add     edx, 7
        shr     edx, 3                   ; count of full and partial loops
        mov     ebx, [esi+spanpackage_t_sfrac]
        mov     bx, dx
        mov     ecx, [esi+spanpackage_t_pz]
        neg     eax
        mov     edi, [esi+spanpackage_t_pdest]
        and     eax, 7                   ; 0->0, 1->7, ..., 7->1
        sub     edi, eax
        sub     ecx, eax
        sub     ecx, eax
        mov     edx, [esi+spanpackage_t_tfrac]
        mov     dx, [esi+spanpackage_t_light]
        mov     ebp, [esi+spanpackage_t_zi]
        ror     ebp, 16
        push    esi
        mov     esi, [esi+spanpackage_t_ptex]
        jmp     dword ptr [aff8entryvec_table+eax*4]

; Register state in draw loop:
; bx = count; high word ebx = sfrac; ecx = pz; dx = light;
; high word edx = tfrac; esi = ptex; edi = pdest; ebp = 1/z

LDrawLoop:
LDraw8:
        cmp bp, [ecx]
        jl      Lp1
        xor     eax, eax
        mov     ah, dh
        mov     al, [esi]
        mov     [ecx], bp
        mov     al, [eax+12345678h]
LPatch8:
        mov     [edi], al
Lp1:
        add     edx, [tstep]
        sbb     eax, eax
        add     ebp, [lzistepx]
        adc     ebp, 0
        add     ebx, [_a_sstepxfrac]
        adc     esi, [advancetable+4+eax*4]

LDraw7:
        cmp bp, [ecx+2]
        jl      Lp2
        xor     eax, eax
        mov     ah, dh
        mov     al, [esi]
        mov     [ecx+2], bp
        mov     al, [eax+12345678h]
LPatch7:
        mov     [edi+1], al
Lp2:
        add     edx, [tstep]
        sbb     eax, eax
        add     ebp, [lzistepx]
        adc     ebp, 0
        add     ebx, [_a_sstepxfrac]
        adc     esi, [advancetable+4+eax*4]

LDraw6:
        cmp bp, [ecx+4]
        jl      Lp3
        xor     eax, eax
        mov     ah, dh
        mov     al, [esi]
        mov     [ecx+4], bp
        mov     al, [eax+12345678h]
LPatch6:
        mov     [edi+2], al
Lp3:
        add     edx, [tstep]
        sbb     eax, eax
        add     ebp, [lzistepx]
        adc     ebp, 0
        add     ebx, [_a_sstepxfrac]
        adc     esi, [advancetable+4+eax*4]

LDraw5:
        cmp bp, [ecx+6]
        jl      Lp4
        xor     eax, eax
        mov     ah, dh
        mov     al, [esi]
        mov     [ecx+6], bp
        mov     al, [eax+12345678h]
LPatch5:
        mov     [edi+3], al
Lp4:
        add     edx, [tstep]
        sbb     eax, eax
        add     ebp, [lzistepx]
        adc     ebp, 0
        add     ebx, [_a_sstepxfrac]
        adc     esi, [advancetable+4+eax*4]

LDraw4:
        cmp bp, [ecx+8]
        jl      Lp5
        xor     eax, eax
        mov     ah, dh
        mov     al, [esi]
        mov     [ecx+8], bp
        mov     al, [eax+12345678h]
LPatch4:
        mov     [edi+4], al
Lp5:
        add     edx, [tstep]
        sbb     eax, eax
        add     ebp, [lzistepx]
        adc     ebp, 0
        add     ebx, [_a_sstepxfrac]
        adc     esi, [advancetable+4+eax*4]

LDraw3:
        cmp bp, [ecx+10]
        jl      Lp6
        xor     eax, eax
        mov     ah, dh
        mov     al, [esi]
        mov     [ecx+10], bp
        mov     al, [eax+12345678h]
LPatch3:
        mov     [edi+5], al
Lp6:
        add     edx, [tstep]
        sbb     eax, eax
        add     ebp, [lzistepx]
        adc     ebp, 0
        add     ebx, [_a_sstepxfrac]
        adc     esi, [advancetable+4+eax*4]

LDraw2:
        cmp bp, [ecx+12]
        jl      Lp7
        xor     eax, eax
        mov     ah, dh
        mov     al, [esi]
        mov     [ecx+12], bp
        mov     al, [eax+12345678h]
LPatch2:
        mov     [edi+6], al
Lp7:
        add     edx, [tstep]
        sbb     eax, eax
        add     ebp, [lzistepx]
        adc     ebp, 0
        add     ebx, [_a_sstepxfrac]
        adc     esi, [advancetable+4+eax*4]

LDraw1:
        cmp bp, [ecx+14]
        jl      Lp8
        xor     eax, eax
        mov     ah, dh
        mov     al, [esi]
        mov     [ecx+14], bp
        mov     al, [eax+12345678h]
LPatch1:
        mov     [edi+7], al
Lp8:
        add     edx, [tstep]
        sbb     eax, eax
        add     ebp, [lzistepx]
        adc     ebp, 0
        add     ebx, [_a_sstepxfrac]
        adc     esi, [advancetable+4+eax*4]

        add     edi, 8
        add     ecx, 16
        dec     bx
        jnz     LDrawLoop

        pop     esi                     ; restore spans pointer
LNextSpan:
        add     esi, spanpackage_t_size
LNextSpanESISet:
        mov     edx, [esi+spanpackage_t_count]
        cmp     edx, -999999
        jnz     LSpanLoop

        pop     edi
        pop     ebp
        pop     ebx
        pop     esi
        pop     edx
        pop     ecx
        pop     eax
        ret

; draw a one-long span
LExactlyOneLong:
        mov     ecx, [esi+spanpackage_t_pz]
        mov     ebp, [esi+spanpackage_t_zi]
        ror     ebp, 16
        mov     ebx, [esi+spanpackage_t_ptex]
        cmp bp, [ecx]
        jl      LNextSpan
        xor     eax, eax
        mov     edi, [esi+spanpackage_t_pdest]
        mov     ah, [esi+spanpackage_t_light+1]
        add     esi, spanpackage_t_size
        mov     al, [ebx]
        mov     [ecx], bp
        mov     al, [eax+12345678h]
LPatch9:
        mov     [edi], al
        jmp     LNextSpanESISet
D_PolysetDrawSpans8_ endp

public  D_PolysetAff8End_
D_PolysetAff8End_:


;=============================================================================
; D_Aff8Patch_  (was: _D_Aff8Patch)
; C: void D_Aff8Patch(void *pcolormap)  -- pcolormap in EAX
; Self-modifies the 9 displacement fields in D_PolysetDrawSpans8.
;=============================================================================
D_Aff8Patch_ proc near
        ; LPatchN are CODE labels.  A direct ds:[label] operand makes WASM emit
        ; an A3 moffs instruction whose disp32 gets a "Frame: DGROUP" OMF
        ; fixup.  Under DOS4GW that value is NOT the flat address of the code
        ; label, so the write lands in the wrong place and the placeholders
        ; stay at 0x12345678.  Loading the address with "offset label" emits
        ; a "Frame: TARGET" fixup, which is the correct flat address; the
        ; subsequent [reg] write uses DS (flat RW) and patches the code.
        ; ECX is callee-saved in the Watcom register ABI, so preserve it.
        push    ecx
        mov     ecx, eax                ; ecx = pcolormap
        mov     eax, offset LPatch1-4
        mov     [eax], ecx
        mov     eax, offset LPatch2-4
        mov     [eax], ecx
        mov     eax, offset LPatch3-4
        mov     [eax], ecx
        mov     eax, offset LPatch4-4
        mov     [eax], ecx
        mov     eax, offset LPatch5-4
        mov     [eax], ecx
        mov     eax, offset LPatch6-4
        mov     [eax], ecx
        mov     eax, offset LPatch7-4
        mov     [eax], ecx
        mov     eax, offset LPatch8-4
        mov     [eax], ecx
        mov     eax, offset LPatch9-4
        mov     [eax], ecx
        pop     ecx
        ret
D_Aff8Patch_ endp


;=============================================================================
; D_PolysetDraw_  (was: _D_PolysetDraw)  -- void
;=============================================================================
D_PolysetDraw_ proc near
        sub     esp, SPAN_SIZE
        mov     eax, esp
        add     eax, CACHE_SIZE-1
        and     eax, NOT (CACHE_SIZE-1)
        mov     [_a_spans], eax

        mov     eax, [_r_affinetridesc+atd_drawtype]
        test    eax, eax
        jz      D_DrawNonSubdiv_        ; tail call (frees SPAN_SIZE there)

        push    ebp
        push    ecx                     ; callee-saved
        push    edx                     ; callee-saved
        push    esi
        push    ebx
        push    edi

        mov     ebp, [_r_affinetridesc+atd_numtriangles]
        shl     ebp, 4
        mov     ebx, [_r_affinetridesc+atd_ptriangles]
        mov     edi, [_r_affinetridesc+atd_pfinalverts]

Llooptop:
        mov     ecx, [ebx+ebp+mtri_vertindex-16+0]
        mov     esi, [ebx+ebp+mtri_vertindex-16+4]
        shl     ecx, 5
        mov     edx, [ebx+ebp+mtri_vertindex-16+8]
        shl     esi, 5
        add     ecx, edi
        shl     edx, 5
        add     esi, edi
        add     edx, edi

; signed area test via FPU -- zero-fxch rewrite with original sign convention.
; area = term2 - term1, matching the original fsubrp and the
; sub eax,080000001h / jc Lskip test below.
        fild    dword ptr [ecx+fv_v+4]          ; i0v1
        fisub   dword ptr [esi+fv_v+4]          ; i0v1 - i1v1
        fild    dword ptr [ecx+fv_v+0]          ; i0v0
        fisub   dword ptr [edx+fv_v+0]          ; i0v0 - i2v0
        fmulp   st(1), st(0)                    ; term1
        fild    dword ptr [ecx+fv_v+0]          ; i0v0
        fisub   dword ptr [esi+fv_v+0]          ; i0v0 - i1v0
        fild    dword ptr [ecx+fv_v+4]          ; i0v1
        fisub   dword ptr [edx+fv_v+4]          ; i0v1 - i2v1
        fmulp   st(1), st(0)                    ; term2
        fsubrp  st(1), st(0)                    ; area = term2 - term1
        mov     eax, [ecx+fv_v+16]
        and     eax, 0FF00h
        add     eax, [_acolormap]
        mov     [_d_pcolormap], eax
        fstp    dword ptr [Ltemp]
        mov     eax, [Ltemp]
        sub     eax, 080000001h
        jc      Lskip

        mov     eax, [ebx+ebp+mtri_facesfront-16]
        test    eax, eax
        jz      Lfacesback

        push    edx
        push    esi
        push    ecx
        call    D_PolysetRecursiveTriangle_
        sub     ebp, 16
        jnz     Llooptop
        jmp     Ldone2

Lfacesback:
        mov     eax, [ecx+fv_v+8]
        push    eax                     ; s0
        mov     eax, [esi+fv_v+8]
        push    eax                     ; s1
        mov     eax, [edx+fv_v+8]
        push    eax                     ; s2
        push    ecx
        push    edx

        mov     eax, [_r_affinetridesc+atd_seamfixupX16]
        test    dword ptr [ecx+fv_flags], ALIAS_ONSEAM
        jz      Lp11
        add     [ecx+fv_v+8], eax
Lp11:
        test    dword ptr [esi+fv_flags], ALIAS_ONSEAM
        jz      Lp12
        add     [esi+fv_v+8], eax
Lp12:
        test    dword ptr [edx+fv_flags], ALIAS_ONSEAM
        jz      Lp13
        add     [edx+fv_v+8], eax
Lp13:
        push    edx
        push    esi
        push    ecx
        call    D_PolysetRecursiveTriangle_

        pop     edx
        pop     ecx
        pop     eax
        mov     [edx+fv_v+8], eax
        pop     eax
        mov     [esi+fv_v+8], eax
        pop     eax
        mov     [ecx+fv_v+8], eax

Lskip:
        sub     ebp, 16
        jnz     Llooptop

Ldone2:
        pop     edi
        pop     ebx
        pop     esi
        pop     edx
        pop     ecx
        pop     ebp
        add     esp, SPAN_SIZE
        ret
D_PolysetDraw_ endp


;=============================================================================
; D_PolysetScanLeftEdge_  (was: _D_PolysetScanLeftEdge)
; C: void D_PolysetScanLeftEdge(int height)  -- height in EAX
;=============================================================================
D_PolysetScanLeftEdge_ proc near
        push    ebp
        push    esi
        push    edi
        push    ebx
        push    ecx                     ; callee-saved
        push    edx                     ; callee-saved
        push    eax                     ; save height -> [esp]
        mov     eax, [esp]              ; height
        mov     ecx, [_d_sfrac]
        and     eax, 0FFFFh
        mov     ebx, [_d_ptex]
        or      ecx, eax
        mov     esi, [_d_pedgespanpackage]
        mov     edx, [_d_tfrac]
        mov     edi, [_d_light]
        mov     ebp, [_d_zi]

LScanLoop:
        mov     [esi+spanpackage_t_ptex], ebx
        mov     eax, [_d_pdest]
        mov     [esi+spanpackage_t_pdest], eax
        mov     eax, [_d_pz]
        mov     [esi+spanpackage_t_pz], eax
        mov     eax, [_d_aspancount]
        mov     [esi+spanpackage_t_count], eax
        mov     [esi+spanpackage_t_light], edi
        mov     [esi+spanpackage_t_zi], ebp
        mov     [esi+spanpackage_t_sfrac], ecx
        mov     [esi+spanpackage_t_tfrac], edx

        mov     al, [esi+spanpackage_t_size]    ; pretouch next cache line
        add     esi, spanpackage_t_size
        mov     eax, [_erroradjustup]
        mov     [_d_pedgespanpackage], esi
        mov     esi, [_errorterm]
        add     esi, eax
        mov     eax, [_d_pdest]
        js      LNoLeftEdgeTurnover

        sub     esi, [_erroradjustdown]
        add     eax, [_d_pdestextrastep]
        mov     [_errorterm], esi
        mov     [_d_pdest], eax
        mov     eax, [_d_pz]
        mov     esi, [_d_aspancount]
        add     eax, [_d_pzextrastep]
        add     ecx, [_d_sfracextrastep]
        adc     ebx, [_d_ptexextrastep]
        add     esi, [_d_countextrastep]
        mov     [_d_pz], eax
        mov     eax, [_d_tfracextrastep]
        mov     [_d_aspancount], esi
        add     edx, eax
        jnc     LSkip1
        add     ebx, [_r_affinetridesc+atd_skinwidth]
LSkip1:
        add     edi, [_d_lightextrastep]
        add     ebp, [_d_ziextrastep]
        mov     esi, [_d_pedgespanpackage]
        dec     ecx
        test    ecx, 0FFFFh
        jnz     LScanLoop

        pop     eax
        pop     edx
        pop     ecx
        pop     ebx
        pop     edi
        pop     esi
        pop     ebp
        ret

LNoLeftEdgeTurnover:
        mov     [_errorterm], esi
        add     eax, [_d_pdestbasestep]
        mov     [_d_pdest], eax
        mov     eax, [_d_pz]
        mov     esi, [_d_aspancount]
        add     eax, [_d_pzbasestep]
        add     ecx, [_d_sfracbasestep]
        adc     ebx, [_d_ptexbasestep]
        add     esi, [_ubasestep]
        mov     [_d_pz], eax
        mov     [_d_aspancount], esi
        mov     esi, [_d_tfracbasestep]
        add     edx, esi
        jnc     LSkip2
        add     ebx, [_r_affinetridesc+atd_skinwidth]
LSkip2:
        add     edi, [_d_lightbasestep]
        add     ebp, [_d_zibasestep]
        mov     esi, [_d_pedgespanpackage]
        dec     ecx
        test    ecx, 0FFFFh
        jnz     LScanLoop

        pop     eax
        pop     edx
        pop     ecx
        pop     ebx
        pop     edi
        pop     esi
        pop     ebp
        ret
D_PolysetScanLeftEdge_ endp


;=============================================================================
; D_PolysetDrawFinalVerts_  (was: _D_PolysetDrawFinalVerts)
; C: void D_PolysetDrawFinalVerts(finalvert_t *fv, int numverts)
;    EAX = fv, EDX = numverts
;=============================================================================
D_PolysetDrawFinalVerts_ proc near
        push    ebp
        push    ebx
        push    ecx                     ; callee-saved (loop counter)
        push    edx                     ; save numverts
        mov     ecx, edx                ; numverts
        mov     ebx, eax                ; fv
        push    esi
        push    edi

LFVLoop:
        mov     eax, [ebx+fv_v+0]
        mov     edx, [_r_refdef+rd_vrectright]
        cmp     eax, edx
        jge     LNextVert
        mov     esi, [ebx+fv_v+4]
        mov     edx, [_r_refdef+rd_vrectbottom]
        cmp     esi, edx
        jge     LNextVert

        mov     edi, [_zspantable+esi*4]
        mov     edx, [ebx+fv_v+20]
        shr     edx, 16
        cmp dx, [edi+eax*2]
        jl      LNextVert
        mov     [edi+eax*2], dx

        mov     edi, [ebx+fv_v+12]
        shr     edi, 16
        mov     edi, [_skintable+edi*4]
        mov     edx, [ebx+fv_v+8]
        shr     edx, 16
        mov     dl, [edi+edx]
        mov     edi, [ebx+fv_v+16]
        and     edi, 0FF00h
        and     edx, 0FFh
        add     edi, edx
        mov     edx, [_acolormap]
        mov     dl, [edx+edi]
        mov     edi, [_d_scantable+esi*4]
        mov     esi, [_d_viewbuffer]
        add     edi, eax
        mov     [esi+edi], dl

LNextVert:
        add     ebx, fv_size
        dec     ecx
        jnz     LFVLoop

        pop     edi
        pop     esi
        pop     edx
        pop     ecx
        pop     ebx
        pop     ebp
        ret
D_PolysetDrawFinalVerts_ endp


;=============================================================================
; D_DrawNonSubdiv_  (was: _D_DrawNonSubdiv)  -- void, tail-called
;=============================================================================
D_DrawNonSubdiv_ proc near
        push    ebp
        push    ebx
        push    esi
        push    edi
        push    ecx                     ; callee-saved
        push    edx                     ; callee-saved

        mov     ebp, [_r_affinetridesc+atd_numtriangles]
        shl     ebp, mtri_shift         ; mtri_shift = 4
        mov     esi, [_r_affinetridesc+atd_ptriangles]

LNDLoop:
        mov     edi, [_r_affinetridesc+atd_pfinalverts]
        mov     ecx, [esi+ebp+mtri_vertindex-mtri_size+0]
        shl     ecx, 5
        mov     edx, [esi+ebp+mtri_vertindex-mtri_size+4]
        shl     edx, 5
        mov     ebx, [esi+ebp+mtri_vertindex-mtri_size+8]
        shl     ebx, 5
        add     ecx, edi
        add     edx, edi
        add     ebx, edi

; d_xdenom = (i0v1-i1v1)*(i0v0-i2v0) - (i0v0-i1v0)*(i0v1-i2v1)
        mov     eax, [ecx+fv_v+4]
        mov     esi, [ecx+fv_v+0]
        sub     eax, [edx+fv_v+4]
        sub     esi, [ebx+fv_v+0]
        imul    eax, esi
        mov     esi, [ecx+fv_v+0]
        mov     edi, [ecx+fv_v+4]
        sub     esi, [edx+fv_v+0]
        sub     edi, [ebx+fv_v+4]
        imul    edi, esi
        sub     eax, edi
        jns     LNextTri

        mov     [_d_xdenom], eax
        fild    dword ptr [_d_xdenom]

; copy index0/1/2 -> r_p0/1/2
        mov     eax, [ecx+fv_v+0]
        mov     esi, [ecx+fv_v+4]
        mov     [_r_p0+0], eax
        mov     [_r_p0+4], esi
        mov     eax, [ecx+fv_v+8]
        mov     esi, [ecx+fv_v+12]
        mov     [_r_p0+8], eax
        mov     [_r_p0+12], esi
        mov     eax, [ecx+fv_v+16]
        mov     esi, [ecx+fv_v+20]
        mov     [_r_p0+16], eax
        mov     [_r_p0+20], esi

        fdivr   dword ptr [float_1]

        mov     eax, [edx+fv_v+0]
        mov     esi, [edx+fv_v+4]
        mov     [_r_p1+0], eax
        mov     [_r_p1+4], esi
        mov     eax, [edx+fv_v+8]
        mov     esi, [edx+fv_v+12]
        mov     [_r_p1+8], eax
        mov     [_r_p1+12], esi
        mov     eax, [edx+fv_v+16]
        mov     esi, [edx+fv_v+20]
        mov     [_r_p1+16], eax
        mov     [_r_p1+20], esi

        mov     eax, [ebx+fv_v+0]
        mov     esi, [ebx+fv_v+4]
        mov     [_r_p2+0], eax
        mov     [_r_p2+4], esi
        mov     eax, [ebx+fv_v+8]
        mov     esi, [ebx+fv_v+12]
        mov     [_r_p2+8], eax
        mov     [_r_p2+12], esi
        mov     eax, [ebx+fv_v+16]
        mov     esi, [ebx+fv_v+20]
        mov     [_r_p2+16], eax
        mov     edi, [_r_affinetridesc+atd_ptriangles]
        mov     [_r_p2+20], esi
        mov     eax, [edi+ebp+mtri_facesfront-mtri_size]

        test    eax, eax
        jnz     LFacesFront

        mov     eax, [ecx+fv_flags]
        mov     esi, [edx+fv_flags]
        mov     edi, [ebx+fv_flags]
        test    eax, ALIAS_ONSEAM
        mov     eax, [_r_affinetridesc+atd_seamfixupX16]
        jz      LOnseamDone0
        add     [_r_p0+8], eax
LOnseamDone0:
        test    esi, ALIAS_ONSEAM
        jz      LOnseamDone1
        add     [_r_p1+8], eax
LOnseamDone1:
        test    edi, ALIAS_ONSEAM
        jz      LOnseamDone2
        add     [_r_p2+8], eax
LOnseamDone2:

LFacesFront:
        fstp    dword ptr [_d_xdenom]
        call    D_PolysetSetEdgeTable_
        call    D_RasterizeAliasPolySmooth_

LNextTri:
        mov     esi, [_r_affinetridesc+atd_ptriangles]
        sub     ebp, mtri_size
        jnz     LNDLoop

        pop     edx
        pop     ecx
        pop     edi
        pop     esi
        pop     ebx
        pop     ebp
        add     esp, SPAN_SIZE
        ret
D_DrawNonSubdiv_ endp

;=============================================================================
; Translation notes:
;
; 1. CALLING CONVENTION: Watcom register ABI. C-callable functions take args
;    in EAX/EDX. Callee-saved EBX/ECX/EDX/ESI/EDI/EBP all preserved. The two
;    stdcall routines (RecursiveTriangle, DrawNonSubdiv) keep their gas stack
;    conventions because they are asm-internal / tail-called.
;
; 2. FPU SYNTAX: gas swaps operands for fsubp/fsubrp (historic AT&T quirk):
;    gas 'fsubp %st(0),%st(N)' -> MASM 'fsubrp st(N),st(0)';
;    gas 'fsubrp %st(0),%st(N)' -> MASM 'fsubp st(N),st(0)'.
;    faddp/fmulp -> 'fXXXp st(N),st(0)'; fxch/fld/fild/fistp direct.
;
; 3. SELF-MODIFYING CODE: the nine 'mov al,[eax+12345678h]' instructions have
;    their disp32 patched by D_Aff8Patch via [LPatchN-4]. Verified by disassembly
;    that wasm emits a 6-byte instruction with disp32 exactly at LPatchN-4.
;
; 4. OPT (possible): D_PolysetCalcGradients' deep FPU stack choreography is
;    hand-tuned for 486 FPU pipeline latency - kept faithful rather than rewriting.
;
; 5. VALIDATION (native Win32 functional tests vs C reference oracles):
;    - D_PolysetCalcGradients: all 8 gradient outputs x 6 triangles match C ref
;      (d_xdenom pre-converted to float bits of 1/xden as the engine does).
;    - D_PolysetDraw area-calc FPU sequence: exact area values + backface signs.
;    - D_PolysetDrawFinalVerts: z-test + skin/colormap pixel writes match.
;    - D_PolysetScanLeftEdge: 3 span packages generated with correct stepping.
;    Self-modifying LPatch disp32 offsets verified via wdis.
;=============================================================================

end
