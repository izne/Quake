;=============================================================================
; r_aliasa.asm - alias model transform and project (replaces the old stub)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/r_aliasa.s.
; R_AliasTransformAndProjectFinalVerts(finalvert_t *fv, stvert_t *pstverts)
; Watcom register ABI: EAX=fv, EDX=pstverts.
; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> preserved.
;
; FPU mapping (derived from gas stack comments):
;   fdivrs Lfloat_1 -> fdivr dword ptr [Lfloat_1]  (st0 = 1.0/st0)
;   fsubr %st(a),%st(0) -> fsubr st(0),st(a)  (st0 = sta - st0)
;   fsubp -> handled via stack comments; fmulp/faddp -> fXXXp st(N),st(0)
;=============================================================================

.386
.model  small

fv_v            equ 0
fv_flags        equ 24
fv_size         equ 32
stv_onseam      equ 0
stv_s           equ 4
stv_t           equ 8
stv_size        equ 12
tv_lightnormalindex equ 3
tv_size         equ 4

extrn   _r_apverts:dword, _r_anumverts:dword
extrn   _aliastransform:dword, _r_avertexnormals:dword
extrn   _r_plightvec:dword, _r_ambientlight:dword, _r_shadelight:dword
extrn   _aliasxcenter:dword, _aliasycenter:dword

public  R_AliasTransformAndProjectFinalVerts_

.data
Lfloat_1    dd 1.0
Ltemp       dd 0
Lcoords     dd 0, 0, 0

.code

;=============================================================================
; R_AliasTransformAndProjectFinalVerts_  (was: _R_AliasTransform...)
; EAX=fv, EDX=pstverts
;=============================================================================
R_AliasTransformAndProjectFinalVerts_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx                     ; callee-saved (i counter)
        push    edx                     ; callee-saved (pstverts)
        mov     ebp, edx                ; ebp = pstverts
        mov     edi, eax                ; edi = fv
        mov     esi, [_r_apverts]
        mov     ecx, [_r_anumverts]
        xor     edx, edx

Lloop:
; transform: zi = 1/(Dot(pverts->v, aliastransform[2]) + aliastransform[2][3])
        movzx   eax, byte ptr [esi]
        mov     [Lcoords], eax
        fild    dword ptr [Lcoords]             ; v0
        movzx   eax, byte ptr [esi+1]
        mov     [Lcoords+4], eax
        fild    dword ptr [Lcoords+4]           ; v1 | v0
        movzx   eax, byte ptr [esi+2]
        mov     [Lcoords+8], eax
        fild    dword ptr [Lcoords+8]           ; v2 | v1 | v0

        fld     st(2)                            ; v0 | v2 | v1 | v0
        fmul    dword ptr [_aliastransform+32]
        fld     st(2)                            ; v1 | accum | v2 | v1 | v0
        fmul    dword ptr [_aliastransform+36]
        fxch    st(1)                            ; accum | accum2 | v2 | v1 | v0
        fadd    dword ptr [_aliastransform+44]
        fld     st(2)                            ; v2 | accum | accum2 | v2 | v1 | v0
        fmul    dword ptr [_aliastransform+40]
        fxch    st(1)                            ; accum | accum3 | accum2 | v2 | v1 | v0
        faddp   st(2), st(0)                     ; accum3 | accum | v2 | v1 | v0
        mov     dl, [esi+tv_lightnormalindex]
        mov     eax, [ebp+stv_s]
        mov     [edi+fv_v+8], eax
        faddp   st(1), st(0)                     ; z | v2 | v1 | v0

        mov     eax, [ebp+stv_t]
        mov     [edi+fv_v+12], eax

        fdivr   dword ptr [Lfloat_1]             ; zi | v2 | v1 | v0

; fv->flags = pstverts->onseam
        mov     eax, [ebp+stv_onseam]
        mov     [edi+fv_flags], eax

