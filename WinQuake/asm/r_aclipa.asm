;=============================================================================
; r_aclipa.asm - alias model clipping (replaces the old placeholder stub)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/r_aclipa.s.
; Four routines sharing one FPU core:
;   R_Alias_clip_bottom/top/right/left(finalvert_t *pfv0, *pfv1, *out)
; Watcom register ABI: EAX=pfv0, EDX=pfv1, EBX=out.
; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> preserved.
;
; FPU operand mapping (derived from the gas stack comments):
;   gas fdivp %st(0),%st(1) -> MASM fdivrp st(1),st(0)  (-> st0 = Ltemp0/Ltemp1 = scale)
;   gas fsubr %st(0),%st(N) -> MASM fsub   st(N),st(0)  (stN = stN - st0)
;   gas fmul  %st(0),%st(N) -> MASM fmul   st(N),st(0)  (stN = stN * st0)
;   gas faddp %st(0),%st(N) -> MASM faddp  st(N),st(0)  (stN = stN + st0; pop)
;=============================================================================

.386
.model  small

rd_aliasvrect        equ 20
rd_aliasvrectright   equ 48
rd_aliasvrectbottom  equ 52
fv_v                 equ 0

extrn   _r_refdef:dword
extrn   float_point5:dword

public  R_Alias_clip_bottom_, R_Alias_clip_top_
public  R_Alias_clip_right_, R_Alias_clip_left_

.data
Ltemp0  dd 0
Ltemp1  dd 0

.code

;------------------------------------------------------------------------------
; Shared core (near proc). Inputs:
;   EAX = clip coord, EDX = v0coord, ECX = v1coord,
;   ESI = pfv0 (near endpoint), EDI = pfv1 (far endpoint), EBX = out.
; All callee-saved regs already saved by caller; caller restores them.
; Produces the interpolated vertex into [out]. Based on gas LDoForwardOrBackward
; + LDo3Forward with the exact FPU stack choreography.
;------------------------------------------------------------------------------
AC_Core proc near
        sub     ecx, edx                ; Ltemp1 = v1coord - v0coord
        sub     eax, edx                ; Ltemp0 = clip - v0coord
        mov     [Ltemp1], ecx
        mov     [Ltemp0], eax
        fild    dword ptr [Ltemp1]      ; st0 = Ltemp1
        fild    dword ptr [Ltemp0]      ; st0=Ltemp0, st1=Ltemp1
        mov     edx, ebx                ; edx = out
        mov     eax, 2                  ; 3 components
        fdivrp  st(1), st(0)            ; -> st0 = Ltemp0/Ltemp1 = scale

AC_Reload:
        fild    dword ptr [esi+fv_v+0]
        fild    dword ptr [edi+fv_v+0]
        fild    dword ptr [esi+fv_v+4]
        fild    dword ptr [edi+fv_v+4]
        fild    dword ptr [esi+fv_v+8]
        fild    dword ptr [edi+fv_v+8]
        fxch    st(5)
        fsub    st(4), st(0)            ; st4 = fv1v0-fv0v0
        fxch    st(3)
        fsub    st(2), st(0)            ; st2 = fv1v1-fv0v1
        fxch    st(1)
        fsub    st(5), st(0)            ; st5 = fv1v2-fv0v2
        fxch    st(6)                   ; st0 = scale
        fmul    st(4), st(0)            ; st4 *= scale
        add     edi, 12
        fmul    st(2), st(0)            ; st2 *= scale
        add     esi, 12
        add     edx, 12
        fmul    st(5), st(0)            ; st5 *= scale
        fxch    st(3)                   ; st0 = fv0v0
        faddp   st(4), st(0)            ; st4 = fv0v0+(fv1v0-fv0v0)*scale; pop
        faddp   st(1), st(0)            ; st0 = fv0v1+(fv1v1-fv0v1)*scale
        fxch    st(4)                   ; st0 = fv0v2
        faddp   st(3), st(0)            ; st0 = fv0v2+(fv1v2-fv0v2)*scale
        fxch    st(1)                   ; st0 = scale
        fadd    dword ptr [float_point5]
        fxch    st(3)
        fadd    dword ptr [float_point5]
        fxch    st(2)
        fadd    dword ptr [float_point5]
        fxch    st(3)                   ; st0 = fv0v0+..., st1 = scale
        fistp   dword ptr [edx+fv_v+0-12]   ; out->v[0]
        fxch    st(1)
        fistp   dword ptr [edx+fv_v+4-12]   ; out->v[1]
        fxch    st(1)
        fistp   dword ptr [edx+fv_v+8-12]   ; out->v[2]
        dec     eax
        jnz     AC_Reload
        fstp    st(0)                   ; drop remaining scale
        ret
