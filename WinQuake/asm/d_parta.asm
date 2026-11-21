;=============================================================================
; d_parta.asm - 8-bpp particle drawing (replaces the old placeholder stub)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/d_parta.s.
; D_DrawParticle(particle_t *p) - 1 arg in EAX. Plus DP_1x1..DP_4x4 jump targets.
; Watcom register ABI: EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> preserved.
; FPU mappings (verified across math/d_polysa/d_draw):
;   fsubrs mem -> fsubr mem (st0=mem-st0);  fsubs mem -> fsub mem (st0=st0-mem)
;   fdivrs mem -> fdivr mem (st0=mem/st0);  fmul %st(i),%st(0) -> fmul st(0),st(i)
;   faddp %st(0),%st(N) -> faddp st(N),st(0);  fcomps -> fcomp (pops)
;=============================================================================

.386
.model  small

pt_org      equ 0
pt_color    equ 12
CYCLE       equ 128
TURB_TEX_SIZE equ 64

extrn   _r_origin:dword, _r_ppn:dword, _r_pup:dword, _r_pright:dword
extrn   _xcenter:dword, _ycenter:dword
extrn   _d_vrectbottom_particle:dword, _d_vrectright_particle:dword
extrn   _d_vrecty:dword, _d_vrectx:dword
extrn   _d_viewbuffer:dword, _d_scantable:dword, _d_pzbuffer:dword
extrn   _d_zrowbytes:dword, _d_zwidth:dword, _screenwidth:dword
extrn   _d_pix_shift:dword, _d_pix_min:dword, _d_pix_max:dword
extrn   _d_y_aspect_shift:dword

extrn   float_1:dword, float_point5:dword, float_particle_z_clip:dword
extrn   DP_32768:dword
extrn   DP_u:dword, DP_v:dword, DP_Count:dword, DP_Color:dword, DP_Pix:dword
extrn   izi:dword
extrn   DP_EntryTable:dword

public  D_DrawParticle_
public  DP_1x1, DP_2x2, DP_3x3, DP_4x4

.data
        ALIGN 4

.code

;=============================================================================
; D_DrawParticle_  (was: _D_DrawParticle)  -- EAX = particle_t *p
;=============================================================================
D_DrawParticle_ proc near
        push    ebp
        push    edi
        push    ebx
        push    ecx                     ; callee-saved, clobbered
        push    esi                     ; callee-saved, used in 2x2/3x3/4x4
        push    edx                     ; callee-saved, clobbered
        mov     edi, eax                ; edi = p

; transform point: local = p->org - r_origin
        fld     dword ptr [_r_origin]
        fsubr   dword ptr [edi+pt_org]          ; st0 = org[0]-origin[0]
        fld     dword ptr [edi+pt_org+4]
        fsub    dword ptr [_r_origin+4]
        fld     dword ptr [edi+pt_org+8]
        fsub    dword ptr [_r_origin+8]
        fxch    st(2)                    ; local0 | local1 | local2

; transformed[2] = Dot(local, r_ppn)
        fld     dword ptr [_r_ppn]
        fmul    st(0), st(1)
        fld     dword ptr [_r_ppn+4]
        fmul    st(0), st(3)
        fld     dword ptr [_r_ppn+8]
        fmul    st(0), st(5)
        fxch    st(2)
        faddp   st(1), st(0)
        faddp   st(1), st(0)             ; z | local0 | local1 | local2
        fld     st(0)
        fdivr   dword ptr [float_1]      ; 1/z | z | local0 | local1 | local2
        fxch    st(1)                    ; z | 1/z | local0 | local1 | local2

; if (z < PARTICLE_Z_CLIP) return (tested after loading r_pup)
        fcomp   dword ptr [float_particle_z_clip]   ; pops -> 1/z | local0 | local1 | local2
        fxch    st(3)                    ; local2 | local0 | local1 | 1/z

        fld     dword ptr [_r_pup]
        fmul    st(0), st(2)             ; dot0 | local2 | local0 | local1 | 1/z
        fld     dword ptr [_r_pup+4]

        fnstsw  ax
        test    ah, 1
        jnz     LPop6AndDone

; transformed[1] = Dot(local, r_pup)
        fmul    st(0), st(4)
        fld     dword ptr [_r_pup+8]
        fmul    st(0), st(3)
        fxch    st(2)
        faddp   st(1), st(0)
        faddp   st(1), st(0)             ; y | local2 | local0 | local1 | 1/z
        fxch    st(3)                    ; local1 | local2 | local0 | y | 1/z

; transformed[0] = Dot(local, r_pright)
        fmul    dword ptr [_r_pright+4]
        fxch    st(2)
        fmul    dword ptr [_r_pright]
        fxch    st(1)
        fmul    dword ptr [_r_pright+8]
        fxch    st(2)
        faddp   st(1), st(0)
        faddp   st(1), st(0)             ; x | y | 1/z
        fxch    st(1)                    ; y | x | 1/z

