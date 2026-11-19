;=============================================================================
; worlda.asm - x86 assembly-language hull-point test
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/worlda.s,
; adapted to Watcom's DEFAULT 32-bit REGISTER calling convention.
;
; C prototype (world.c:491, guarded by #if !id386):
;   int SV_HullPointContents (hull_t *hull, int num, vec3_t p);
;
; Equivalent source logic:
;   while (num >= 0) {
;       node  = hull->clipnodes + num;
;       plane = hull->planes + node->planenum;
;       if (plane->type < 3)  d = p[plane->type] - plane->dist;
;       else                  d = DotProduct(plane->normal, p) - plane->dist;
;       num = (d < 0) ? node->children[1] : node->children[0];
;   }
;   return num;
;
; CALLING CONVENTION (IMPORTANT):
;   The original gas .s source uses cdecl stack parameters, but this port
;   compiles with OpenWatcom C, whose DEFAULT 32-bit convention passes the
;   first arguments in REGISTERS. Verified from disassembly of the C caller:
;       EAX = hull   (arg 1)
;       EDX = num    (arg 2)
;       EBX = p      (arg 3, pointer to vec3_t)
;   Return value in EAX. Only EAX/EDX are volatile; EBX/ECX/ESI/EDI/EBP
;   are ALL callee-saved in Watcom's convention -> all preserved.
;
; Register allocation inside the routine:
;   eax = num / scratch (return value)     edx = children copy
;   ebx = 0 (axis index for p[plane->type])
;   esi = p (vec3_t *)                     edi = hull->clipnodes
;   ebp = hull->planes                     ecx = planenum*5 (plane stride helper)
;
; Structure offsets (from asm_i386_asm.h):
;   hull_t:      hu_clipnodes=0,  hu_planes=4
;   dclipnode_t: nd_planenum=0,   nd_children=4   (server clipnode = 8 bytes)
;   mplane_t:    pl_normal=0,     pl_dist=12,      pl_type=16  (plane = 20 bytes)
;=============================================================================

.386
.model  small

; ---- structure offsets -----------------------------------------------------
hu_clipnodes    equ 0
hu_planes       equ 4
nd_planenum     equ 0
nd_children     equ 4
pl_normal       equ 0
pl_dist         equ 12
pl_type         equ 16

; ---- exported symbols (Watcom trailing-underscore convention) --------------
public  SV_HullPointContents_

.data
    ALIGN 4
Ltemp   dd 0                    ; scratch: stores 'd' for the sign-bit test

.code
;=============================================================================
; SV_HullPointContents_  (was: _SV_HullPointContents in worlda.s)
;
; On entry:  EAX = hull, EDX = num, EBX = p
;=============================================================================
SV_HullPointContents_ proc near
        ; Preserve callee-saved registers (Watcom convention):
        ; EBX, ECX, ESI, EDI, EBP are all callee-saved; only EAX/EDX volatile.
        push    ebx
        push    ecx
        push    esi
        push    edi
        push    ebp

        ; Unpack incoming register arguments
        mov     edi, [eax+hu_clipnodes] ; edi = hull->clipnodes
        mov     ebp, [eax+hu_planes]    ; ebp = hull->planes
        mov     esi, ebx                ; esi = p (vec3_t *)
        mov     eax, edx                ; eax = num
        test    eax, eax
        js      short Lhquickout        ; num < 0 -> return immediately
        xor     ebx, ebx                ; ebx = 0 (axis index)

; eax = num, esi = p, edi = clipnodes, ebp = planes, ebx = 0
; while (num >= 0) {
Lhloop:
        ; node = hull->clipnodes + num   (dclipnode_t = 8 bytes -> scale 8)
        mov     ecx, [edi+eax*8+nd_planenum]    ; ecx = node->planenum
        mov     eax, [edi+eax*8+nd_children]    ; eax = node->children (2x short packed)
        mov     edx, eax                        ; edx = copy of children
        ror     eax, 16                         ; swap hi/lo words -> children[0] becomes hi
        lea     ecx, [ecx+ecx*4]                ; ecx = planenum*5
                                                ; plane access uses [ebp+ecx*4] = planenum*20

        ; plane = hull->planes + node->planenum
        ; if (plane->type < 3)  -> simple axis distance
        mov     bl, [ebp+ecx*4+pl_type]         ; bl = plane->type
        cmp     bl, 3
        jb      short Lnodot

        ; else: d = DotProduct(plane->normal, p) - plane->dist
        fld     dword ptr [ebp+ecx*4+pl_normal+0]   ; st0 = normal[0]
        fmul    dword ptr [esi+0]                   ; st0 = n0*p0
        fld     dword ptr [ebp+ecx*4+pl_normal+4]   ; st0 = n1, st1 = n0*p0
        fmul    dword ptr [esi+4]                   ; st0 = n1*p1
        fld     dword ptr [ebp+ecx*4+pl_normal+8]   ; st0 = n2, st1 = n1*p1, st2 = n0*p0
        fmul    dword ptr [esi+8]                   ; st0 = n2*p2
        fxch    st(1)                               ; st0=n1*p1, st1=n2*p2, st2=n0*p0
        faddp   st(2), st(0)                        ; st2 = n0*p0+n1*p1, pop
        faddp   st(1), st(0)                        ; st1 = dot, pop -> st0 = dot
        fsub    dword ptr [ebp+ecx*4+pl_dist]       ; st0 = dot - dist
        jmp     short Lsub

Lnodot:
        ; d = p[plane->type] - plane->dist
        fld     dword ptr [ebp+ecx*4+pl_dist]       ; st0 = dist
        fsubr   dword ptr [esi+ebx*4]               ; st0 = p[type] - dist

Lsub:
        ; Split the packed children word into sign-extended ints.
        ; eax (after ror 16): hi=children[0], lo=children[1]
        ; edx (original):     hi=children[1], lo=children[0]
        sar     eax, 16                         ; eax = children[0]
        sar     edx, 16                         ; edx = children[1]

        ; Branchless select: num = (d < 0) ? children[1] : children[0]
        fstp    dword ptr [Ltemp]               ; store d
        mov     ecx, [Ltemp]                    ; ecx = d bit pattern
        sar     ecx, 31                         ; ecx = 0xFFFFFFFF if d<0, else 0
        and     edx, ecx                        ; if d<0: keep children[1], else 0
        not     ecx                             ; OPT: 'not' vs 'xor ecx,-1' (shorter encoding)
        and     eax, ecx                        ; if d>=0: keep children[0], else 0
        or      eax, edx                        ; eax = selected child = new num
        jns     short Lhloop                    ; num >= 0 -> loop
; }

Lhquickout:
        pop     ebp
        pop     edi
        pop     esi
        pop     ecx
        pop     ebx
        ret                                     ; return contents in EAX
SV_HullPointContents_ endp

;=============================================================================
; Translation notes / optimization opportunities:
;
; 1. CALLING CONVENTION: The gas original uses cdecl ([esp+4] params). This
;    port compiles with Watcom C, whose default 32-bit convention passes args
;    in EAX/EDX/EBX. Adapting to registers was REQUIRED - a literal cdecl
;    translation reads garbage and crashes (confirmed by functional test).
;
; 2. CALLEE-SAVED REGS: EBX/ECX/ESI/EDI/EBP are ALL preserved via push/pop
;    (Watcom convention: only EAX/EDX are volatile). Clobbering ECX corrupted
;    the C caller's state in the functional test.
;
; 3. FIDELITY: The FPU stack ordering (fld/fmul/fxch/faddp sequence) is
;    preserved exactly. 'faddp st(2),st(0)' is the MASM form of the gas
;    'faddp %st(0),%st(2)' (AT&T reverses operands).
;
; 4. OPT (applied): 'not ecx' replaces 'xor ecx, 0FFFFFFFFh' (shorter encoding).
;
; 5. OPT (possible): Ltemp is a global scratch dword. Making it a stack local
;    would make the routine reentrant. Left global to stay faithful.
;
; 6. OPT (not available on 486): CMOVcc is Pentium-Pro+, so the and/not/and/or
;    branchless select is the correct fastest approach for the 486 target.
;
; 7. NOTE: scale-8 for clipnodes is intentional - SERVER hull clipnodes are
;    8 bytes (planenum + 2 shorts), unlike the 40-byte client dclipnode_t.
;=============================================================================

end