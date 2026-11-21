;=============================================================================
; r_drawa.asm - alias edge clipping/emission (replaces the old stub)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/r_drawa.s.
; R_ClipEdge(mvertex_t *pv0, mvertex_t *pv1, clipplane_t *clip)
; Watcom register ABI: EAX=pv0, EDX=pv1, EBX=clip.
; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> preserved.
; FPU mapping verified style (fsubrp/fdivrp/faddp -> fXXXp st(N),st(0) etc.)
;=============================================================================

.386
.model  small

FULLY_CLIPPED_CACHED equ 080000000h
FRAMECOUNT_MASK      equ 07FFFFFFFh
NEAR_CLIP            equ 001h        ; placeholder; real value from data
SURF_T_SHIFT         equ 6

mv_position     equ 0
mv_size         equ 12
cp_normal       equ 0
cp_dist         equ 12
cp_next         equ 16
cp_leftedge     equ 20
et_owner        equ 28
et_surfs        equ 16
et_nearzi       equ 24
et_u            equ 0
et_u_step       equ 4
et_next         equ 12
et_nextremove   equ 20
et_size         equ 32

rd_vrect_x_adj_shift20      equ 76
rd_vrectright_adj_shift20   equ 80
rd_fvrectx_adj              equ 68
rd_fvrectright_adj          equ 84
rd_fvrecty_adj              equ 72
rd_fvrectbottom_adj         equ 88

extrn   _r_refdef:dword, _r_lastvertvalid:dword, _r_lzi1:dword, _r_u1:dword
extrn   _r_v1:dword, _r_ceilv1:dword, _r_nearzi:dword, _r_nearzionly:dword
extrn   _cacheoffset:dword, _r_framecount:dword, _edge_p:dword, _r_pedge:dword
extrn   _r_emitted:dword, _surface_p:dword, _surfaces:dword
extrn   _r_leftclipped:dword, _r_leftexit:dword, _r_rightclipped:dword
extrn   _r_rightexit:dword, _r_leftenter:dword, _r_rightenter:dword
extrn   _modelorg:dword, _xscale:dword, _yscale:dword, _xcenter:dword, _ycenter:dword
extrn   _vpn:dword, _vright:dword, _vup:dword
extrn   _newedges:dword, _removeedges:dword
extrn   float_1:dword, float_point5:dword
extrn   fp_1m:dword, fp_1m_minus_1:dword
extrn   _ceil_cw:word, _single_cw:word

public  R_ClipEdge_

.data
        ALIGN 4
Ld0     dd 0.0
Ld1     dd 0.0
Lstack  dd 0
Lfp_near_clip dd 0.01
Lceilv0 dd 0
Lv      dd 0
Lu0     dd 0
Lv0     dd 0
Lzi0    dd 0

.code

;=============================================================================
; R_ClipEdge_  (was: _R_ClipEdge)  -- EAX=pv0, EDX=pv1, EBX=clip
; Note: because this function calls itself recursively and uses call LTransform-
; AndProject (a local near proc), we keep the register flow close to the gas.
;=============================================================================
R_ClipEdge_ proc near
        push    esi
        push    edi
        push    ebx
        push    ecx                     ; callee-saved, clobbered
        push    edx                     ; callee-saved under Watcom ABI
        push    ebp                     ; callee-saved, clobbered
        mov     [Lstack], esp           ; for clearing stack later
        ; Args on entry: EAX=pv0, EDX=pv1, EBX=clip (all already in place)
        mov     esi, eax                ; esi = pv0
        ; edx already pv1, ebx already clip
        test    ebx, ebx
        jz      Lemit