AC_Core endp

;------------------------------------------------------------------------------
; Entry helpers: each saves callee-saved regs, loads pfv0/pfv1/out, chooses the
; clip coordinate + comparison axis, handles endpoint swap, then calls AC_Core.
;------------------------------------------------------------------------------
R_Alias_clip_bottom_ proc near
        push    esi
        push    edi
        push    ebp
        push    ebx
        push    ecx
        push    edx
        push    eax                     ; [esp+4] = pfv0
        push    edx                     ; [esp+0] = pfv1
        mov     esi, [esp+4]
        mov     edi, [esp]
        mov     eax, [_r_refdef+rd_aliasvrectbottom]
        mov     edx, [esi+fv_v+4]
        mov     ecx, [edi+fv_v+4]
        cmp     edx, ecx
        jl      ACB_Fwd
        mov     edx, [edi+fv_v+4]
        mov     ecx, [esi+fv_v+4]
        xchg    esi, edi
        jmp     ACB_Core
ACB_Fwd:
        mov     edx, [esi+fv_v+4]
        mov     ecx, [edi+fv_v+4]
ACB_Core:
        call    AC_Core
        pop     edx
        pop     eax
        pop     edx
        pop     ecx
        pop     ebx
        pop     ebp
        pop     edi
        pop     esi
        ret
R_Alias_clip_bottom_ endp

R_Alias_clip_top_ proc near
        push    esi
        push    edi
        push    ebp
        push    ebx
        push    ecx
        push    edx
        push    eax
        push    edx
        mov     esi, [esp+4]
        mov     edi, [esp]
        mov     eax, [_r_refdef+rd_aliasvrect+4]
        mov     edx, [esi+fv_v+4]
        mov     ecx, [edi+fv_v+4]
        cmp     edx, ecx
        jl      ACT_Fwd
        mov     edx, [edi+fv_v+4]
        mov     ecx, [esi+fv_v+4]
        xchg    esi, edi
        jmp     ACT_Core
ACT_Fwd:
        mov     edx, [esi+fv_v+4]
        mov     ecx, [edi+fv_v+4]
ACT_Core:
        call    AC_Core
        pop     edx
        pop     eax
        pop     edx
        pop     ecx
        pop     ebx
        pop     ebp
        pop     edi
        pop     esi
        ret
R_Alias_clip_top_ endp

R_Alias_clip_right_ proc near
        push    esi
        push    edi
        push    ebp
        push    ebx
        push    ecx
        push    edx
        push    eax
        push    edx
        mov     esi, [esp+4]
        mov     edi, [esp]
        mov     eax, [_r_refdef+rd_aliasvrectright]
        ; right/left: compare v[1] for direction, use v[0] for the interpolation
        mov     edx, [esi+fv_v+4]
        mov     ecx, [edi+fv_v+4]
        cmp     edx, ecx
        mov     edx, [esi+fv_v+0]
        mov     ecx, [edi+fv_v+0]
        jl      ACR_Fwd
        mov     edx, [edi+fv_v+0]
        mov     ecx, [esi+fv_v+0]
        xchg    esi, edi
        jmp     ACR_Core
ACR_Fwd:
        mov     edx, [esi+fv_v+0]
        mov     ecx, [edi+fv_v+0]
ACR_Core:
        call    AC_Core
        pop     edx
        pop     eax
        pop     edx
        pop     ecx
        pop     ebx
        pop     ebp
        pop     edi
        pop     esi
        ret
R_Alias_clip_right_ endp

R_Alias_clip_left_ proc near
        push    esi
        push    edi
        push    ebp
        push    ebx
        push    ecx
        push    edx
        push    eax
        push    edx
        mov     esi, [esp+4]
        mov     edi, [esp]
        mov     eax, [_r_refdef+rd_aliasvrect+0]
        mov     edx, [esi+fv_v+4]
        mov     ecx, [edi+fv_v+4]
        cmp     edx, ecx
        mov     edx, [esi+fv_v+0]
        mov     ecx, [edi+fv_v+0]
        jl      ACL_Fwd
        mov     edx, [edi+fv_v+0]
        mov     ecx, [esi+fv_v+0]
        xchg    esi, edi
        jmp     ACL_Core
ACL_Fwd:
        mov     edx, [esi+fv_v+0]
        mov     ecx, [edi+fv_v+0]
ACL_Core:
        call    AC_Core
        pop     edx
        pop     eax
        pop     edx
        pop     ecx
        pop     ebx
        pop     ebp
        pop     edi
        pop     esi
        ret
R_Alias_clip_left_ endp

end
