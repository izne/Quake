;=============================================================================
; math.asm - x86 assembly-language math routines
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/math.s.
; Three routines:
;   Invert24To16(val)               - 1 arg  -> EAX
;   TransformVector(in, out)        - 2 args -> EAX, EDX
;   BoxOnPlaneSide(emins, emaxs, p) - 3 args -> EAX, EDX, EBX
;
; CALLING CONVENTION (Watcom default 32-bit register ABI - see worlda.asm):
;   Only EAX/EDX are volatile; EBX/ECX/ESI/EDI/EBP are callee-saved.
;   Invert24To16:  EAX = val. Clobbers ECX -> preserve.
;   TransformVector: EAX = in, EDX = out (no remap needed, FPU only).
;   BoxOnPlaneSide: EAX = emins, EDX = emaxs, EBX = p (used directly).
;       Only ECX is saved/restored; EBX is preserved because it is never
;       modified. The zero-fxch version computes dist1/dist2 in parallel
;       x87 stack slots instead of remapping into the gas register layout.
;
; Globals (C, leading underscore, from quake486.map):
;   _vright, _vup, _vpn (vec3_t arrays, 12 bytes each)
;   BOPS_Error_ (C function, trailing underscore)
;
; Struct offsets (asm_i386_asm.h): pl_normal=0, pl_dist=12, pl_signbits=17
;=============================================================================

.386
.model  small

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

.data
    ALIGN 4
; jump table indexed by p->signbits (0..7)
Ljmptab dd Lcase0, Lcase1, Lcase2, Lcase3
        dd Lcase4, Lcase5, Lcase6, Lcase7

Ltemp   dd 0            ; scratch for 'd' sign test in LSetSides

.code
;=============================================================================
; Invert24To16_  (was: _Invert24To16)
; C: fixed16_t Invert24To16(fixed16_t val)   // (2^40 / val), or -1 if val<=256
; On entry: EAX = val
;=============================================================================
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
; Optimized for 486 / Am5x86: ZERO fxch, direct memory-operand FMULs,
; and keeps in[0..2] resident on the x87 stack across all 3 dot products.
;=============================================================================
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

        ; out[2] = DotProduct(in, vpn) — consume in[0], in[1], in[2] directly!
        fmul    dword ptr [_vpn]             ; in[0]*vp[0] | in[1] | in[2]
        fld     st(1)                        ; in[1] | in[0]*vp[0] | in[1] | in[2]
        fmul    dword ptr [_vpn+4]           ; in[1]*vp[1] | in[0]*vp[0] | in[1] | in[2]
        faddp   st(1), st(0)                 ; vp_xy | in[1] | in[2]
        fstp    st(1)                        ; vp_xy | in[2]  (pops used in[1]!)
        fld     st(1)                        ; in[2] | vp_xy | in[2]
        fmul    dword ptr [_vpn+8]           ; in[2]*vp[2] | vp_xy | in[2]
        faddp   st(1), st(0)                 ; out[2] | in[2]
        fstp    st(1)                        ; out[2]  (pops used in[2]!)
        fstp    dword ptr [edx+8]            ; (stack empty)
        ret
TransformVector_ endp


;=============================================================================
; BoxOnPlaneSide_  (was: _BoxOnPlaneSide)
; C: int BoxOnPlaneSide(vec3_t emins, vec3_t emaxs, mplane_t *p)
; On entry: EAX = emins, EDX = emaxs, EBX = p
; 486 version: no remap; ECX saved/restored, EBX left untouched.
;=============================================================================
BoxOnPlaneSide_ proc near
        push    ecx
        movzx   ecx, byte ptr [ebx+pl_signbits]
        cmp     ecx, 8
        jge     Lerror
        fld     dword ptr [ebx+pl_normal]    ; n0
        fld     st(0)                        ; n0 | n0
        jmp     dword ptr [Ljmptab+ecx*4]

; Entry: EAX = emins, EDX = emaxs, EBX = p
; Stack: st(0) = n0, st(1) = n0
; Exit:  st(0) = dist1, st(1) = dist2 (ZERO fxch!)

; case 0: max0, max1, max2 | min0, min1, min2
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
        ; BOPS_Error does not return (calls Sys_Error)
BoxOnPlaneSide_ endp

;=============================================================================
; Translation notes / optimization opportunities:
;
; 1. CALLING CONVENTION: Watcom register ABI. BoxOnPlaneSide's 3 args remapped
;    from EAX/EDX/EBX to gas's ECX(emins)/EBX(emaxs)/EDX(p) allocation.
;
; 2. CALLEE-SAVED: ECX preserved in Invert24To16; EBX+ECX in BoxOnPlaneSide.
;    TransformVector uses only EAX/EDX + FPU -> no preservation needed.
;
; 3. FPU SYNTAX: gas 'faddp %st(0),%st(N)' -> MASM 'faddp st(N),st(0)'
;    (operands reversed), but 'fxch %st(N)' -> 'fxch st(N)' (NO reversal).
;    Mixing these up (using st(1) for TransformVector's fxch) produced wrong
;    results in the functional test - caught and fixed. All verified by test.
;    'fld %st(0)' -> 'fld st(0)'; 'fcomps' -> 'fcomp dword ptr'.
;
; 4. JUMP TABLE: gas 'jmp Ljmptab(,%eax,4)' -> 'jmp dword ptr [Ljmptab+eax*4]'.
;    Table holds flat 32-bit code offsets, indexed by p->signbits (0..7).
;
; 5. LSetSides sign logic uses the FPU status word C0 bit (AH bit 0 after
;    fnstsw): !C0(dist1) -> sides bit 0, C0(dist2) -> sides bit 1.
;    Matches C: sides=(dist1>=dist) | ((dist2<dist)<<1).
;
; 6. OPT (possible): the 8 cases share an identical structure, differing only
;    in which of emins/emaxs each normal component multiplies. A data-driven
;    approach (table of min/max pointers per signbits) could replace the jump
;    table, but the FPU interleaving here is heavily hand-optimized for Pentium
;    pipeline latency - now optimized for 486.
;=============================================================================

end