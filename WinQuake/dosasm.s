; dosasm.s - Stub for Watcom assembler
; Provides minimal symbols for linking

.model  small
.386
.code

public  _StartMSRInterval
public  _EndMSRInterval

_StartMSRInterval proc near
    xor     eax, eax
    xor     ecx, ecx
    xor     edx, edx
    ret
_StartMSRInterval endp

_EndMSRInterval proc near
    xor     eax, eax
    xor     ecx, ecx
    xor     edx, edx
    ret
_EndMSRInterval endp

end
