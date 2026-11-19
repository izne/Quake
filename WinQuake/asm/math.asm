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
;   BoxOnPlaneSide: EAX = emins, EDX = emaxs, EBX = p.
;       Remap to gas internal allocation: ECX=emins, EBX=emaxs, EDX=p.
;       Preserve EBX + ECX.
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
        mov     ecx, eax            ; ecx = val
        mov     edx, 0100h          ; 0x100 (high word of 2^40 dividend)
        cmp     ecx, edx
        jle     short LOutOfRange
        xor     eax, eax            ; eax = 0 (low word of dividend)
        div     ecx                 ; edx:eax / ecx -> eax = quotient
        pop     ecx
        ret
LOutOfRange:
        mov     eax, 0FFFFFFFFh
        pop     ecx
        ret
Invert24To16_ endp


;=============================================================================
; TransformVector_  (was: _TransformVector)
; C: void TransformVector(vec3_t in, vec3_t out)
;       out[0] = DotProduct(in, vright);
;       out[1] = DotProduct(in, vup);
;       out[2] = DotProduct(in, vpn);
; On entry: EAX = in, EDX = out (already in gas's expected registers)
; Uses only EAX/EDX + FPU -> no callee-saved regs to preserve.
;=============================================================================
TransformVector_ proc near
        ; eax = in, edx = out (from Watcom ABI, no remap needed)
        fld     dword ptr [eax]              ; in[0]
        fmul    dword ptr [_vright]          ; in[0]*vright[0]
        fld     dword ptr [eax]              ; in[0] | in[0]*vright[0]
        fmul    dword ptr [_vup]             ; in[0]*vup[0] | ...
        fld     dword ptr [eax]              ; in[0] | in[0]*vup[0] | ...
        fmul    dword ptr [_vpn]             ; in[0]*vpn[0] | ...  (st2=vright prod)

        fld     dword ptr [eax+4]            ; in[1] | ...
        fmul    dword ptr [_vright+4]        ; in[1]*vright[1] | ...
        fld     dword ptr [eax+4]            ; in[1] | in[1]*vright[1] | ...
        fmul    dword ptr [_vup+4]           ; in[1]*vup[1] | ...
        fld     dword ptr [eax+4]            ; in[1] | in[1]*vup[1] | ...
        fmul    dword ptr [_vpn+4]           ; in[1]*vpn[1] | ...
        fxch    st(2)                        ; in[1]*vright[1] | in[1]*vup[1] | in[1]*vpn[1] | ...

        faddp   st(5), st(0)                 ; += vright accum
        faddp   st(3), st(0)                 ; += vup accum
        faddp   st(1), st(0)                 ; vpn_accum | vup_accum | vright_accum

        fld     dword ptr [eax+8]            ; in[2] | ...
        fmul    dword ptr [_vright+8]        ; in[2]*vright[2] | ...
        fld     dword ptr [eax+8]            ; in[2] | in[2]*vright[2] | ...
        fmul    dword ptr [_vup+8]           ; in[2]*vup[2] | ...
        fld     dword ptr [eax+8]            ; in[2] | in[2]*vup[2] | ...
        fmul    dword ptr [_vpn+8]           ; in[2]*vpn[2] | ...
        fxch    st(2)                        ; in[2]*vright[2] | in[2]*vup[2] | in[2]*vpn[2] | ...

        faddp   st(5), st(0)
        faddp   st(3), st(0)
        faddp   st(1), st(0)                 ; vpn_accum | vup_accum | vright_accum

        fstp    dword ptr [edx+8]            ; out[2]
        fstp    dword ptr [edx+4]            ; out[1]
        fstp    dword ptr [edx]              ; out[0]
        ret
TransformVector_ endp


;=============================================================================
; BoxOnPlaneSide_  (was: _BoxOnPlaneSide)
; C: int BoxOnPlaneSide(vec3_t emins, vec3_t emaxs, mplane_t *p)
; On entry: EAX = emins, EDX = emaxs, EBX = p
; Remap to gas internal: ECX=emins, EBX=emaxs, EDX=p
;=============================================================================
BoxOnPlaneSide_ proc near
        push    ebx                 ; callee-saved
        push    ecx                 ; callee-saved

        mov     ecx, eax            ; ecx = emins
        mov     eax, edx            ; eax = emaxs (temp)
        mov     edx, ebx            ; edx = p
        mov     ebx, eax            ; ebx = emaxs

        xor     eax, eax            ; eax = 0 (for signbits index)
        mov     al, [edx+pl_signbits]        ; al = p->signbits
        cmp     al, 8
        jge     Lerror
        fld     dword ptr [edx+pl_normal]    ; p->normal[0]
        fld     st(0)                        ; normal[0] | normal[0]
        jmp     dword ptr [Ljmptab+eax*4]

; case 0: dist1 = n0*max0+n1*max1+n2*max2 ; dist2 = n0*min0+n1*min1+n2*min2
Lcase0:
        fmul    dword ptr [ebx]              ; n0*max0
        fld     dword ptr [edx+pl_normal+4]
        fxch    st(2)
        fmul    dword ptr [ecx]              ; n0*min0
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ebx+4]            ; n1*max1
        fld     dword ptr [edx+pl_normal+8]
        fxch    st(2)
        fmul    dword ptr [ecx+4]            ; n1*min1
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ebx+8]            ; n2*max2
        fxch    st(5)
        faddp   st(3), st(0)
        fmul    dword ptr [ecx+8]            ; n2*min2
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        jmp     LSetSides

