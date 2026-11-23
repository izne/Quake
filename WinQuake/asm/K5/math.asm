;=============================================================================
; math.asm - x86 assembly-language math routines
;
; 486 / AMD Am5x86 / AMD K5 optimized MASM (OpenWatcom wasm) version.
; Three routines:
;   Invert24To16(val)               - 1 arg  -> EAX
;   TransformVector(in, out)        - 2 args -> EAX, EDX
;   BoxOnPlaneSide(emins, emaxs, p) - 3 args -> EAX, EDX, EBX
;
; CALLING CONVENTION (Watcom default 32-bit register ABI):
;   Only EAX/EDX are volatile; EBX/ECX/ESI/EDI/EBP are callee-saved.
;=============================================================================

.386
; explicit PARA segments

pl_normal       equ 0
pl_dist         equ 12
pl_signbits     equ 17

extrn   _vright:dword
extrn   _vup:dword
extrn   _vpn:dword
extrn   BOPS_Error_:near

public  Invert24To16_
public  TransformVector_
public  BoxOnPlaneSide_
_DATA SEGMENT PARA PUBLIC USE32 'DATA'
        ASSUME DS:_DATA
    ALIGN 16
; jump table indexed by p->signbits (0..7)
Ljmptab dd Lcase0, Lcase1, Lcase2, Lcase3
        dd Lcase4, Lcase5, Lcase6, Lcase7
_DATA ENDS

_TEXT SEGMENT PARA PUBLIC USE32 'CODE'
        ASSUME CS:_TEXT
;=============================================================================
; Invert24To16_  (was: _Invert24To16)
; C: fixed16_t Invert24To16(fixed16_t val)   // (2^40 / val), or -1 if val<=256
; On entry: EAX = val
;=============================================================================
    ALIGN 16
Invert24To16_ proc near
        push    ecx                 ; ECX is callee-saved in Watcom
        push    edx                 ; EDX is callee-saved in Watcom
        mov     ecx, eax            ; ecx = val
        mov     edx, 0100h          ; 0x100 (high word of 2^40 dividend)
        cmp     ecx, edx
        jle     short LOutOfRange
        xor     eax, eax            ; eax = 0 (low word of dividend)
        div     ecx                 ; edx:eax / ecx -> eax = quotient
        pop     edx
        pop     ecx
        ret
LOutOfRange:
        mov     eax, 0FFFFFFFFh
        pop     edx
        pop     ecx
        ret
Invert24To16_ endp


;=============================================================================
; TransformVector_  (was: _TransformVector)
; C: void TransformVector(vec3_t in, vec3_t out)
;       out[0] = DotProduct(in, vright);
;       out[1] = DotProduct(in, vup);
;       out[2] = DotProduct(in, vpn);
; On entry: EAX = in, EDX = out (Watcom ABI)
; Optimized: 0 fxch (saves 486 stalls + K5 ROP decode slots), loads in[0..2]
; once onto x87 stack, and consumes stack cleanly via fstp st(1).
;=============================================================================
    ALIGN 16
