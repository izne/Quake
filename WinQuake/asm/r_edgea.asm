;=============================================================================
; r_edgea.asm - alias edge-processing code (replaces the old stub)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/r_edgea.s.
; R_InsertNewEdges(edge_t*,edge_t*), R_RemoveEdges(edge_t*), R_StepActiveU(edge_t*),
; R_GenerateSpans(void), R_SurfacePatch(void), R_EdgeCodeStart/End labels.
; Four self-modifying patch sites (LPatch0/2/3/4) patched by R_SurfacePatch.
; EBX/ECX/EDX/ESI/EDI/EBP callee-saved -> preserved.
; FPU: gas faddp %st(0),%st(N) -> faddp st(N),st(0); fmul %st(a),%st(0) -> fmul st(0),st(a).
;=============================================================================

.386
.model  small

SURF_T_SHIFT equ 6
et_u equ 0
et_u_step equ 4
et_prev equ 8
et_next equ 12
et_surfs equ 16
et_nextremove equ 20
et_size equ 32
st_next equ 0
st_prev equ 4
st_spans equ 8
st_key equ 12
st_last_u equ 16
st_spanstate equ 20
st_insubmodel equ 40
st_d_ziorigin equ 44
st_d_zistepu equ 48
st_d_zistepv equ 52
st_size equ 64
espan_t_u equ 0
espan_t_v equ 4
espan_t_count equ 8
espan_t_pnext equ 12
espan_t_size equ 16

extrn   _surfaces:dword, _r_bmodelactive:dword, _current_iv:dword
extrn   _span_p:dword, _edge_head_u_shift20:dword, _edge_tail_u_shift20:dword
extrn   _edge_head:dword, _edge_tail:dword
extrn   _edge_aftertail:dword, _fv:dword

public  R_EdgeCodeStart_, R_EdgeCodeEnd_
public  R_InsertNewEdges_, R_RemoveEdges_, R_StepActiveU_
public  R_GenerateSpans_, R_SurfacePatch_

.data
        ALIGN 4
Ltemp               dd 0
float_1_div_0100000h dd 035800000h
float_point_999     dd 0.999
float_1_point_001   dd 1.001

.code
public R_EdgeCodeStart_
R_EdgeCodeStart_:

;=============================================================================
; R_InsertNewEdges_  -- EAX=edgestoadd, EDX=edgelist
;=============================================================================
R_InsertNewEdges_ proc near
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx
        mov     ecx, edx                ; ecx = edgelist
        mov     edx, eax                ; edx = edgestoadd
LDoNextEdge:
        mov     eax, [edx+et_u]
        mov     edi, edx
LContinueSearch:
        mov     ebx, [ecx+et_u]
        mov     esi, [ecx+et_next]
        cmp     eax, ebx
        jle     LAddedge
        mov     ebx, [esi+et_u]
        mov     ecx, [esi+et_next]
        cmp     eax, ebx
        jle     LAddedge2
        mov     ebx, [ecx+et_u]
        mov     esi, [ecx+et_next]
        cmp     eax, ebx
        jle     LAddedge
        mov     ebx, [esi+et_u]
        mov     ecx, [esi+et_next]
        cmp     eax, ebx
        jg      LContinueSearch
LAddedge2:
        mov     edx, [edx+et_next]
        mov     ebx, [esi+et_prev]
        mov     [edi+et_next], esi
        mov     [edi+et_prev], ebx
        mov     [ebx+et_next], edi
        mov     [esi+et_prev], edi
        mov     ecx, esi
        cmp     edx, 0
        jnz     LDoNextEdge
        jmp     LDone
        ALIGN 4
LAddedge:
        mov     edx, [edx+et_next]
        mov     ebx, [ecx+et_prev]
        mov     [edi+et_next], ecx
        mov     [edi+et_prev], ebx
        mov     [ebx+et_next], edi
        mov     [ecx+et_prev], edi
        cmp     edx, 0
        jnz     LDoNextEdge
LDone:
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        ret
R_InsertNewEdges_ endp

;=============================================================================
; R_RemoveEdges_  -- EAX=pedge
;=============================================================================
R_RemoveEdges_ proc near
        push    ebx
        push    ecx
        push    edx
Lre_loop:
        mov     ecx, [eax+et_next]
        mov     ebx, [eax+et_nextremove]
        mov     edx, [eax+et_prev]
        test    ebx, ebx
        mov     [ecx+et_prev], edx
        jz      Lre_done
        mov     [edx+et_next], ecx
        mov     ecx, [ebx+et_next]
        mov     edx, [ebx+et_prev]
        mov     eax, [ebx+et_nextremove]
        mov     [ecx+et_prev], edx
        test    eax, eax
        mov     [edx+et_next], ecx
        jnz     Lre_loop
        pop     edx
        pop     ecx
        pop     ebx
        ret
