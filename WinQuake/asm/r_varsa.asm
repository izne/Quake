;=============================================================================
; r_varsa.asm - renderer float constants / ASM-only variables
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/r_varsa.s.
; This is a DATA-ONLY module - no code, just global float constants.
;
; Symbol naming:
;   - Float constants (float_0, fp_64k, Float2ToThe31nd, ...) are ASM-ONLY.
;     They are declared in quakeasm.h as plain '.extern float_point5' (NO C()
;     wrapper), so other asm modules reference them by PLAIN name. Keep plain.
;   - _r_bmodelactive is a C variable (r_vars.c, r_local.h). C data uses a
;     LEADING underscore in both gas and Watcom -> '_r_bmodelactive'.
;     In the C build it's guarded by #if !id386; this asm definition is the
;     id386=1 counterpart.
;
; NOTE: PARTICLE_Z_CLIP = 8.0 (d_ifacea.h:59), expanded from the gas macro.
;=============================================================================

.386
.model  small

; ---- asm-only float constants (plain names, public to other asm modules) ---
public  float_0, float_1, float_minus_1, float_particle_z_clip, float_point5
public  fp_16, fp_64k, fp_1m, fp_1m_minus_1, fp_8, fp_64kx64k
public  FloatZero, Float2ToThe31nd, FloatMinus2ToThe31nd

; ---- C data symbol (leading underscore) ------------------------------------
public  _r_bmodelactive

.data
    ALIGN 4

;-------------------------------------------------------
; float constants
;-------------------------------------------------------
float_0                 dd 0.0                 ; 0x00000000
float_1                 dd 1.0                 ; 0x3F800000
float_minus_1           dd -1.0                ; 0xBF800000
float_particle_z_clip   dd 8.0                 ; 0x41000000 (PARTICLE_Z_CLIP)
float_point5            dd 0.5                 ; 0x3F000000

fp_1m                   dd 1048576.0           ; 0x49800000 (2^20)
fp_1m_minus_1           dd 1048575.0           ; 0x497FFFF0 (2^20 - 1)
fp_64k                  dd 65536.0             ; 0x47800000 (2^16)
fp_8                    dd 8.0                 ; 0x41000000
fp_16                   dd 16.0                ; 0x41800000
fp_64kx64k              dd 0x4f000000          ; (float)0x8000*0x10000 = 2^31

FloatZero               dd 0                   ; 0x00000000 (integer, used as float)
Float2ToThe31nd         dd 0x4f000000          ; float 2^31
FloatMinus2ToThe31nd    dd 0xcf000000          ; float -2^31

;-------------------------------------------------------
; C global refresh variable (id386=1 counterpart)
;-------------------------------------------------------
_r_bmodelactive         dd 0

;=============================================================================
; Translation notes:
;
; 1. DATA-ONLY: no .code segment, no procedures. All values are 32-bit dwords.
;
; 2. FLOAT LITERALS: wasm accepts 'dd <float>' and emits the correct IEEE-754
;    bit pattern (verified: 1.0 -> 3F800000, 0.5 -> 3F000000, etc.). The three
;    '.long 0x........' values in the source are kept as explicit hex since
;    they are raw bit patterns (2^31 constants), not decimal floats.
;
; 3. NAMING: plain names for asm-only constants (quakeasm.h uses '.extern
;    float_point5' with no C() wrapper), leading underscore for the one C
;    data symbol (_r_bmodelactive). This differs from function symbols which
;    use a TRAILING underscore in Watcom.
;
; 4. fp_64kx64k / Float2ToThe31nd both = 0x4f000000 = (float)2^31. Kept as-is
;    from the original (the 0x8000*0x10000 comment overflows 32-bit signed
;    but the bit pattern is what matters).
;=============================================================================

end