Lcliploop:
; d0 = Dot(pv0->pos, clip->normal) - clip->dist
; d1 = Dot(pv1->pos, clip->normal) - clip->dist
        fld     dword ptr [esi+mv_position+0]
        fmul    dword ptr [ebx+cp_normal+0]
        fld     dword ptr [esi+mv_position+4]
        fmul    dword ptr [ebx+cp_normal+4]
        fld     dword ptr [esi+mv_position+8]
        fmul    dword ptr [ebx+cp_normal+8]
        fxch    st(1)
        faddp   st(2), st(0)
        fld     dword ptr [edx+mv_position+0]
        fmul    dword ptr [ebx+cp_normal+0]
        fld     dword ptr [edx+mv_position+4]
        fmul    dword ptr [ebx+cp_normal+4]
        fld     dword ptr [edx+mv_position+8]
        fmul    dword ptr [ebx+cp_normal+8]
        fxch    st(1)
        faddp   st(2), st(0)
        fxch    st(3)
        faddp   st(2), st(0)
        faddp   st(2), st(0)
        fsub    dword ptr [ebx+cp_dist]
        fxch    st(1)
        fsub    dword ptr [ebx+cp_dist]
        fxch    st(1)
        fstp    dword ptr [Ld0]
        fstp    dword ptr [Ld1]

        mov     eax, [Ld0]
        mov     ecx, [Ld1]
        or      ecx, eax
        js      LC2

Lcontinue:
        mov     ebx, [ebx+cp_next]
        test    ebx, ebx
        jnz     Lcliploop

Lemit:
        fldcw   word ptr [_ceil_cw]
        cmp     dword ptr [_r_lastvertvalid], 0
        jz      LCalcFirst
        mov     eax, [_r_lzi1]
        mov     ecx, [_r_u1]
        mov     [Lzi0], eax
        mov     [Lu0], ecx
        mov     ecx, [_r_v1]
        mov     eax, [_r_ceilv1]
        mov     [Lv0], ecx
        mov     [Lceilv0], eax
        jmp     LCalcSecond

LCalcFirst:
        call    LTransformAndProject      ; v0 | lzi0 | u0
        fst     dword ptr [Lv0]
        fxch    st(2)
        fstp    dword ptr [Lu0]
        fstp    dword ptr [Lzi0]
        fistp   dword ptr [Lceilv0]
LCalcSecond:
        mov     esi, edx                 ; world = pv1->position
        call    LTransformAndProject      ; v1 | lzi1 | u1
        fld     dword ptr [Lu0]
        fxch    st(3)
        fld     dword ptr [Lzi0]
        fxch    st(3)
        fld     dword ptr [Lv0]
        fxch    st(3)
        fist    dword ptr [_r_ceilv1]
        fldcw   word ptr [_single_cw]
        fst     dword ptr [_r_v1]
        fxch    st(4)
        fcom    st(1)
        fnstsw  ax
        test    ah, 1
        jz      LP0
        fstp    st(0)
        fld     st(0)
LP0:
        fxch    st(1)
        fstp    dword ptr [_r_lzi1]
        fxch    st(1)
        fst     dword ptr [_r_u1]
        fxch    st(1)
        fcom    dword ptr [_r_nearzi]
        fnstsw  ax
        test    ah, 045h
        jnz     LNZ1
        fst     dword ptr [_r_nearzi]
LNZ1:
        mov     eax, [_r_nearzionly]
        test    eax, eax
        jz      LNZ2
LPop5AndDone:
        mov     eax, [_cacheoffset]
        mov     edx, [_r_framecount]
        cmp     eax, 07FFFFFFFh
        jz      LDoPop
        and     edx, FRAMECOUNT_MASK
        or      edx, FULLY_CLIPPED_CACHED
        mov     [_cacheoffset], edx
LDoPop:
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)
        fstp    st(0)
        jmp     Ldone

LNZ2:
        mov     ebx, [Lceilv0]
        mov     edi, [_edge_p]
        mov     ecx, [_r_ceilv1]
        mov     edx, edi
        mov     esi, [_r_pedge]
        add     edx, et_size
        cmp     ebx, ecx
        jz      LPop5AndDone
        mov     eax, [_r_pedge]
        mov     [edi+et_owner], eax
        fstp    dword ptr [edi+et_nearzi]
        jc      LSide0