; project the point
        fmul    st(0), st(2)             ; y/z | x | 1/z
        fxch    st(1)
        fmul    st(0), st(2)             ; x/z | y/z | 1/z
        fxch    st(1)                    ; y/z | x/z | 1/z
        fsubr   dword ptr [_ycenter]     ; v | x/z | 1/z
        fxch    st(1)
        fadd    dword ptr [_xcenter]     ; u | v | 1/z
        fxch    st(1)
        fadd    dword ptr [float_point5] ; v | u | 1/z
        fxch    st(1)
        fadd    dword ptr [float_point5] ; u | v | 1/z
        fxch    st(2)                    ; 1/z | v | u
        fmul    dword ptr [DP_32768]     ; 1/z*0x8000 | v | u
        fxch    st(2)                    ; u | v | 1/z*0x8000

        fistp   dword ptr [DP_u]         ; v | 1/z*0x8000
        fistp   dword ptr [DP_v]         ; 1/z*0x8000
        mov     eax, [DP_u]
        mov     edx, [DP_v]

; bounds check
        mov     ebx, [_d_vrectbottom_particle]
        mov     ecx, [_d_vrectright_particle]
        cmp     edx, ebx
        jg      LPop1AndDone
        cmp     eax, ecx
        jg      LPop1AndDone
        mov     ebx, [_d_vrecty]
        mov     ecx, [_d_vrectx]
        cmp     edx, ebx
        jl      LPop1AndDone
        cmp     eax, ecx
        jl      LPop1AndDone

        fld     dword ptr [edi+pt_color] ; color | 1/z*0x8000
        fistp   dword ptr [DP_Color]     ; 1/z*0x8000

        mov     ebx, [_d_viewbuffer]
        add     ebx, eax
        mov     edi, [_d_scantable+edx*4]
        imul    edx, [_d_zrowbytes]
        lea     edx, [edx+eax*2]
        mov     eax, [_d_pzbuffer]
        fistp   dword ptr [izi]
        add     edi, ebx
        add     edx, eax

; pix = izi >> d_pix_shift, clamp to [min,max]
        mov     eax, [izi]
        mov     ecx, [_d_pix_shift]
        shr     eax, cl
        mov     ebp, [izi]
        mov     ebx, [_d_pix_min]
        mov     ecx, [_d_pix_max]
        cmp     eax, ebx
        jnl     LTestPixMax
        mov     eax, ebx
        jmp     LTestDone
LTestPixMax:
        cmp     eax, ecx
        jng     LTestDone
        mov     eax, ecx
LTestDone:
        mov     ch, byte ptr [DP_Color]

        mov     ebx, [_d_y_aspect_shift]
        test    ebx, ebx
        jnz     LDefault
        cmp     eax, 4
        ja      LDefault
        jmp     dword ptr [DP_EntryTable+eax*4-4]

; 1x1
DP_1x1:
        cmp [edx], bp
        jg      LDone
        mov     [edx], bp
        mov     [edi], ch
        jmp     LDone

; 2x2
DP_2x2:
        push    esi
        mov     ebx, [_screenwidth]
        mov     esi, [_d_zrowbytes]
        cmp [edx], bp
        jg      L2x2_1
        mov     [edx], bp
        mov     [edi], ch
L2x2_1:
        cmp [edx+2], bp
        jg      L2x2_2
        mov     [edx+2], bp
        mov     [edi+1], ch
L2x2_2:
        cmp [edx+esi], bp
        jg      L2x2_3
        mov     [edx+esi], bp
        mov     [edi+ebx], ch
L2x2_3:
        cmp [edx+esi+2], bp
        jg      L2x2_4
        mov     [edx+esi+2], bp
        mov     [edi+ebx+1], ch
L2x2_4:
        pop     esi
        jmp     LDone

; 3x3
DP_3x3:
        push    esi
        mov     ebx, [_screenwidth]
        mov     esi, [_d_zrowbytes]
        cmp [edx], bp
        jg      L3x3_1
        mov     [edx], bp
        mov     [edi], ch
L3x3_1:
        cmp [edx+2], bp
        jg      L3x3_2
        mov     [edx+2], bp
        mov     [edi+1], ch
L3x3_2:
        cmp [edx+4], bp
        jg      L3x3_3
        mov     [edx+4], bp
        mov     [edi+2], ch
L3x3_3:
        cmp [edx+esi], bp
        jg      L3x3_4
        mov     [edx+esi], bp
        mov     [edi+ebx], ch