Lre_done:
        mov     [edx+et_next], ecx
        pop     edx
        pop     ecx
        pop     ebx
        ret
R_RemoveEdges_ endp

;=============================================================================
; R_StepActiveU_  -- EAX=pedgelist
;=============================================================================
R_StepActiveU_ proc near
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx
        mov     edx, eax                ; edx = pedgelist
        mov     esi, [edx+et_prev]
LNewEdge:
        mov     edi, [esi+et_u]
LNextEdge:
        mov     eax, [edx+et_u]
        mov     ebx, [edx+et_u_step]
        add     eax, ebx
        mov     esi, [edx+et_next]
        mov     [edx+et_u], eax
        cmp     eax, edi
        jl      LPushBack
        mov     edi, [esi+et_u]
        mov     ebx, [esi+et_u_step]
        add     edi, ebx
        mov     edx, [esi+et_next]
        mov     [esi+et_u], edi
        cmp     edi, eax
        jl      LPushBack2
        mov     eax, [edx+et_u]
        mov     ebx, [edx+et_u_step]
        add     eax, ebx
        mov     esi, [edx+et_next]
        mov     [edx+et_u], eax
        cmp     eax, edi
        jl      LPushBack
        mov     edi, [esi+et_u]
        mov     ebx, [esi+et_u_step]
        add     edi, ebx
        mov     edx, [esi+et_next]
        mov     [esi+et_u], edi
        cmp     edi, eax
        jnl     LNextEdge
LPushBack2:
        mov     ebx, edx
        mov     eax, edi
        mov     edx, esi
        mov     esi, ebx
LPushBack:
        mov     ecx, [edx+et_prev]
        mov     ebx, [edx+et_next]
        cmp     edx, offset _edge_aftertail
        jz      LUDone
        mov     edi, [ecx+et_prev]
        mov     [esi+et_prev], ecx
        mov     [ecx+et_next], ebx
LPushBackLoop:
        mov     ecx, [edi+et_prev]
        mov     ebx, [edi+et_u]
        cmp     eax, ebx
        jnl     LPushBackFound
        mov     edi, [ecx+et_prev]
        mov     ebx, [ecx+et_u]
        cmp     eax, ebx
        jl      LPushBackLoop
        mov     ecx, edi
LPushBackFound:
        mov     ebx, [edi+et_next]
        mov     [edx+et_prev], edi
        mov     [edx+et_next], ebx
        mov     [edi+et_next], edx
        mov     [ebx+et_prev], edx
        mov     edx, esi
        mov     esi, [esi+et_prev]
        cmp     edx, offset _edge_tail
        jnz     LNewEdge
LUDone:
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        ret
R_StepActiveU_ endp

;=============================================================================
; R_GenerateSpans_  -- void. TrailingEdge is an internal near proc, entered
; via `call` (both-leading/trailing case) or via pushed-return-address `jmp`.
;=============================================================================
R_GenerateSpans_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx

        mov     eax, [_surfaces]
        mov     edx, [_edge_head_u_shift20]
        add     eax, st_size
        mov     ebp, [_span_p]
        mov     dword ptr [_r_bmodelactive], 0
        mov     [eax+st_next], eax
        mov     [eax+st_prev], eax
        mov     [eax+st_last_u], edx
        mov     ebx, [_edge_head+et_next]
        cmp     ebx, offset _edge_tail
        jz      Lgs_lastspan

Lgs_edgeloop:
        mov     edi, [ebx+et_surfs]
        mov     eax, [_surfaces]
        mov     esi, edi
        and     edi, 0FFFF0000h
        and     esi, 0FFFFh
        jz      Lgs_leading
        shl     esi, SURF_T_SHIFT
        add     esi, eax
        test    edi, edi
        jz      Lgs_trailing
        call    TrailingEdge
        mov     eax, [_surfaces]

Lgs_leading:
        shr     edi, 16-SURF_T_SHIFT
        mov     eax, [_surfaces]
        add     edi, eax
        mov     esi, [12345678h]
LPatch2:
        mov     edx, [edi+st_spanstate]
        mov     eax, [edi+st_insubmodel]
        test    eax, eax
        jnz     Lbmodel_leading
        test    edx, edx
        jnz     Lxl_done
        inc     edx
        mov     eax, [edi+st_key]
        mov     [edi+st_spanstate], edx
        mov     ecx, [esi+st_key]
        cmp     eax, ecx
        jl      Lnewtop
