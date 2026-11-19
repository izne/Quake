;=============================================================================
; snd_mixa.asm - x86 assembly-language sound mixing
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/snd_mixa.s.
; Two routines:
;   SND_PaintChannelFrom8       (3 args -> Watcom register ABI)
;   Snd_WriteLinearBlastStereo16 (void, uses globals)
;
; CALLING CONVENTION (Watcom default 32-bit register ABI - see worlda.asm):
;   SND_PaintChannelFrom8(ch, sc, count):
;       EAX = ch   (channel_t *)
;       EDX = sc   (sfxcache_t *)
;       EBX = count
;   Snd_WriteLinearBlastStereo16(void): no args.
;   Only EAX/EDX volatile; EBX/ECX/ESI/EDI/EBP are callee-saved -> preserved.
;
; Global data symbols (C, leading underscore, from quake486.map):
;   _paintbuffer, _snd_scaletable, _snd_p, _snd_vol, _snd_out,
;   _snd_linear_count
;
; Struct offsets (asm_i386_asm.h):
;   channel_t:    ch_leftvol=4, ch_rightvol=8, ch_pos=16
;   sfxcache_t:   sfxc_data=20
;   painting:     psp_left=0, psp_right=4, psp_size=8
;
; NOTE on the gas source's odd "_paintbuffer)+psp_left-psp_size(...)" syntax:
;   This is a mangled form of C(paintbuffer) (see QW/client/snd_mixa.s) which
;   expands to the plain symbol _paintbuffer. The address expression
;   _paintbuffer + psp_left - psp_size + ecx*psp_size becomes
;   _paintbuffer[ecx*8 - 8] in MASM (count indexes from the end).
;=============================================================================

.386
.model  small

; ---- struct offsets --------------------------------------------------------
ch_leftvol      equ 4
ch_rightvol     equ 8
ch_pos          equ 16
sfxc_data       equ 20
psp_left        equ 0
psp_right       equ 4
psp_size        equ 8

; ---- global data (C, leading underscore) -----------------------------------
extrn   _paintbuffer:dword
extrn   _snd_scaletable:dword
extrn   _snd_p:dword
extrn   _snd_vol:dword
extrn   _snd_out:dword
extrn   _snd_linear_count:dword

; ---- exported functions (Watcom trailing-underscore convention) ------------
public  SND_PaintChannelFrom8_
public  Snd_WriteLinearBlastStereo16_

.code
;=============================================================================
; SND_PaintChannelFrom8_  (was: _SND_PaintChannelFrom8)
;
; C: void SND_PaintChannelFrom8(channel_t *ch, sfxcache_t *sc, int count)
;
; On entry:  EAX = ch, EDX = sc, EBX = count
; Internally remap to the gas original's allocation:
;   EBX = ch, ESI = sc, ECX = count, EAX/EDX = lscale/rscale,
;   EDI/EBP = scratch, BL = sample data.
;=============================================================================
SND_PaintChannelFrom8_ proc near
        ; Preserve callee-saved registers (Watcom: only EAX/EDX volatile)
        push    ebx
        push    ecx
        push    esi
        push    edi
        push    ebp

        ; Unpack incoming register args -> gas allocation
        mov     esi, edx                ; esi = sc
        mov     ecx, ebx                ; ecx = count
        mov     ebx, eax                ; ebx = ch

;	if (ch->leftvol > 255)  ch->leftvol = 255;
;	if (ch->rightvol > 255) ch->rightvol = 255;
        mov     eax, [ebx+ch_leftvol]
        mov     edx, [ebx+ch_rightvol]
        cmp     eax, 255
        jna     short LLeftSet
        mov     eax, 255
LLeftSet:
        cmp     edx, 255
        jna     short LRightSet
        mov     edx, 255
LRightSet:

;	lscale = snd_scaletable[ch->leftvol >> 3];
;	rscale = snd_scaletable[ch->rightvol >> 3];
;	sfx = (signed char *)sc->data + ch->pos;
;	ch->pos += count;
        and     eax, 0F8h               ; leftvol >> 3 << 7 == leftvol & 0xF8 << 7
        add     esi, sfxc_data          ; esi = &sc->data
        and     edx, 0F8h
        mov     edi, [ebx+ch_pos]       ; edi = ch->pos
        add     esi, edi                ; esi = sfx = sc->data + ch->pos
        shl     eax, 7                  ; << 7 (snd_scaletable rows are 256 ints = 1024 bytes)
        add     edi, ecx                ; edi = ch->pos + count
        shl     edx, 7
        mov     [ebx+ch_pos], edi       ; ch->pos += count
        add     eax, offset _snd_scaletable   ; eax = lscale
        add     edx, offset _snd_scaletable   ; edx = rscale
        xor     ebx, ebx                ; ebx = 0 (data index)
        mov     bl, [esi+ecx-1]         ; data = sfx[count-1]

        test    ecx, 1
        jz      short LMix8Loop

; odd count: process the first (last-indexed) sample separately
        mov     edi, [eax+ebx*4]        ; lscale[data]
        mov     ebp, [edx+ebx*4]        ; rscale[data]
        add     edi, [_paintbuffer+ecx*8 + psp_left-psp_size]
        add     ebp, [_paintbuffer+ecx*8 + psp_right-psp_size]
        mov     [_paintbuffer+ecx*8 + psp_left-psp_size], edi
        mov     [_paintbuffer+ecx*8 + psp_right-psp_size], ebp
        mov     bl, [esi+ecx-2]
        dec     ecx
        jz      short LDone

