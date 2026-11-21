;=============================================================================
; r_edgea.asm - edge-processing code, MASM (OpenWatcom wasm) translation of
;               WinQuake/r_edgea.s
;
; R_InsertNewEdges(edge_t*,edge_t*), R_RemoveEdges(edge_t*), R_StepActiveU(edge_t*),
; R_GenerateSpans(void), R_SurfacePatch(void), R_EdgeCodeStart/End labels.
;
; Watcom register ABI: args in EAX,EDX; EBX/ECX/ESI/EDI/EBP are preserved.
;
; Differences from the original GAS source:
;  * No self-modifying code.  The four patch sites (LPatch0/2/3/4) that held
;    &surfaces[1] are replaced by computing it from _surfaces at the point of
;    use (&surfaces[1] = _surfaces + st_size; surfaces[1].next is at +st_next).
;    R_SurfacePatch_ therefore has nothing to do and is a plain RET (kept so
;    existing callers still link).
;  * Control flow of R_GenerateSpans is laid out exactly like the original so
;    that every fall-through is preserved.  The two things that must NOT be
;    "tidied": LInsertAndExit falls into Lgs_nextedge (NOT into Lxl_done),
;    and the second 1/z-sort copy (Lzcheck_for_newtop) falls into
;    Lsortloop_fpop2 (NOT into Lnewtop).
;  * FPU: gas "faddp %st(0),%st(N)" -> "faddp st(N),st(0)";
;         gas "fmul %st(a),%st(0)" -> "fmul st(0),st(a)".
;         (no fsub/fdiv are used in this file, so the GAS reversed-operand
;          trap does not apply.)
;  * float constants are given as exact IEEE-754 hex so they do not depend on
;    how the assembler parses decimal 'dd' initialisers.
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
Ltemp                dd 0
float_1_div_0100000h dd 035800000h      ; 1.0/(float)0x100000
float_point_999      dd 03F7FBE77h      ; 0.999f
float_1_point_001    dd 03F8020C5h      ; 1.001f

.code
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
        mov     edi, ecx
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
; TrailingEdge -- internal helper, entered by CALL, or by JMP with the return
;                 address (Lgs_nextedge) already pushed.
;   in:  ESI = surf_t* whose span is ending, EBX = edge, EBP = span_p
;   out: EBP updated.  Clobbers EAX,ECX,EDX,ESI.  Returns with RET.
;=============================================================================
TrailingEdge proc near
        mov     eax, [esi+st_spanstate] ; check for edge inversion
        dec     eax
        jnz     TI_Inverted
        mov     [esi+st_spanstate], eax ; eax == 0
        mov     ecx, [esi+st_insubmodel]
        mov     edx, [_surfaces]
        mov     eax, [_r_bmodelactive]
        mov     edx, [edx+st_size+st_next]      ; surfaces[1].next
        sub     eax, ecx
        cmp     edx, esi
        mov     [_r_bmodelactive], eax
        jnz     TI_NoEmit               ; surface isn't on top, just remove

; emit a span (current top going away)
        mov     eax, [ebx+et_u]
        shr     eax, 20                 ; iu = integral pixel u
        mov     edx, [esi+st_last_u]
        mov     ecx, [esi+st_next]
        cmp     eax, edx
        jle     TI_NoEmit2              ; iu <= surf->last_u, nothing to emit

        mov     [ecx+st_last_u], eax    ; surf->next->last_u = iu
        sub     eax, edx
        mov     [ebp+espan_t_u], edx    ; span->u = surf->last_u
        mov     [ebp+espan_t_count], eax
        mov     eax, [_current_iv]
        mov     [ebp+espan_t_v], eax
        mov     eax, [esi+st_spans]
        mov     [ebp+espan_t_pnext], eax
        mov     [esi+st_spans], ebp     ; surf->spans = span
        add     ebp, espan_t_size

        mov     edx, [esi+st_next]      ; remove the surface from the surface
        mov     esi, [esi+st_prev]      ; stack
        mov     [esi+st_next], edx
        mov     [edx+st_prev], esi
        ret

TI_NoEmit2:
        mov     [ecx+st_last_u], eax    ; surf->next->last_u = iu
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

;=============================================================================
; R_GenerateSpans_ -- void.  EBP = span_p throughout.
;=============================================================================
R_GenerateSpans_ proc near
        push    ebp
        push    edi
        push    esi
        push    ebx
        push    ecx
        push    edx

; clear active surfaces to just the background surface
        mov     eax, [_surfaces]
        mov     edx, [_edge_head_u_shift20]
        add     eax, st_size            ; eax = &surfaces[1]
        mov     ebp, [_span_p]
        mov     dword ptr [_r_bmodelactive], 0
        mov     [eax+st_next], eax
        mov     [eax+st_prev], eax
        mov     [eax+st_last_u], edx
        mov     ebx, [_edge_head+et_next]       ; edge = edge_head.next