TransformVector_ proc near
        fld     dword ptr [eax+8]            ; in[2]
        fld     dword ptr [eax+4]            ; in[1] | in[2]
        fld     dword ptr [eax]              ; in[0] | in[1] | in[2]

        ; out[0] = DotProduct(in, vright)
        fld     st(0)                        ; in[0] | in[0] | in[1] | in[2]
        fmul    dword ptr [_vright]          ; in[0]*vr[0] | in[0] | in[1] | in[2]
        fld     st(2)                        ; in[1] | in[0]*vr[0] | in[0] | in[1] | in[2]
        fmul    dword ptr [_vright+4]        ; in[1]*vr[1] | in[0]*vr[0] | in[0] | in[1] | in[2]
        faddp   st(1), st(0)                 ; vr_xy | in[0] | in[1] | in[2]
        fld     st(3)                        ; in[2] | vr_xy | in[0] | in[1] | in[2]
        fmul    dword ptr [_vright+8]        ; in[2]*vr[2] | vr_xy | in[0] | in[1] | in[2]
        faddp   st(1), st(0)                 ; out[0] | in[0] | in[1] | in[2]
        fstp    dword ptr [edx]              ; in[0] | in[1] | in[2]

        ; out[1] = DotProduct(in, vup)
        fld     st(0)                        ; in[0] | in[0] | in[1] | in[2]
        fmul    dword ptr [_vup]             ; in[0]*vu[0] | in[0] | in[1] | in[2]
        fld     st(2)                        ; in[1] | in[0]*vu[0] | in[0] | in[1] | in[2]
        fmul    dword ptr [_vup+4]           ; in[1]*vu[1] | in[0]*vu[0] | in[0] | in[1] | in[2]
        faddp   st(1), st(0)                 ; vu_xy | in[0] | in[1] | in[2]
        fld     st(3)                        ; in[2] | vu_xy | in[0] | in[1] | in[2]
        fmul    dword ptr [_vup+8]           ; in[2]*vu[2] | vu_xy | in[0] | in[1] | in[2]
        faddp   st(1), st(0)                 ; out[1] | in[0] | in[1] | in[2]
        fstp    dword ptr [edx+4]            ; in[0] | in[1] | in[2]

        ; out[2] = DotProduct(in, vpn) -- consumes in[0..2] in-place
        fmul    dword ptr [_vpn]             ; in[0]*vp[0] | in[1] | in[2]
        fld     st(1)                        ; in[1] | in[0]*vp[0] | in[1] | in[2]
        fmul    dword ptr [_vpn+4]           ; in[1]*vp[1] | in[0]*vp[0] | in[1] | in[2]
        faddp   st(1), st(0)                 ; vp_xy | in[1] | in[2]
        fstp    st(1)                        ; vp_xy | in[2]  (pops used in[1])
        fld     st(1)                        ; in[2] | vp_xy | in[2]
        fmul    dword ptr [_vpn+8]           ; in[2]*vp[2] | vp_xy | in[2]
        faddp   st(1), st(0)                 ; out[2] | in[2]
        fstp    st(1)                        ; out[2]  (pops used in[2])
        fstp    dword ptr [edx+8]            ; (stack empty)
        ret
TransformVector_ endp


;=============================================================================
; BoxOnPlaneSide_  (was: _BoxOnPlaneSide)
; C: int BoxOnPlaneSide(vec3_t emins, vec3_t emaxs, mplane_t *p)
; On entry: EAX = emins, EDX = emaxs, EBX = p (kept directly, no remap!)
; Optimized: 0 fxch across all 8 cases (down from 7 per case), single normal
; load per axis, and direct Watcom register usage.
;=============================================================================
    ALIGN 16
BoxOnPlaneSide_ proc near
        push    ecx
        movzx   ecx, byte ptr [ebx+pl_signbits]
        cmp     ecx, 8
        jge     Lerror
        fld     dword ptr [ebx+pl_normal]    ; n0
        fld     st(0)                        ; n0 | n0
        jmp     dword ptr [Ljmptab+ecx*4]

; case 0: max0, max1, max2 | min0, min1, min2
    ALIGN 16
Lcase0:
        fmul    dword ptr [edx]
        fld     dword ptr [eax]
        fmulp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+4]
        fld     st(0)
        fmul    dword ptr [edx+4]
        faddp   st(2), st(0)
        fmul    dword ptr [eax+4]
        faddp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+8]
        fld     st(0)
        fmul    dword ptr [edx+8]
        faddp   st(2), st(0)
        fmul    dword ptr [eax+8]
        faddp   st(2), st(0)
        jmp     LSetSides

; case 1: min0, max1, max2 | max0, min1, min2
    ALIGN 16
Lcase1:
        fmul    dword ptr [eax]
        fld     dword ptr [edx]
        fmulp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+4]
        fld     st(0)
        fmul    dword ptr [edx+4]
        faddp   st(2), st(0)
        fmul    dword ptr [eax+4]
        faddp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+8]
        fld     st(0)
        fmul    dword ptr [edx+8]
        faddp   st(2), st(0)
        fmul    dword ptr [eax+8]
        faddp   st(2), st(0)
        jmp     LSetSides

; case 2: max0, min1, max2 | min0, max1, min2
    ALIGN 16
Lcase2:
        fmul    dword ptr [edx]
        fld     dword ptr [eax]
        fmulp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+4]
        fld     st(0)
        fmul    dword ptr [eax+4]
        faddp   st(2), st(0)
        fmul    dword ptr [edx+4]
        faddp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+8]
        fld     st(0)
        fmul    dword ptr [edx+8]
        faddp   st(2), st(0)
        fmul    dword ptr [eax+8]
        faddp   st(2), st(0)
        jmp     LSetSides

