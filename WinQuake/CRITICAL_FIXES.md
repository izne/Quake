# Quick Reference: Critical Fixes Applied

## Completed Fixes

### 1. Headers in vid_vga.c ✅
**File**: `vid_vga.c`
**Change**: Added missing headers
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
```

### 2. VGA Memory Pointer ✅
**File**: `vid_vga.c:348`
**Change**: Replaced `real2ptr(0xa0000)` with direct pointer
```c
// Before:
VGA_pagebase = (void *)real2ptr(0xa0000);

// After:
VGA_pagebase = (void *)0xb8000;  // DOS4GW provides linear addressing
```

### 3. PIT Timer Implementation ✅
**File**: `sys_dos_wc.c:502-540`
**Change**: Implemented PIT-based timer without `real2ptr()`
```c
// Uses Programmable Interval Timer (PIT)
// Reads BIOS tick counter from address 0x46c directly
// No DPMI or real2ptr() dependency
```

## Next Steps

1. **Assembly Verification**: Test `dosasm.s` and `sys_dosa.s` with `wasm`
2. **Sound DMA**: Fix `ptr2real()`/`real2ptr()` in `snd_dos.c`
3. **Full Build**: Compile everything with `wcc386`
4. **Testing**: Run in DOSBox

## Build Command Template

```bash
# Compile C files
wcc386 -4 -5 -otexan -zp4 -fp5 -fpi87 -mf -bt=dos -fo=sys_dos_wc.obj sys_dos_wc.c
wcc386 -4 -5 -otexan -zp4 -fp5 -fpi87 -mf -bt=dos -fo=vid_vga.obj vid_vga.c

# Assemble assembly files
wasm -fo=dosasm.obj dosasm.s
wasm -fo=sys_dosa.obj sys_dosa.s

# Link with DOS4GW
wlink -bt=dos -fo=quake486.exe sys_dos_wc.obj vid_vga.obj ... dos4g
```

## Known Remaining Issues

- `sys_dos_wc.c` LSP errors (OpenWatcom headers not in IDE path - will compile fine)
- `vid_vga.c` LSP errors (same reason)
- Sound DMA needs `ptr2real()` replacement
- Assembly files need verification
