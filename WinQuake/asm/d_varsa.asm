;=============================================================================
; d_varsa.asm - renderer draw variables / tables (ASM-only + C globals)
;
; Faithful MASM (OpenWatcom wasm) translation of WinQuake/d_varsa.s.
; DATA-ONLY module: global draw variables, reciprocal/jump tables.
;
; Symbol naming:
;   - C globals use a LEADING underscore (_d_sdivzstepu, _cacheblock, ...).
;     These are the id386=1 counterparts of the #if !id386 definitions in
;     d_vars.c. Confirmed against quake486.map (e.g. _d_viewbuffer).
;   - ASM-only variables/tables use PLAIN names (izi, pbase, reciprocal_table,
;     advancetable, ...) - referenced directly by other asm modules.
;   - Jump-table entries (Entry2_16, DP_1x1, Spr8Entry2_8, ...) are code labels
;     defined in OTHER asm files. Declared 'extrn :near' so the linker stores
;     their 32-bit addresses into the tables.
;=============================================================================

.386
.model  small

; ---- C globals (leading underscore) ----------------------------------------
public  _d_sdivzstepu, _d_tdivzstepu, _d_zistepu
public  _d_sdivzstepv, _d_tdivzstepv, _d_zistepv
public  _d_sdivzorigin, _d_tdivzorigin, _d_ziorigin
public  _sadjust, _tadjust, _bbextents, _bbextentt
public  _cacheblock, _cachewidth, _d_viewbuffer
public  _d_pzbuffer, _d_zrowbytes, _d_zwidth

; ---- ASM-only variables / tables (plain names) -----------------------------
public  izi, pbase, s, t, sfracf, tfracf, snext, tnext
public  spancountminus1, zi16stepu, sdivz16stepu, tdivz16stepu
public  zi8stepu, sdivz8stepu, tdivz8stepu, pz, izistep
public  reciprocal_table_16, entryvec_table_16
public  DP_Count, DP_u, DP_v, DP_32768, DP_Color, DP_Pix, DP_EntryTable
public  advancetable, sstep, tstep, pspantemp, counttemp, jumptemp
public  reciprocal_table, entryvec_table, spr8entryvec_table

; ---- external code labels (addresses stored in jump tables) ----------------
extrn   Entry2_16:near, Entry3_16:near, Entry4_16:near, Entry5_16:near
extrn   Entry6_16:near, Entry7_16:near, Entry8_16:near, Entry9_16:near
extrn   Entry10_16:near, Entry11_16:near, Entry12_16:near, Entry13_16:near
extrn   Entry14_16:near, Entry15_16:near, Entry16_16:near

extrn   DP_1x1:near, DP_2x2:near, DP_3x3:near, DP_4x4:near

extrn   Entry2_8:near, Entry3_8:near, Entry4_8:near, Entry5_8:near
extrn   Entry6_8:near, Entry7_8:near, Entry8_8:near

extrn   Spr8Entry2_8:near, Spr8Entry3_8:near, Spr8Entry4_8:near, Spr8Entry5_8:near
extrn   Spr8Entry6_8:near, Spr8Entry7_8:near, Spr8Entry8_8:near

.data
    ALIGN 4

;-------------------------------------------------------
; global refresh variables (C globals, .single = float)
;-------------------------------------------------------
_d_sdivzstepu   dd 0.0
_d_tdivzstepu   dd 0.0
_d_zistepu      dd 0.0
_d_sdivzstepv   dd 0.0
_d_tdivzstepv   dd 0.0
_d_zistepv      dd 0.0
_d_sdivzorigin  dd 0.0
_d_tdivzorigin  dd 0.0
_d_ziorigin     dd 0.0

_sadjust        dd 0
_tadjust        dd 0
_bbextents      dd 0
_bbextentt      dd 0

_cacheblock     dd 0
_cachewidth     dd 0
_d_viewbuffer   dd 0
_d_pzbuffer     dd 0
_d_zrowbytes    dd 0
_d_zwidth       dd 0

;-------------------------------------------------------
; ASM-only variables
;-------------------------------------------------------
izi             dd 0

s               dd 0
t               dd 0
snext           dd 0
tnext           dd 0
sfracf          dd 0
tfracf          dd 0
pbase           dd 0
zi8stepu        dd 0
sdivz8stepu     dd 0
tdivz8stepu     dd 0
zi16stepu       dd 0
sdivz16stepu    dd 0
tdivz16stepu    dd 0
spancountminus1 dd 0
pz              dd 0

izistep         dd 0

;-------------------------------------------------------
; local variables for d_draw16.s
;-------------------------------------------------------
; 1/2 .. 1/15 in 0.32 fixed-point form
reciprocal_table_16 dd 040000000h, 02aaaaaaah, 020000000h
                    dd 019999999h, 015555555h, 012492492h
                    dd 010000000h, 00e38e38eh, 00ccccccch, 00ba2e8bah
                    dd 0aaaaaaah, 09d89d89h, 09249249h, 08888888h

; jump table: index -> address of EntryN_16 code label
entryvec_table_16 dd 0, Entry2_16, Entry3_16, Entry4_16
                  dd Entry5_16, Entry6_16, Entry7_16, Entry8_16
                  dd Entry9_16, Entry10_16, Entry11_16, Entry12_16
                  dd Entry13_16, Entry14_16, Entry15_16, Entry16_16

;-------------------------------------------------------
; local variables for d_parta.s
;-------------------------------------------------------
DP_Count        dd 0
DP_u            dd 0
DP_v            dd 0
DP_32768        dd 32768.0              ; 0x47000000
DP_Color        dd 0
DP_Pix          dd 0

DP_EntryTable   dd DP_1x1, DP_2x2, DP_3x3, DP_4x4

; advancetable is 8 bytes; code points to the middle (offset +4) so negative
; offsets work
advancetable    dd 0, 0
sstep           dd 0
tstep           dd 0

pspantemp       dd 0
counttemp       dd 0
jumptemp        dd 0

; 1/2 .. 1/7 in 0.32 fixed-point form
reciprocal_table dd 040000000h, 02aaaaaaah, 020000000h
                 dd 019999999h, 015555555h, 012492492h

entryvec_table  dd 0, Entry2_8, Entry3_8, Entry4_8
                dd Entry5_8, Entry6_8, Entry7_8, Entry8_8

spr8entryvec_table dd 0, Spr8Entry2_8, Spr8Entry3_8, Spr8Entry4_8
                   dd Spr8Entry5_8, Spr8Entry6_8, Spr8Entry7_8, Spr8Entry8_8

;=============================================================================
; Translation notes:
;
; 1. DATA-ONLY: no .code segment, no procedures.
;
; 2. THREE SYMBOL CLASSES:
;    - C globals (_d_*) use leading underscore (Watcom data convention).
;    - ASM-only data uses plain names (quakeasm.h '.extern <name>' with no C()
;      wrapper).
;    - Jump-table entries are external CODE labels declared 'extrn :near';
;      'dd <label>' stores the label's 32-bit address (verified by disassembly).
;
; 3. HEX LITERALS: 0.32 reciprocal constants kept as explicit hex. A leading
;    zero is added where needed (e.g. 040000000h) so wasm parses them as hex
;    numbers rather than identifiers.
;
; 4. DP_32768 uses a float literal -> 0x47000000 (32768.0f).
;
; 5. advancetable is 8 bytes (two dwords) - code indexes it at +4 for negative
;    offsets, so the size must stay 8 bytes.
;=============================================================================

end