; case 3: min0, min1, max2 | max0, max1, min2
    ALIGN 16
Lcase3:
        fmul    dword ptr [eax]
        fld     dword ptr [edx]
        fmulp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+4]
        fld     st(0)
        fmul    dword ptr [eax+4]
        faddp   st(2), st(0)
        fmul    dword ptr [edx+4]
        faddp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+8]
        fld     st(0)
        fmul    dword ptr [edx+8]
        faddp   st(2), st(0)
        fmul    dword ptr [eax+8]
        faddp   st(2), st(0)
        jmp     LSetSides

; case 4: max0, max1, min2 | min0, min1, max2
    ALIGN 16
Lcase4:
        fmul    dword ptr [edx]
        fld     dword ptr [eax]
        fmulp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+4]
        fld     st(0)
        fmul    dword ptr [edx+4]
        faddp   st(2), st(0)
        fmul    dword ptr [eax+4]
        faddp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+8]
        fld     st(0)
        fmul    dword ptr [eax+8]
        faddp   st(2), st(0)
        fmul    dword ptr [edx+8]
        faddp   st(2), st(0)
        jmp     LSetSides

; case 5: min0, max1, min2 | max0, min1, max2
    ALIGN 16
Lcase5:
        fmul    dword ptr [eax]
        fld     dword ptr [edx]
        fmulp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+4]
        fld     st(0)
        fmul    dword ptr [edx+4]
        faddp   st(2), st(0)
        fmul    dword ptr [eax+4]
        faddp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+8]
        fld     st(0)
        fmul    dword ptr [eax+8]
        faddp   st(2), st(0)
        fmul    dword ptr [edx+8]
        faddp   st(2), st(0)
        jmp     LSetSides

; case 6: max0, min1, min2 | min0, max1, max2
    ALIGN 16
Lcase6:
        fmul    dword ptr [edx]
        fld     dword ptr [eax]
        fmulp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+4]
        fld     st(0)
        fmul    dword ptr [eax+4]
        faddp   st(2), st(0)
        fmul    dword ptr [edx+4]
        faddp   st(2), st(0)
        fld     dword ptr [ebx+pl_normal+8]
        fld     st(0)
        fmul    dword ptr [eax+8]
        faddp   st(2), st(0)
        fmul    dword ptr [edx+8]
        faddp   st(2), st(0)
        jmp     LSetSides

; case 7: min0, min1, min2 | max0, max1, max2
    ALIGN 16
Lcase7:
		fmul    dword ptr [eax]
		fld     dword ptr [edx]
		fmulp   st(2), st(0)
		fld     dword ptr [ebx+pl_normal+4]
		fld     st(0)
		fmul    dword ptr [eax+4]
		faddp   st(2), st(0)
		fmul    dword ptr [edx+4]
		faddp   st(2), st(0)
		fld     dword ptr [ebx+pl_normal+8]
		fld     st(0)
		fmul    dword ptr [eax+8]
		faddp   st(2), st(0)
		fmul    dword ptr [edx+8]
		faddp   st(2), st(0)
	ALIGN 16
LSetSides:
; Stack: st(0) = dist1, st(1) = dist2
		fcomp   dword ptr [ebx+pl_dist]      ; compare dist1 with p->dist, pop
		xor     ecx, ecx                     ; ecx = 0 (sides)
		fnstsw  ax                           ; capture status from dist1 compare
		fcomp   dword ptr [ebx+pl_dist]      ; compare dist2 with p->dist, pop
		and     ah, 1                        ; C0 from dist1
		xor     ah, 1                        ; !C0 -> (dist1 >= dist)
		add     cl, ah                       ; bit 0
		fnstsw  ax                           ; capture status from dist2 compare
		and     ah, 1                        ; C0 from dist2 -> (dist2 < dist)
		add     ah, ah                       ; shift to bit 1
		add     cl, ah                       ; bit 1
		mov     eax, ecx                     ; return sides
		pop     ecx
		ret
Lerror:
		call    BOPS_Error_
BoxOnPlaneSide_ endp
_TEXT ENDS

end