LSide1:
        fsubp   st(3), st(0)
        fsub    st(0), st(1)
        fdivp   st(2), st(0)
        mov     dword ptr [_r_emitted], 1
        mov     [_edge_p], edx
        mov     eax, [edx]
        mov     eax, ecx
        lea     ecx, [ebx-1]
        mov     ebx, eax
        mov     eax, [_surface_p]
        mov     esi, [_surfaces]
        sub     edx, edx
        sub     eax, esi
        shr     eax, SURF_T_SHIFT
        mov     [edi+et_surfs], edx
        mov     [edi+et_surfs+2], eax
        sub     esi, esi
        mov     [Lv], ebx
        fild    dword ptr [Lv]
        fsubrp  st(1), st(0)
        fmul    st(0), st(1)
        fadd    dword ptr [_r_u1]
        jmp     LSideDone
LSide0:
        fsub    st(0), st(3)
        fxch    st(2)
        fsub    st(0), st(1)
        fdivp   st(2), st(0)
        mov     dword ptr [_r_emitted], 1
        mov     [_edge_p], edx
        mov     eax, [edx]
        dec     ecx
        mov     eax, [_surface_p]
        mov     esi, [_surfaces]
        sub     edx, edx
        sub     eax, esi
        shr     eax, SURF_T_SHIFT
        mov     [edi+et_surfs+2], edx
        mov     [edi+et_surfs], eax
        mov     esi, 1
        mov     [Lv], ebx
        fild    dword ptr [Lv]
        fsubrp  st(1), st(0)
        fmul    st(0), st(1)
        faddp   st(2), st(0)
        fxch    st(1)
LSideDone:
        fmul    dword ptr [fp_1m]
        fxch    st(1)
        fmul    dword ptr [fp_1m]
        fxch    st(1)
        fadd    dword ptr [fp_1m_minus_1]
        fxch    st(1)
        fistp   dword ptr [edi+et_u_step]
        fistp   dword ptr [edi+et_u]
        mov     eax, [edi+et_u]
        mov     edx, [_r_refdef+rd_vrect_x_adj_shift20]
        cmp     eax, edx
        jl      LP4
        mov     edx, [_r_refdef+rd_vrectright_adj_shift20]
        cmp     eax, edx
        jng     LP5
LP4:
        mov     [edi+et_u], edx
        mov     eax, edx
LP5:
        add     eax, esi
        mov     esi, [_newedges+ebx*4]
        test    esi, esi
        jz      LDoFirst
        cmp     dword ptr [esi+et_u], eax
        jl      LNotFirst
LDoFirst:
        mov     [edi+et_next], esi
        mov     [_newedges+ebx*4], edi
        jmp     LSetRemove
LNotFirst:
LFindInsertLoop:
        mov     edx, esi
        mov     esi, [esi+et_next]
        test    esi, esi
        jz      LInsertFound
        cmp     dword ptr [esi+et_u], eax
        jl      LFindInsertLoop
LInsertFound:
        mov     [edi+et_next], esi
        mov     [edx+et_next], edi
LSetRemove:
        mov     eax, [_removeedges+ecx*4]
        mov     [_removeedges+ecx*4], edi
        mov     [edi+et_nextremove], eax
Ldone:
        mov     esp, [Lstack]
        pop     ebp
        pop     edx
        pop     ecx
        pop     ebx
        pop     edi
        pop     esi
        ret

; at least one point clipped
LC2:
        test    eax, eax
        jns     LC1
        mov     eax, [Ld1]
        test    eax, eax
        jns     LC3
        mov     eax, [_r_leftclipped]
        mov     ecx, [_r_pedge]
        test    eax, eax
        jnz     Ldone
        mov     eax, [_r_framecount]
        and     eax, FRAMECOUNT_MASK
        or      eax, FULLY_CLIPPED_CACHED
        mov     [_cacheoffset], eax
        jmp     Ldone