; lighting: lightcos = Dot(r_avertexnormals[index], r_plightvec)
        lea     eax, [edx+edx*2]                 ; index*3
        fxch    st(3)                            ; v0 | v2 | v1 | zi

        fld     dword ptr [_r_avertexnormals+eax*4]
        fmul    dword ptr [_r_plightvec]
        fld     dword ptr [_r_avertexnormals+4+eax*4]
        fmul    dword ptr [_r_plightvec+4]
        fld     dword ptr [_r_avertexnormals+8+eax*4]
        fmul    dword ptr [_r_plightvec+8]
        fxch    st(1)
        faddp   st(2), st(0)
        fld     st(2)                            ; v0 | laccum | laccum2 | v0 | v2 | v1 | zi
        fmul    dword ptr [_aliastransform+0]    ; xaccum
        fxch    st(2)                            ; laccum2 | laccum | xaccum | ...
        faddp   st(1), st(0)                     ; laccum | xaccum | v0 | v2 | v1 | zi

; temp = r_ambientlight; if (lightcos < 0) temp += (int)(r_shadelight*lightcos)
        fst     dword ptr [Ltemp]               ; gas 'fsts' = store, NO pop
        mov     eax, [_r_ambientlight]
        mov     dl, byte ptr [Ltemp+3]
        test    dl, 080h
        jz      Lsavelight
        fmul    dword ptr [_r_shadelight]
        fistp   dword ptr [Ltemp]
        add     eax, [Ltemp]
        jns     Lp1
        xor     eax, eax

Lp1:
; project x,y,z
        fxch    st(1)                            ; v0 | xaccum | v2 | v1 | zi
        fmul    dword ptr [_aliastransform+16]   ; yaccum
        fxch    st(3)                            ; v1 | xaccum | v2 | yaccum | zi
        fld     st(0)                            ; v1 | v1 | xaccum | v2 | yaccum | zi
        fmul    dword ptr [_aliastransform+4]    ; xaccum2
        fxch    st(1)                            ; v1 | xaccum2 | xaccum | v2 | yaccum | zi
        mov     [edi+fv_v+16], eax
        fmul    dword ptr [_aliastransform+20]   ; yaccum2
        fxch    st(2)                            ; xaccum | xaccum2 | yaccum2 | v2 | yaccum | zi
        fadd    dword ptr [_aliastransform+12]
        fxch    st(4)                            ; yaccum | xaccum2 | yaccum2 | v2 | xaccum | zi
        fadd    dword ptr [_aliastransform+28]
        fxch    st(3)                            ; v2 | xaccum2 | yaccum2 | yaccum | xaccum | zi
        fld     st(0)                            ; v2 | v2 | xaccum2 | yaccum2 | yaccum | xaccum | zi
        fmul    dword ptr [_aliastransform+8]    ; xaccum3
        fxch    st(1)                            ; v2 | xaccum3 | xaccum2 | yaccum2 | yaccum | xaccum | zi
        fmul    dword ptr [_aliastransform+24]   ; yaccum3
        fxch    st(5)                            ; xaccum | xaccum3 | xaccum2 | yaccum2 | yaccum | yaccum3 | zi
        faddp   st(2), st(0)                     ; xaccum3 | xaccum | yaccum2 | yaccum | yaccum3 | zi
        fxch    st(3)                            ; yaccum | xaccum | yaccum2 | xaccum3 | yaccum3 | zi
        faddp   st(2), st(0)                     ; xaccum | yaccum | xaccum3 | yaccum3 | zi
        add     esi, tv_size
        faddp   st(2), st(0)                     ; yaccum | x | yaccum3 | zi
        faddp   st(2), st(0)                     ; x | y | zi
        add     ebp, stv_size
        fmul    st(0), st(2)                     ; x/z | y | zi (st0 = st0*zi)
        fxch    st(1)                            ; y | x/z | zi
        fmul    st(0), st(2)                     ; y/z | x/z | zi (st0 = st0*zi)
        fxch    st(1)                            ; x/z | y/z | zi
        fadd    dword ptr [_aliasxcenter]        ; u
        fxch    st(1)                            ; y/z | u | zi
        fadd    dword ptr [_aliasycenter]        ; v | u | zi
        fxch    st(2)                            ; zi | u | v
        fistp   dword ptr [edi+fv_v+20]          ; u | v
        fistp   dword ptr [edi+fv_v+0]           ; v
        fistp   dword ptr [edi+fv_v+4]

        add     edi, fv_size
        dec     ecx
        jnz     Lloop

        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret

Lsavelight:
        fstp    st(0)
        jmp     Lp1
R_AliasTransformAndProjectFinalVerts_ endp

end