Lsortloopnb:
        mov     esi, [esi+st_next]
        mov     ecx, [esi+st_key]
        cmp     eax, ecx
        jge     Lsortloopnb
        jmp     LInsertAndExit

Lbmodel_leading:
        test    edx, edx
        jnz     Lxl_done
        mov     ecx, [_r_bmodelactive]
        inc     edx
        inc     ecx
        mov     [edi+st_spanstate], edx
        mov     [_r_bmodelactive], ecx
        mov     eax, [edi+st_key]
        mov     ecx, [esi+st_key]
        cmp     eax, ecx
        jl      Lnewtop
        jz      Lzcheck_for_newtop
Lsortloop:
        mov     esi, [esi+st_next]
        mov     ecx, [esi+st_key]
        cmp     eax, ecx
        jg      Lsortloop
        jne     LInsertAndExit
        ; equal keys: 1/z test (first copy)
        mov     eax, [ebx+et_u]
        sub     eax, 0FFFFFh
        mov     [Ltemp], eax
        fild    dword ptr [Ltemp]
        fmul    dword ptr [float_1_div_0100000h]
        fld     st(0)
        fmul    dword ptr [edi+st_d_zistepu]
        fld     dword ptr [_fv]
        fmul    dword ptr [edi+st_d_zistepv]
        fxch    st(1)
        fadd    dword ptr [edi+st_d_ziorigin]
        fld     dword ptr [esi+st_d_zistepu]
        fmul    st(3), st(0)
        fxch    st(1)
        faddp   st(2), st(0)
        fld     dword ptr [_fv]
        fmul    dword ptr [esi+st_d_zistepv]
        fld     st(2)
        fmul    dword ptr [float_point_999]
        fxch    st(2)
        fadd    dword ptr [esi+st_d_ziorigin]
        faddp   st(1), st(0)
        fxch    st(1)
        fcomp   st(1)
        fxch    st(1)
        fmul    dword ptr [float_1_point_001]
        fxch    st(1)
        fnstsw  ax
        test    ah, 01h
        jz      Lgotposition_fpop3
        fcomp   st(1)
        fnstsw  ax
        test    ah, 045h
        jz      Lsortloop_fpop2
        fld     dword ptr [edi+st_d_zistepu]
        fcomp   dword ptr [esi+st_d_zistepu]
        fnstsw  ax
        test    ah, 01h
        jz      Lgotposition_fpop2
Lsortloop_fpop2:
        fstp    st(0)
        fstp    st(0)
        mov     eax, [edi+st_key]
        jmp     Lsortloop
Lgotposition_fpop3:
        fstp    st(0)
Lgotposition_fpop2:
        fstp    st(0)
        fstp    st(0)
        jmp     LInsertAndExit

Lzcheck_for_newtop:
        mov     eax, [ebx+et_u]
        sub     eax, 0FFFFFh
        mov     [Ltemp], eax
        fild    dword ptr [Ltemp]
        fmul    dword ptr [float_1_div_0100000h]
        fld     st(0)
        fmul    dword ptr [edi+st_d_zistepu]
        fld     dword ptr [_fv]
        fmul    dword ptr [edi+st_d_zistepv]
        fxch    st(1)
        fadd    dword ptr [edi+st_d_ziorigin]
        fld     dword ptr [esi+st_d_zistepu]
        fmul    st(3), st(0)
        fxch    st(1)
        faddp   st(2), st(0)
        fld     dword ptr [_fv]
        fmul    dword ptr [esi+st_d_zistepv]
        fld     st(2)
        fmul    dword ptr [float_point_999]
        fxch    st(2)
        fadd    dword ptr [esi+st_d_ziorigin]
        faddp   st(1), st(0)
        fxch    st(1)
        fcomp   st(1)
        fxch    st(1)
        fmul    dword ptr [float_1_point_001]
        fxch    st(1)
        fnstsw  ax
        test    ah, 01h
        jz      Lnewtop_fpop3
        fcomp   st(1)
        fnstsw  ax
        test    ah, 045h
        jz      Lsortloop_fpop2
        fld     dword ptr [edi+st_d_zistepu]
        fcomp   dword ptr [esi+st_d_zistepu]
        fnstsw  ax
        test    ah, 01h
        jz      Lnewtop_fpop2
Lnewtop_fpop3:
        fstp    st(0)
Lnewtop_fpop2:
        fstp    st(0)
        fstp    st(0)
        mov     eax, [edi+st_key]