LC1:
        ; only point1 clipped: f = d0/(d0-d1)
        fld     dword ptr [Ld0]
        fld     dword ptr [Ld1]
        fsubr   st(0), st(1)
        mov     dword ptr [_cacheoffset], 07FFFFFFFh
        fdivp   st(1), st(0)
        sub     esp, mv_size
        fld     dword ptr [edx+mv_position+8]
        fsub    dword ptr [esi+mv_position+8]
        fld     dword ptr [edx+mv_position+4]
        fsub    dword ptr [esi+mv_position+4]
        fld     dword ptr [edx+mv_position+0]
        fsub    dword ptr [esi+mv_position+0]
        mov     edx, esp
        mov     eax, [ebx+cp_leftedge]
        test    al, al
        fmul    st(0), st(3)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(2)
        fmulp   st(3), st(0)
        fadd    dword ptr [esi+mv_position+0]
        fxch    st(1)
        fadd    dword ptr [esi+mv_position+4]
        fxch    st(2)
        fadd    dword ptr [esi+mv_position+8]
        fxch    st(1)
        fstp    dword ptr [esp+mv_position+0]
        fstp    dword ptr [esp+mv_position+8]
        fstp    dword ptr [esp+mv_position+4]
        jz      Ltestright
        mov     dword ptr [_r_leftclipped], 1
        mov     eax, [esp+mv_position+0]
        mov     [_r_leftexit+mv_position+0], eax
        mov     eax, [esp+mv_position+4]
        mov     [_r_leftexit+mv_position+4], eax
        mov     eax, [esp+mv_position+8]
        mov     [_r_leftexit+mv_position+8], eax
        jmp     Lcontinue
Ltestright:
        test    ah, ah
        jz      Lcontinue
        mov     dword ptr [_r_rightclipped], 1
        mov     eax, [esp+mv_position+0]
        mov     [_r_rightexit+mv_position+0], eax
        mov     eax, [esp+mv_position+4]
        mov     [_r_rightexit+mv_position+4], eax
        mov     eax, [esp+mv_position+8]
        mov     [_r_rightexit+mv_position+8], eax
        jmp     Lcontinue
LC3:
        mov     dword ptr [_r_lastvertvalid], 0
        fld     dword ptr [Ld0]
        fld     dword ptr [Ld1]
        fsubr   st(0), st(1)
        mov     dword ptr [_cacheoffset], 07FFFFFFFh
        fdivp   st(1), st(0)
        sub     esp, mv_size
        fld     dword ptr [edx+mv_position+8]
        fsub    dword ptr [esi+mv_position+8]
        fld     dword ptr [edx+mv_position+4]
        fsub    dword ptr [esi+mv_position+4]
        fld     dword ptr [edx+mv_position+0]
        fsub    dword ptr [esi+mv_position+0]
        mov     eax, [ebx+cp_leftedge]
        test    al, al
        fmul    st(0), st(3)
        fxch    st(1)
        fmul    st(0), st(3)
        fxch    st(2)
        fmulp   st(3), st(0)
        fadd    dword ptr [esi+mv_position+0]
        fxch    st(1)
        fadd    dword ptr [esi+mv_position+4]
        fxch    st(2)
        fadd    dword ptr [esi+mv_position+8]
        fxch    st(1)
        fstp    dword ptr [esp+mv_position+0]
        fstp    dword ptr [esp+mv_position+8]
        fstp    dword ptr [esp+mv_position+4]
        mov     esi, esp
        jz      Ltestright2
        mov     dword ptr [_r_leftclipped], 1
        mov     eax, [esp+mv_position+0]
        mov     [_r_leftenter+mv_position+0], eax
        mov     eax, [esp+mv_position+4]
        mov     [_r_leftenter+mv_position+4], eax
        mov     eax, [esp+mv_position+8]
        mov     [_r_leftenter+mv_position+8], eax
        jmp     Lcontinue