;	for (i=0 ; i<count ; i++)
;	{
LMix8Loop:
;		data = sfx[i];
;		paintbuffer[i].left += lscale[data];
;		paintbuffer[i].right += rscale[data];
        mov     edi, [eax+ebx*4]
        mov     ebp, [edx+ebx*4]
        add     edi, [_paintbuffer+ecx*8 + psp_left-psp_size]
        add     ebp, [_paintbuffer+ecx*8 + psp_right-psp_size]
        mov     bl, [esi+ecx-2]
        mov     [_paintbuffer+ecx*8 + psp_left-psp_size], edi
        mov     [_paintbuffer+ecx*8 + psp_right-psp_size], ebp

        mov     edi, [eax+ebx*4]
        mov     ebp, [edx+ebx*4]
        mov     bl, [esi+ecx-3]
        add     edi, [_paintbuffer+ecx*8 + psp_left-psp_size*2]
        add     ebp, [_paintbuffer+ecx*8 + psp_right-psp_size*2]
        mov     [_paintbuffer+ecx*8 + psp_left-psp_size*2], edi
        mov     [_paintbuffer+ecx*8 + psp_right-psp_size*2], ebp

;	}
        sub     ecx, 2
        jnz     short LMix8Loop

LDone:
        pop     ebp
        pop     edi
        pop     esi
        pop     ecx
        pop     ebx
        ret
SND_PaintChannelFrom8_ endp


;=============================================================================
; Snd_WriteLinearBlastStereo16_  (was: _Snd_WriteLinearBlastStereo16)
;
; C: void Snd_WriteLinearBlastStereo16(void)
; void function: no incoming register args. Uses C globals directly.
; Preserves EBX/EDI/ESI.
;=============================================================================
Snd_WriteLinearBlastStereo16_ proc near
        push    esi
        push    edi
        push    ebx

        mov     ecx, [_snd_linear_count]
        mov     ebx, [_snd_p]
        mov     esi, [_snd_vol]
        mov     edi, [_snd_out]

;	for (i=0 ; i<snd_linear_count ; i+=2)
;	{
LWLBLoopTop:
;		val = (snd_p[i]*snd_vol)>>8;  clamp to [0x8000,0x7FFF]
        mov     eax, [ebx+ecx*4-8]
        imul    eax, esi
        sar     eax, 8
        cmp     eax, 07FFFh
        jg      short LClampHigh
        cmp     eax, 0FFFF8000h
        jnl     short LClampDone
        mov     eax, 0FFFF8000h
        jmp     short LClampDone
LClampHigh:
        mov     eax, 07FFFh
LClampDone:

;		val = (snd_p[i+1]*snd_vol)>>8;  clamp
        mov     edx, [ebx+ecx*4-4]
        imul    edx, esi
        sar     edx, 8
        cmp     edx, 07FFFh
        jg      short LClampHigh2
        cmp     edx, 0FFFF8000h
        jnl     short LClampDone2
        mov     edx, 0FFFF8000h
        jmp     short LClampDone2
LClampHigh2:
        mov     edx, 07FFFh
LClampDone2:
        shl     edx, 16
        and     eax, 0FFFFh
        or      edx, eax
        mov     [edi+ecx*2-4], edx      ; store stereo pair (2x 16-bit) as dword

;	}
        sub     ecx, 2
        jnz     short LWLBLoopTop

        pop     ebx
        pop     edi
        pop     esi
        ret
Snd_WriteLinearBlastStereo16_ endp

;=============================================================================
; Translation notes / optimization opportunities:
;
; 1. CALLING CONVENTION: 3-arg function uses Watcom register ABI (EAX/EDX/EBX),
;    NOT cdecl stack. Remapped incoming args to the gas original's register
;    allocation (EBX=ch, ESI=sc, ECX=count) right after the prologue.
;
; 2. CALLEE-SAVED: EBX/ECX/ESI/EDI/EBP preserved in PaintChannelFrom8;
;    EBX/EDI/ESI in WriteLinearBlastStereo16.
;
; 3. GAS MACRO: '_paintbuffer)' is mangled C(paintbuffer) -> _paintbuffer.
;    Address expressions converted from gas scaled-index syntax to MASM
;    [_paintbuffer+ecx*8+disp] form; verified by disassembly.
;
; 4. OPT (note): 'and eax,0F8h; shl eax,7' replaces 'shr eax,3; shl eax,10'
;    (leftvol & 0xF8)<<7 == ((leftvol>>3)<<3)<<7 == (leftvol>>3)<<10.
;    This is exactly what the original does - kept as-is.
;
; 5. The mix loop unrolls 2 samples per iteration (matches original), and
;    the odd-count path peels one iteration first (matches original).
;
; 6. sfxcache_t.data is an INLINE flexible array (byte data[1]) at offset 20,
;    not a pointer. So 'add esi, sfxc_data' points directly at the sample
;    bytes - NO pointer load needed (confirmed by functional test).
;=============================================================================

end