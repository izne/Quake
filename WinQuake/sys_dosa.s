; sys_dosa.s - Floating point control for Watcom C / DOS4GW
;
; Everything else that used to be stubbed out here now lives in C:
;   dos_inportb/outportb/inportw/outportw, outportb/inportb,
;   ptr2real/real2ptr, dos_getmemory/dos_freememory -> sys_dos_wc.c
;   VGA_UpdatePlanarScreen/VGA_UpdateLinearScreen   -> vid_vga.c
;   VideoRegisterSet                                -> vregset.c
;   dos_int86                                       -> dos_int86.c
;
; Watcom C decorates functions with a TRAILING underscore (MaskExceptions_)
; and data with a LEADING one (_ceil_cw).  The renderer .s files use the
; leading form for functions as well, so both are provided.

.model  small
.386
.code

; ================ FP CONTROL FUNCTIONS ================

public  MaskExceptions_
public  Sys_LowFPPrecision_
public  Sys_HighFPPrecision_
public  Sys_PushFPCW_SetHigh_
public  Sys_PopFPCW_
public  Sys_SetFPCW_

public  _MaskExceptions
public  _Sys_LowFPPrecision
public  _Sys_HighFPPrecision
public  _Sys_PushFPCW_SetHigh
public  _Sys_PopFPCW
public  _Sys_SetFPCW

MaskExceptions_ proc near
    fninit
    ret
MaskExceptions_ endp

Sys_LowFPPrecision_ proc near
    fldcw   word ptr [_single_cw]
    ret
Sys_LowFPPrecision_ endp

Sys_HighFPPrecision_ proc near
    fldcw   word ptr [_full_cw]
    ret
Sys_HighFPPrecision_ endp

Sys_PushFPCW_SetHigh_ proc near
    fnstcw  word ptr [_pushed_cw]
    fldcw   word ptr [_full_cw]
    ret
Sys_PushFPCW_SetHigh_ endp

Sys_PopFPCW_ proc near
    fldcw   word ptr [_pushed_cw]
    ret
Sys_PopFPCW_ endp

Sys_SetFPCW_ proc near
    fnstcw  word ptr [_cw]
    mov     ax, word ptr [_cw]
    and     ah, 0F0h
    or      ah, 03h                 ; round mode, 64-bit precision
    mov     word ptr [_full_cw], ax
    and     ah, 0F0h
    or      ah, 0Ch                 ; chop mode, single precision
    mov     word ptr [_single_cw], ax
    and     ah, 0F0h
    or      ah, 08h                 ; ceil mode, single precision
    mov     word ptr [_ceil_cw], ax
    ret
Sys_SetFPCW_ endp

_MaskExceptions proc near
    fninit
    ret
_MaskExceptions endp

_Sys_LowFPPrecision proc near
    fldcw   word ptr [_single_cw]
    ret
_Sys_LowFPPrecision endp

_Sys_HighFPPrecision proc near
    fldcw   word ptr [_full_cw]
    ret
_Sys_HighFPPrecision endp

_Sys_PushFPCW_SetHigh proc near
    fnstcw  word ptr [_pushed_cw]
    fldcw   word ptr [_full_cw]
    ret
_Sys_PushFPCW_SetHigh endp

_Sys_PopFPCW proc near
    fldcw   word ptr [_pushed_cw]
    ret
_Sys_PopFPCW endp

_Sys_SetFPCW proc near
    fnstcw  word ptr [_cw]
    mov     ax, word ptr [_cw]
    and     ah, 0F0h
    or      ah, 03h                 ; round mode, 64-bit precision
    mov     word ptr [_full_cw], ax
    and     ah, 0F0h
    or      ah, 0Ch                 ; chop mode, single precision
    mov     word ptr [_single_cw], ax
    and     ah, 0F0h
    or      ah, 08h                 ; ceil mode, single precision
    mov     word ptr [_ceil_cw], ax
    ret
_Sys_SetFPCW endp

; ================ FP CONTROL DATA ================
; Referenced by the renderer assembly files (fldcw ceil_cw etc.) once they
; are linked back in.

public  _fpenv
public  _ceil_cw
public  _single_cw
public  _full_cw
public  _cw
public  _pushed_cw

.data
_fpenv      db  28 dup(0)
_ceil_cw    dd  0
_single_cw  dd  0
_full_cw    dd  0
_cw         dd  0
_pushed_cw  dd  0

end