Ltestright2:
        test    ah, ah
        jz      Lcontinue
        mov     dword ptr [_r_rightclipped], 1
        mov     eax, [esp+mv_position+0]
        mov     [_r_rightenter+mv_position+0], eax
        mov     eax, [esp+mv_position+4]
        mov     [_r_rightenter+mv_position+4], eax
        mov     eax, [esp+mv_position+8]
        mov     [_r_rightenter+mv_position+8], eax
        jmp     Lcontinue

;---- LTransformAndProject: ESI = point; result v|lzi|u on FP stack ----------
LTransformAndProject proc near
        fld     dword ptr [esi+mv_position+0]
        fsub    dword ptr [_modelorg+0]
        fld     dword ptr [esi+mv_position+4]
        fsub    dword ptr [_modelorg+4]
        fld     dword ptr [esi+mv_position+8]
        fsub    dword ptr [_modelorg+8]
        fxch    st(2)
        fld     st(0)
        fmul    dword ptr [_vpn+0]
        fld     st(1)
        fmul    dword ptr [_vright+0]
        fxch    st(2)
        fmul    dword ptr [_vup+0]
        fld     st(3)
        fmul    dword ptr [_vpn+4]
        fld     st(4)
        fmul    dword ptr [_vright+4]
        fxch    st(5)
        fmul    dword ptr [_vup+4]
        fxch    st(1)
        faddp   st(3), st(0)
        fxch    st(3)
        faddp   st(4), st(0)
        faddp   st(2), st(0)
        fld     st(3)
        fmul    dword ptr [_vpn+8]
        fld     st(4)
        fmul    dword ptr [_vright+8]
        fxch    st(5)
        fmul    dword ptr [_vup+8]
        fxch    st(1)
        faddp   st(2), st(0)
        fxch    st(4)
        faddp   st(3), st(0)
        fxch    st(1)
        faddp   st(3), st(0)
        fcom    dword ptr [Lfp_near_clip]
        fnstsw  ax
        test    ah, 1
        jz      LNoClip
        fstp    st(0)
        fld     dword ptr [Lfp_near_clip]
LNoClip:
        fdivr   dword ptr [float_1]
        fxch    st(1)
        fld     dword ptr [_xscale]
        fmul    st(0), st(2)
        fmulp   st(1), st(0)
        fadd    dword ptr [_xcenter]
        fcom    dword ptr [_r_refdef+rd_fvrectx_adj]
        fnstsw  ax
        test    ah, 1
        jz      LClampP0
        fstp    st(0)
        fld     dword ptr [_r_refdef+rd_fvrectx_adj]
LClampP0:
        fcom    dword ptr [_r_refdef+rd_fvrectright_adj]
        fnstsw  ax
        test    ah, 045h
        jnz     LClampP1
        fstp    st(0)
        fld     dword ptr [_r_refdef+rd_fvrectright_adj]
LClampP1:
        fld     st(1)
        fmul    dword ptr [_yscale]
        fmulp   st(3), st(0)
        fxch    st(2)
        fsubr   dword ptr [_ycenter]
        fcom    dword ptr [_r_refdef+rd_fvrecty_adj]
        fnstsw  ax
        test    ah, 1
        jz      LClampP2
        fstp    st(0)
        fld     dword ptr [_r_refdef+rd_fvrecty_adj]
LClampP2:
        fcom    dword ptr [_r_refdef+rd_fvrectbottom_adj]
        fnstsw  ax
        test    ah, 045h
        jnz     LClampP3
        fstp    st(0)
        fld     dword ptr [_r_refdef+rd_fvrectbottom_adj]
LClampP3:
        ret
LTransformAndProject endp
R_ClipEdge_ endp

end
