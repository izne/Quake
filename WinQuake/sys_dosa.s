; sys_dosa.s - Floating point control and DOS I/O for Watcom DOS4GW
; Provides ALL stub symbols - multiple naming conventions to cover all cases

.model  small
.386
.code

; FP Control functions - both leading underscore and no-underscore versions
public  _MaskExceptions
public  MaskExceptions
public  _Sys_LowFPPrecision
public  Sys_LowFPPrecision
public  _Sys_HighFPPrecision
public  Sys_HighFPPrecision
public  _Sys_PushFPCW_SetHigh
public  Sys_PushFPCW_SetHigh
public  _Sys_PopFPCW
public  Sys_PopFPCW
public  _Sys_SetFPCW
public  Sys_SetFPCW

; FP Control functions - trailing underscore versions (what Watcom C expects)
public  MaskExceptions_
public  Sys_LowFPPrecision_
public  Sys_HighFPPrecision_
public  Sys_PushFPCW_SetHigh_
public  Sys_PopFPCW_
public  Sys_SetFPCW_

; DOS I/O functions - trailing underscore versions for Watcom calling C
public  _dos_outportb_
public  _dos_outportw_
public  _dos_inportb_
public  _dos_inportw_
public  _ptr2real_
public  _real2ptr_
public  _dos_getmemory_
;public  _dos_int86_  ; now implemented in dos_int86.c
public  _VGA_UpdatePlanarScreen_
public  _VGA_UpdateLinearScreen_

; DOS I/O functions - NO leading underscore, trailing underscore (what C code calls)
public  dos_outportb_
public  dos_outportw_
public  dos_inportb_
public  dos_inportw_
public  ptr2real_
public  real2ptr_
public  dos_getmemory_
;public  dos_int86_    ; now implemented in dos_int86.c
public  VGA_UpdatePlanarScreen_
public  VGA_UpdateLinearScreen_
public  outportb_
public  inportb_
public  VideoRegisterSet_

; ================ Trailing underscore implementations (no leading underscore) ================

outportb_ proc near
    push    bp
    mov     bp, sp
    mov     dx, [bp+4]
    mov     al, [bp+6]
    out     dx, al
    pop     bp
    ret
outportb_ endp

inportb_ proc near
    push    bp
    mov     bp, sp
    mov     dx, [bp+4]
    xor     ax, ax
    in      al, dx
    pop     bp
    ret
inportb_ endp

VideoRegisterSet_ proc near
    xor     ax, ax
    ret
VideoRegisterSet_ endp

dos_outportb_ proc near
    ret
dos_outportb_ endp

dos_outportw_ proc near
    ret
dos_outportw_ endp

dos_inportb_ proc near
    xor     ax, ax
    ret
dos_inportb_ endp

dos_inportw_ proc near
    xor     ax, ax
    ret
dos_inportw_ endp

ptr2real_ proc near
    xor     eax, eax
    ret
ptr2real_ endp

real2ptr_ proc near
    xor     eax, eax
    ret
real2ptr_ endp

dos_getmemory_ proc near
    xor     eax, eax
    ret
dos_getmemory_ endp

; dos_int86_ is now implemented in dos_int86.c using Watcom int386()

VGA_UpdatePlanarScreen_ proc near
    ret
VGA_UpdatePlanarScreen_ endp

VGA_UpdateLinearScreen_ proc near
    ret
VGA_UpdateLinearScreen_ endp

; ================ Leading underscore versions for Watcom calling C ================
public  _dos_outportb_
public  _dos_outportw_
public  _dos_inportb_
public  _dos_inportw_
public  _ptr2real_
public  _real2ptr_
public  _dos_getmemory_
; _dos_int86_ is now implemented in dos_int86.c
public  _VGA_UpdatePlanarScreen_
public  _VGA_UpdateLinearScreen_

_dos_outportb_ proc near
    ret
_dos_outportb_ endp

_dos_outportw_ proc near
    ret
_dos_outportw_ endp

_dos_inportb_ proc near
    xor     ax, ax
    ret
_dos_inportb_ endp

_dos_inportw_ proc near
    xor     ax, ax
    ret
_dos_inportw_ endp

_ptr2real_ proc near
    xor     eax, eax
    ret
_ptr2real_ endp

_real2ptr_ proc near
    xor     eax, eax
    ret
_real2ptr_ endp

_dos_getmemory_ proc near
    xor     eax, eax
    ret
_dos_getmemory_ endp

; _dos_int86_ is now implemented in dos_int86.c

_VGA_UpdatePlanarScreen_ proc near
    ret
_VGA_UpdatePlanarScreen_ endp

_VGA_UpdateLinearScreen_ proc near
    ret
_VGA_UpdateLinearScreen_ endp