; generate spans
        cmp     ebx, offset _edge_tail          ; done if empty list
        jz      Lgs_lastspan

Lgs_edgeloop:
        mov     edi, [ebx+et_surfs]
        mov     eax, [_surfaces]
        mov     esi, edi
        and     edi, 0FFFF0000h
        and     esi, 0FFFFh
        jz      Lgs_leading             ; not a trailing edge

; it has a left surface, so a surface is going away for this span
        shl     esi, SURF_T_SHIFT
        add     esi, eax
        test    edi, edi
        jz      Lgs_trailing

; both leading and trailing
        call    TrailingEdge
        mov     eax, [_surfaces]

;---------------------------------------------------------------
; handle a leading edge
;---------------------------------------------------------------
Lgs_leading:
        shr     edi, 16-SURF_T_SHIFT
        mov     eax, [_surfaces]
        add     edi, eax                ; edi = surf
        mov     esi, [eax+st_size+st_next]      ; surf2 = surfaces[1].next
        mov     edx, [edi+st_spanstate]
        mov     eax, [edi+st_insubmodel]
        test    eax, eax
        jnz     Lbmodel_leading

; handle a leading non-bmodel edge
; don't start a span if this is an inverted span, with the end edge preceding
; the start edge (that is, we've already seen the end edge)
        test    edx, edx
        jnz     Lxl_done

; if (surf->key < surf2->key) goto newtop;
        inc     edx
        mov     eax, [edi+st_key]
        mov     [edi+st_spanstate], edx
        mov     ecx, [esi+st_key]
        cmp     eax, ecx
        jl      Lnewtop

; main sorting loop; always terminates because the background is a sentinel
Lsortloopnb:
        mov     esi, [esi+st_next]
        mov     ecx, [esi+st_key]
        cmp     eax, ecx
        jge     Lsortloopnb

        jmp     LInsertAndExit

; handle a leading bmodel edge
        ALIGN 4
Lbmodel_leading:
        test    edx, edx
        jnz     Lxl_done

        mov     ecx, [_r_bmodelactive]
        inc     edx
        inc     ecx
        mov     [edi+st_spanstate], edx
        mov     [_r_bmodelactive], ecx

; if (surf->key < surf2->key) goto newtop;
        mov     eax, [edi+st_key]
        mov     ecx, [esi+st_key]
        cmp     eax, ecx
        jl      Lnewtop

; if ((surf->key == surf2->key) && surf->insubmodel)  -- flags still from CMP
        jz      Lzcheck_for_newtop

Lsortloop:
        mov     esi, [esi+st_next]
        mov     ecx, [esi+st_key]
        cmp     eax, ecx
        jg      Lsortloop

        jne     LInsertAndExit

; Do 1/z sorting to see if we've arrived in the right position
        mov     eax, [ebx+et_u]
        sub     eax, 0FFFFFh
        mov     [Ltemp], eax
        fild    dword ptr [Ltemp]
        fmul    dword ptr [float_1_div_0100000h]        ; fu
        fld     st(0)                                   ; fu | fu
        fmul    dword ptr [edi+st_d_zistepu]
        fld     dword ptr [_fv]
        fmul    dword ptr [edi+st_d_zistepv]
        fxch    st(1)
        fadd    dword ptr [edi+st_d_ziorigin]
        fld     dword ptr [esi+st_d_zistepu]
        fmul    st(0), st(3)
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

; if (newzibottom >= testzi) goto Lgotposition;
        fcomp   st(1)
        fxch    st(1)
        fmul    dword ptr [float_1_point_001]
        fxch    st(1)
        fnstsw  ax
        test    ah, 01h
        jz      Lgotposition_fpop3

; if (newzitop >= testzi)
        fcomp   st(1)
        fnstsw  ax
        test    ah, 045h
        jz      Lsortloop_fpop2

; if (surf->d_zistepu >= surf2->d_zistepu) goto newtop;
        fld     dword ptr [edi+st_d_zistepu]
        fcomp   dword ptr [esi+st_d_zistepu]
        fnstsw  ax
        test    ah, 01h
        jz      Lgotposition_fpop2

        fstp    st(0)                   ; clear the FP stack
        fstp    st(0)
        mov     eax, [edi+st_key]
        jmp     Lsortloop

Lgotposition_fpop3:
        fstp    st(0)
Lgotposition_fpop2:
        fstp    st(0)
        fstp    st(0)
        jmp     LInsertAndExit

; emit a span (obscures current top)
Lnewtop_fpop3:
        fstp    st(0)
Lnewtop_fpop2:
        fstp    st(0)
        fstp    st(0)
        mov     eax, [edi+st_key]       ; reload the sorting key

Lnewtop:
        mov     eax, [ebx+et_u]
        mov     edx, [esi+st_last_u]
        shr     eax, 20                 ; iu = integral pixel u
        mov     [edi+st_last_u], eax    ; surf->last_u = iu
        cmp     eax, edx
        jle     LInsertAndExit          ; iu <= surf2->last_u, nothing to emit

        sub     eax, edx
        mov     [ebp+espan_t_u], edx    ; span->u = surf2->last_u
        mov     [ebp+espan_t_count], eax
        mov     eax, [_current_iv]
        mov     [ebp+espan_t_v], eax
        mov     eax, [esi+st_spans]
        mov     [ebp+espan_t_pnext], eax
        mov     [esi+st_spans], ebp     ; surf2->spans = span
        add     ebp, espan_t_size

LInsertAndExit:
; insert before surf2
        mov     [edi+st_next], esi      ; surf->next = surf2
        mov     eax, [esi+st_prev]
        mov     [edi+st_prev], eax      ; surf->prev = surf2->prev
        mov     [esi+st_prev], edi      ; surf2->prev = surf
        mov     [eax+st_next], edi      ; surf2->prev->next = surf

;---------------------------------------------------------------
; leading edge done -- see if there are any more edges
; (NOTE: LInsertAndExit FALLS THROUGH to here.)
;---------------------------------------------------------------
Lgs_nextedge:
        mov     ebx, [ebx+et_next]
        cmp     ebx, offset _edge_tail
        jnz     Lgs_edgeloop

; clean up at the right edge
Lgs_lastspan:
; now that we've reached the right edge of the screen, we're done with any
; unfinished surfaces, so emit a span for whatever's on top
        mov     edi, [_surfaces]
        add     edi, st_size            ; edi = &surfaces[1]
        mov     esi, [edi+st_next]      ; esi = surfaces[1].next (top)
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

; reset spanstate for all surfaces in the surface stack
Lgs_resetspanstate:
        mov     [esi+st_spanstate], ecx
        mov     esi, [esi+st_next]
        cmp     esi, edi                ; back at &surfaces[1]?
        jnz     Lgs_resetspanstate

; store the final span_p
        mov     [_span_p], ebp

        pop     edx
        pop     ecx
        pop     ebx
        pop     esi
        pop     edi
        pop     ebp
        ret

; trailing edge only
Lgs_trailing:
        push    offset Lgs_nextedge
        jmp     TrailingEdge

;---------------------------------------------------------------
; 1/z sorting for bmodels in the same leaf
;---------------------------------------------------------------
        ALIGN 4
Lxl_done:
        inc     edx
        mov     [edi+st_spanstate], edx
        jmp     Lgs_nextedge

        ALIGN 4
Lzcheck_for_newtop:
        mov     eax, [ebx+et_u]
        sub     eax, 0FFFFFh
        mov     [Ltemp], eax
        fild    dword ptr [Ltemp]
        fmul    dword ptr [float_1_div_0100000h]        ; fu
        fld     st(0)
        fmul    dword ptr [edi+st_d_zistepu]
        fld     dword ptr [_fv]
        fmul    dword ptr [edi+st_d_zistepv]
        fxch    st(1)
        fadd    dword ptr [edi+st_d_ziorigin]
        fld     dword ptr [esi+st_d_zistepu]
        fmul    st(0), st(3)
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

; if (newzibottom >= testzi) goto newtop;
        fcomp   st(1)
        fxch    st(1)
        fmul    dword ptr [float_1_point_001]
        fxch    st(1)
        fnstsw  ax
        test    ah, 01h
        jz      Lnewtop_fpop3

; if (newzitop >= testzi)
        fcomp   st(1)
        fnstsw  ax
        test    ah, 045h
        jz      Lsortloop_fpop2

; if (surf->d_zistepu >= surf2->d_zistepu) goto newtop;
        fld     dword ptr [edi+st_d_zistepu]
        fcomp   dword ptr [esi+st_d_zistepu]
        fnstsw  ax
        test    ah, 01h
        jz      Lnewtop_fpop2

; (NOTE: falls through to Lsortloop_fpop2 -- keep it right here.)
Lsortloop_fpop2:
        fstp    st(0)                   ; clear the FP stack
        fstp    st(0)
        mov     eax, [edi+st_key]
        jmp     Lsortloop
R_GenerateSpans_ endp

R_EdgeCodeEnd_:

;=============================================================================
; R_SurfacePatch_ -- nothing to patch any more.
;
; The original patched four code immediates (LPatch0/2/3/4) with &surfaces[1]
; (self-modifying code, which breaks under DOS4GW/wasm because the absolute
; code writes are not relocated).  R_GenerateSpans_ and TrailingEdge now derive
; &surfaces[1] from _surfaces on every use, so there is no stale-pointer risk
; if surfaces[] moves.  Kept as an exported no-op so callers still link.
;=============================================================================
R_SurfacePatch_ proc near
        ret
R_SurfacePatch_ endp

end