L3x3_4:
        cmp [edx+esi+2], bp
        jg      L3x3_5
        mov     [edx+esi+2], bp
        mov     [edi+ebx+1], ch
L3x3_5:
        cmp [edx+esi+4], bp
        jg      L3x3_6
        mov     [edx+esi+4], bp
        mov     [edi+ebx+2], ch
L3x3_6:
        cmp [edx+esi*2], bp
        jg      L3x3_7
        mov     [edx+esi*2], bp
        mov     [edi+ebx*2], ch
L3x3_7:
        cmp [edx+esi*2+2], bp
        jg      L3x3_8
        mov     [edx+esi*2+2], bp
        mov     [edi+ebx*2+1], ch
L3x3_8:
        cmp [edx+esi*2+4], bp
        jg      L3x3_9
        mov     [edx+esi*2+4], bp
        mov     [edi+ebx*2+2], ch
L3x3_9:
        pop     esi
        jmp     LDone

; 4x4
DP_4x4:
        push    esi
        mov     ebx, [_screenwidth]
        mov     esi, [_d_zrowbytes]
        ; row 0
        cmp     word ptr [edx], bp
        jg      L4x4_1
        mov     [edx], bp
        mov     [edi], ch
L4x4_1: cmp     word ptr [edx+2], bp
        jg      L4x4_2
        mov     [edx+2], bp
        mov     [edi+1], ch
L4x4_2: cmp     word ptr [edx+4], bp
        jg      L4x4_3
        mov     [edx+4], bp
        mov     [edi+2], ch
L4x4_3: cmp     word ptr [edx+6], bp
        jg      L4x4_4
        mov     [edx+6], bp
        mov     [edi+3], ch
L4x4_4:
        ; row 1
        cmp     word ptr [edx+esi], bp
        jg      L4x4_5
        mov     [edx+esi], bp
        mov     [edi+ebx], ch
L4x4_5: cmp     word ptr [edx+esi+2], bp
        jg      L4x4_6
        mov     [edx+esi+2], bp
        mov     [edi+ebx+1], ch
L4x4_6: cmp     word ptr [edx+esi+4], bp
        jg      L4x4_7
        mov     [edx+esi+4], bp
        mov     [edi+ebx+2], ch
L4x4_7: cmp     word ptr [edx+esi+6], bp
        jg      L4x4_8
        mov     [edx+esi+6], bp
        mov     [edi+ebx+3], ch
L4x4_8:
        lea     edx, [edx+esi*2]
        lea     edi, [edi+ebx*2]
        ; row 2
        cmp     word ptr [edx], bp
        jg      L4x4_9
        mov     [edx], bp
        mov     [edi], ch
L4x4_9: cmp     word ptr [edx+2], bp
        jg      L4x4_10
        mov     [edx+2], bp
        mov     [edi+1], ch
L4x4_10: cmp    word ptr [edx+4], bp
        jg      L4x4_11
        mov     [edx+4], bp
        mov     [edi+2], ch
L4x4_11: cmp    word ptr [edx+6], bp
        jg      L4x4_12
        mov     [edx+6], bp
        mov     [edi+3], ch
L4x4_12:
        ; row 3
        cmp     word ptr [edx+esi], bp
        jg      L4x4_13
        mov     [edx+esi], bp
        mov     [edi+ebx], ch
L4x4_13: cmp    word ptr [edx+esi+2], bp
        jg      L4x4_14
        mov     [edx+esi+2], bp
        mov     [edi+ebx+1], ch
L4x4_14: cmp    word ptr [edx+esi+4], bp
        jg      L4x4_15
        mov     [edx+esi+4], bp
        mov     [edi+ebx+2], ch
L4x4_15: cmp    word ptr [edx+esi+6], bp
        jg      L4x4_16
        mov     [edx+esi+6], bp
        mov     [edi+ebx+3], ch
L4x4_16:
        pop     esi
        jmp     LDone

; default case
LDefault:
        mov     ebx, eax
        mov     [DP_Pix], eax
        mov     cl, byte ptr [_d_y_aspect_shift]
        shl     ebx, cl
LGenRowLoop:
        mov     eax, [DP_Pix]
LGenColLoop:
        cmp [edx+eax*2-2], bp
        jg      LGSkip
        mov     [edx+eax*2-2], bp
        mov     [edi+eax-1], ch
LGSkip:
        dec     eax
        jnz     LGenColLoop
        add     edx, [_d_zrowbytes]
        add     edi, [_screenwidth]
        dec     ebx
        jnz     LGenRowLoop

LDone:
        pop     edx
        pop     esi
        pop     ecx
        pop     ebx
        pop     edi
        pop     ebp
        ret

LPop6AndDone:
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)
LPop1AndDone:
        fstp    st(0)
        jmp     LDone
D_DrawParticle_ endp

end