; case 1: dist1 = n0*min0+n1*max1+n2*max2 ; dist2 = n0*max0+n1*min1+n2*min2
Lcase1:
        fmul    dword ptr [ecx]
        fld     dword ptr [edx+pl_normal+4]
        fxch    st(2)
        fmul    dword ptr [ebx]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ebx+4]
        fld     dword ptr [edx+pl_normal+8]
        fxch    st(2)
        fmul    dword ptr [ecx+4]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ebx+8]
        fxch    st(5)
        faddp   st(3), st(0)
        fmul    dword ptr [ecx+8]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        jmp     LSetSides

; case 2: dist1 = n0*max0+n1*min1+n2*max2 ; dist2 = n0*min0+n1*max1+n2*min2
Lcase2:
        fmul    dword ptr [ebx]
        fld     dword ptr [edx+pl_normal+4]
        fxch    st(2)
        fmul    dword ptr [ecx]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ecx+4]
        fld     dword ptr [edx+pl_normal+8]
        fxch    st(2)
        fmul    dword ptr [ebx+4]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ebx+8]
        fxch    st(5)
        faddp   st(3), st(0)
        fmul    dword ptr [ecx+8]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        jmp     LSetSides

; case 3: dist1 = n0*min0+n1*min1+n2*max2 ; dist2 = n0*max0+n1*max1+n2*min2
Lcase3:
        fmul    dword ptr [ecx]
        fld     dword ptr [edx+pl_normal+4]
        fxch    st(2)
        fmul    dword ptr [ebx]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ecx+4]
        fld     dword ptr [edx+pl_normal+8]
        fxch    st(2)
        fmul    dword ptr [ebx+4]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ebx+8]
        fxch    st(5)
        faddp   st(3), st(0)
        fmul    dword ptr [ecx+8]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        jmp     LSetSides

; case 4: dist1 = n0*max0+n1*max1+n2*min2 ; dist2 = n0*min0+n1*min1+n2*max2
Lcase4:
        fmul    dword ptr [ebx]
        fld     dword ptr [edx+pl_normal+4]
        fxch    st(2)
        fmul    dword ptr [ecx]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ebx+4]
        fld     dword ptr [edx+pl_normal+8]
        fxch    st(2)
        fmul    dword ptr [ecx+4]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ecx+8]
        fxch    st(5)
        faddp   st(3), st(0)
        fmul    dword ptr [ebx+8]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        jmp     LSetSides

; case 5: dist1 = n0*min0+n1*max1+n2*min2 ; dist2 = n0*max0+n1*min1+n2*max2
Lcase5:
        fmul    dword ptr [ecx]
        fld     dword ptr [edx+pl_normal+4]
        fxch    st(2)
        fmul    dword ptr [ebx]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ebx+4]
        fld     dword ptr [edx+pl_normal+8]
        fxch    st(2)
        fmul    dword ptr [ecx+4]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ecx+8]
        fxch    st(5)
        faddp   st(3), st(0)
        fmul    dword ptr [ebx+8]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        jmp     LSetSides

; case 6: dist1 = n0*max0+n1*min1+n2*min2 ; dist2 = n0*min0+n1*max1+n2*max2
Lcase6:
        fmul    dword ptr [ebx]
        fld     dword ptr [edx+pl_normal+4]
        fxch    st(2)
        fmul    dword ptr [ecx]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ecx+4]
        fld     dword ptr [edx+pl_normal+8]
        fxch    st(2)
        fmul    dword ptr [ebx+4]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ecx+8]
        fxch    st(5)
        faddp   st(3), st(0)
        fmul    dword ptr [ebx+8]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        jmp     LSetSides

; case 7: dist1 = n0*min0+n1*min1+n2*min2 ; dist2 = n0*max0+n1*max1+n2*max2
Lcase7:
        fmul    dword ptr [ecx]
        fld     dword ptr [edx+pl_normal+4]
        fxch    st(2)
        fmul    dword ptr [ebx]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ecx+4]
        fld     dword ptr [edx+pl_normal+8]
        fxch    st(2)
        fmul    dword ptr [ebx+4]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [ecx+8]
        fxch    st(5)
        faddp   st(3), st(0)
        fmul    dword ptr [ebx+8]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        ; falls through to LSetSides

LSetSides:
;	sides = 0;
;	if (dist1 >= p->dist) sides = 1;
;	if (dist2 < p->dist)  sides |= 2;
        faddp   st(2), st(0)                 ; dist1 | dist2
        fcomp   dword ptr [edx+pl_dist]      ; compare dist1 with p->dist, pop
        xor     ecx, ecx                     ; ecx = 0 (sides)
        fnstsw  ax                           ; capture status from dist1 compare
        fcomp   dword ptr [edx+pl_dist]      ; compare dist2 with p->dist, pop
        and     ah, 1                        ; C0 from dist1 (stored in ax)
        xor     ah, 1                        ; !C0 -> (dist1 >= dist)
        add     cl, ah                       ; bit 0
        fnstsw  ax                           ; capture status from dist2 compare
        and     ah, 1                        ; C0 from dist2 -> (dist2 < dist)
        add     ah, ah                       ; shift to bit 1
        add     cl, ah                       ; bit 1
        mov     eax, ecx                     ; return sides
        pop     ecx
        pop     ebx
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
;    table, but the FPU interleaving here is heavily hand-optimized for 486
;    pipeline latency - kept faithful.
;=============================================================================

end