; ================ DOS PORT I/O ================

_dos_inportb proc near
    xor     ax, ax
    ret
_dos_inportb endp
dos_inportb proc near
    xor     ax, ax
    ret
dos_inportb endp

_dos_inportw proc near
    xor     ax, ax
    ret
_dos_inportw endp
dos_inportw proc near
    xor     ax, ax
    ret
dos_inportw endp

_dos_outportb proc near
    ret
_dos_outportb endp
dos_outportb proc near
    ret
dos_outportb endp

_dos_outportw proc near
    ret
_dos_outportw endp
dos_outportw proc near
    ret
dos_outportw endp

; ================ DOS INTERRUPT AND MEMORY ================
; Note: dos_int86 is now implemented in dos_int86.c using Watcom int386()
; These are kept for any legacy callers

_dos_int86 proc near
    xor     ax, ax
    ret
_dos_int86 endp
dos_int86 proc near
    xor     ax, ax
    ret
dos_int86 endp

_ptr2real proc near
    xor     eax, eax
    ret
_ptr2real endp
ptr2real proc near
    xor     eax, eax
    ret
ptr2real endp

_real2ptr proc near
    xor     eax, eax
    ret
_real2ptr endp
real2ptr proc near
    xor     eax, eax
    ret
real2ptr endp

_dos_getmemory proc near
    xor     eax, eax
    ret
_dos_getmemory endp
dos_getmemory proc near
    xor     eax, eax
    ret
dos_getmemory endp

_dos_freememory proc near
    ret
_dos_freememory endp
dos_freememory proc near
    ret
dos_freememory endp

; ================ VGA FUNCTIONS ================

_VGA_UpdatePlanarScreen proc near
    ret
_VGA_UpdatePlanarScreen endp
VGA_UpdatePlanarScreen proc near
    ret
VGA_UpdatePlanarScreen endp

_VGA_UpdateLinearScreen proc near
    ret
_VGA_UpdateLinearScreen endp
VGA_UpdateLinearScreen proc near
    ret
VGA_UpdateLinearScreen endp

_VideoRegisterSet proc near
    xor     ax, ax
    ret
_VideoRegisterSet endp
VideoRegisterSet proc near
    xor     ax, ax
    ret
VideoRegisterSet endp

; ================ FP CONTROL FUNCTIONS ================

MaskExceptions_ proc near
    fninit
    ret
MaskExceptions_ endp
MaskExceptions proc near
    fninit
    ret
MaskExceptions endp

Sys_LowFPPrecision_ proc near
    ret
Sys_LowFPPrecision_ endp
Sys_LowFPPrecision proc near
    ret
Sys_LowFPPrecision endp

Sys_HighFPPrecision_ proc near
    ret
Sys_HighFPPrecision_ endp
Sys_HighFPPrecision proc near
    ret
Sys_HighFPPrecision endp

Sys_PushFPCW_SetHigh_ proc near
    ret
Sys_PushFPCW_SetHigh_ endp
Sys_PushFPCW_SetHigh proc near
    ret
Sys_PushFPCW_SetHigh endp

Sys_PopFPCW_ proc near
    ret
Sys_PopFPCW_ endp
Sys_PopFPCW proc near
    ret
Sys_PopFPCW endp

Sys_SetFPCW_ proc near
    fninit
    ret
Sys_SetFPCW_ endp
Sys_SetFPCW proc near
    fninit
    ret
Sys_SetFPCW endp

_MaskExceptions proc near
    fninit
    ret
_MaskExceptions endp

_Sys_LowFPPrecision proc near
    ret
_Sys_LowFPPrecision endp

_Sys_HighFPPrecision proc near
    ret
_Sys_HighFPPrecision endp

_Sys_PushFPCW_SetHigh proc near
    ret
_Sys_PushFPCW_SetHigh endp

_Sys_PopFPCW proc near
    ret
_Sys_PopFPCW endp

_Sys_SetFPCW proc near
    fninit
    ret
_Sys_SetFPCW endp

; ================ VARIABLES ================

public  _fpenv
public  fpenv
public  _ceil_cw
public  ceil_cw
public  _single_cw
public  single_cw
public  _full_cw
public  full_cw
public  _cw
public  cw
public  _pushed_cw
public  pushed_cw
public  _regs
public  regs

.data
_fpenv      db  28 dup(0)
_ceil_cw    dw  0
_single_cw  dw  0
_full_cw    dw  0
_cw         dw  0
_pushed_cw  dw  0
_regs       db  80 dup(0)

; Aliases for underscore versions
fpenv       equ _fpenv
ceil_cw     equ _ceil_cw
single_cw   equ _single_cw
full_cw     equ _full_cw
cw          equ _cw
pushed_cw   equ _pushed_cw
regs        equ _regs

end