Lnewtop:
        mov     eax, [ebx+et_u]
        mov     edx, [esi+st_last_u]
        shr     eax, 20
        mov     [edi+st_last_u], eax
        cmp     eax, edx
        jle     LInsertAndExit
        sub     eax, edx
        mov     [ebp+espan_t_u], edx
        mov     [ebp+espan_t_count], eax
        mov     eax, [_current_iv]
        mov     [ebp+espan_t_v], eax
        mov     eax, [esi+st_spans]
        mov     [ebp+espan_t_pnext], eax
        mov     [esi+st_spans], ebp
        add     ebp, espan_t_size
LInsertAndExit:
        mov     [edi+st_next], esi
        mov     eax, [esi+st_prev]
        mov     [edi+st_prev], eax
        mov     [esi+st_prev], edi
        mov     [eax+st_next], edi

Lxl_done:
        inc     edx
        mov     [edi+st_spanstate], edx
        jmp     Lgs_nextedge

Lgs_trailing:
        push    offset Lgs_nextedge
        jmp     TrailingEdge

Lgs_nextedge:
        mov     ebx, [ebx+et_next]
        cmp     ebx, offset _edge_tail
        jnz     Lgs_edgeloop

Lgs_lastspan:
        mov     esi, [12345678h]
LPatch3:
        mov     eax, [_edge_tail_u_shift20]
        xor     ecx, ecx
        mov     edx, [esi+st_last_u]
        sub     eax, edx
        jle     Lgs_resetspanstate
        mov     [ebp+espan_t_u], edx
        mov     [ebp+espan_t_count], eax
        mov     eax, [_current_iv]
        mov     [ebp+espan_t_v], eax
        mov     eax, [esi+st_spans]
        mov     [ebp+espan_t_pnext], eax
        mov     [esi+st_spans], ebp
        add     ebp, espan_t_size
Lgs_resetspanstate:
        mov     [esi+st_spanstate], ecx
        mov     esi, [esi+st_next]
        cmp     esi, 012345678h
LPatch4:
        jnz     Lgs_resetspanstate
        mov     [_span_p], ebp
        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret

;---- TrailingEdge: entered via call or via pushed return addr; ESI=surface ---
TrailingEdge proc near
        mov     eax, [esi+st_spanstate]
        dec     eax
        jnz     TI_Inverted
        mov     [esi+st_spanstate], eax
        mov     ecx, [esi+st_insubmodel]
        mov     edx, [12345678h]
LPatch0:
        mov     eax, [_r_bmodelactive]
        sub     eax, ecx
        cmp     edx, esi
        mov     [_r_bmodelactive], eax
        jnz     TI_NoEmit
        mov     eax, [ebx+et_u]
        shr     eax, 20
        mov     edx, [esi+st_last_u]
        mov     ecx, [esi+st_next]
        cmp     eax, edx
        jle     TI_NoEmit2
        mov     [ecx+st_last_u], eax
        sub     eax, edx
        mov     [ebp+espan_t_u], edx
        mov     [ebp+espan_t_count], eax
        mov     eax, [_current_iv]
        mov     [ebp+espan_t_v], eax
        mov     eax, [esi+st_spans]
        mov     [ebp+espan_t_pnext], eax
        mov     [esi+st_spans], ebp
        add     ebp, espan_t_size
        mov     edx, [esi+st_next]
        mov     esi, [esi+st_prev]
        mov     [esi+st_next], edx
        mov     [edx+st_prev], esi
        ret
TI_NoEmit2:
        mov     [ecx+st_last_u], eax
        mov     edx, [esi+st_next]
        mov     esi, [esi+st_prev]
        mov     [esi+st_next], edx
        mov     [edx+st_prev], esi
        ret
TI_NoEmit:
        mov     edx, [esi+st_next]
        mov     esi, [esi+st_prev]
        mov     [esi+st_next], edx
        mov     [edx+st_prev], esi
        ret
TI_Inverted:
        mov     [esi+st_spanstate], eax
        ret
TrailingEdge endp
R_GenerateSpans_ endp

public R_EdgeCodeEnd_
R_EdgeCodeEnd_:

;=============================================================================
; R_SurfacePatch_ - patches the 4 self-modifying displacements
;=============================================================================
public R_SurfacePatch_
R_SurfacePatch_ proc near
        mov     eax, [_surfaces]
        add     eax, st_size
        mov     dword ptr [LPatch4-4], eax
        add     eax, st_next
        mov     dword ptr [LPatch0-4], eax
        mov     dword ptr [LPatch2-4], eax
        mov     dword ptr [LPatch3-4], eax
        ret
R_SurfacePatch_ endp

end
