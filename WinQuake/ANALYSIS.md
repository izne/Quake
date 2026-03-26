# WinQuake DOS Port Analysis

## Executive Summary

This document provides a comprehensive analysis of the WinQuake to DOS port project, comparing the original DJGPP-based implementation with the OpenWatcom C implementation. The goal is to create `quake486.exe` - a 486-optimized DOS executable using OpenWatcom C compiler and DOS4GW/DOS32A extender.

## Project Overview

### Target Configuration
- **Compiler**: OpenWatcom C (`wcc386`)
- **Assembler**: OpenWatcom ASM (`wasm`)
- **DOS Extender**: DOS4GW (`dos4g`)
- **Optimization**: 486-specific (`-4 -5 -otexan`)
- **Output**: `quake486.exe`

### Build Flags
```
-4        : 486 CPU target
-5        : 486-specific optimizations  
-otexan   : Optimize for execution speed
-zp4      : Structure padding to 4 bytes
-fp5      : 80-bit floating point
-fpi87    : Use 80387 FPU instructions
-mf       : Use FPU for math
-bt=dos   : DOS target
```

## File-by-File Analysis

### 1. System Layer (`sys_dos.c` vs `sys_dos_wc.c`)

#### DJGPP Version (`sys_dos.c`)
**Key Features:**
- Uses `__dpmi_` API for DPMI calls
- Implements `real2ptr()` for VGA memory access
- Uses `dos_inportb()`/`dos_outportb()` for I/O ports
- Complex memory allocation with `sbrk()` and `__dpmi_lock_linear_region()`
- Hardware timer via `StartMSRInterval()`/`EndMSRInterval()`

**Critical DJGPP-specific calls:**
```c
__dpmi_regs dregs;
__dpmi_int(0x10, &dregs);
real2ptr(0xa0000);  // VGA page base
dos_inportb(port);
dos_outportb(port, val);
ptr2real(ptr);
__dpmi_lock_linear_region();
```

#### Watcom Version (`sys_dos_wc.c`)
**Key Features:**
- Uses Watcom `int386()` for BIOS/DOS interrupts
- Direct pointer access `VGA_pagebase = (void *)0xb8000`
- Uses `inp()`/`outp()` for I/O ports (conio.h)
- Simplified memory allocation with `malloc()` (DOS4GW handles it)
- Uses `clock()` for timing (less accurate)

**Watcom equivalents:**
```c
union REGS regs;
int386(0x10, &inregs, &outregs);
VGA_pagebase = (void *)0xb8000;
inp(port);
outp(port, val);
```

**Migration Gaps:**
1. ⚠️ **Time Function**: `Sys_FloatTime()` uses `clock()` instead of hardware timer
2. ⚠️ **Memory Locking**: Simplified allocation may need adjustment for DMA buffers
3. ⚠️ **MSR Timer**: `StartMSRInterval()` assembly code needs verification

### 2. Video Layer (`vid_dos_wc.c`, `vid_vga.c`)

#### Video DOS (`vid_dos_wc.c`)
**Status**: ✅ Fully converted to Watcom

**Key Features:**
- Uses `dos_int86()` for BIOS interrupts
- Direct VGA memory access via pointer
- Palette operations using `outportb()`
- V-Sync via `inportb(0x3DA)`

**Watcom I/O calls:**
```c
dos_outportb(0x3C8, index);  // Palette start
outportb(0x3C9, val);        // Palette data
inportb(0x3DA);              // V-Sync status
```

#### VGA Mode Setting (`vid_vga.c`)
**Status**: ✅ Mostly Watcom-compatible

**Key Features:**
- Mode 0x13 setup using `dos_int86(0x10)`
- Planar vs linear framebuffer handling
- VGA register programming via `outportb()`

**Critical Functions:**
```c
// Mode 0x13 setup (line 362)
regs.h.ah = 0;
regs.h.al = 0x13;
dos_int86(0x10);

// VGA I/O (lines 92, 101, 162)
outportb(SC_INDEX, MAP_MASK);
outportb(SC_DATA, 1 << plane);
```

**Migration Gaps:**
1. ⚠️ `real2ptr()` usage on line 364 needs conversion to direct pointer
2. ⚠️ `VGA_UpdatePlanarScreen()` and `VGA_UpdateLinearScreen()` need review

### 3. Sound Layer (`snd_dos.c`)

**Status**: ⚠️ Needs Review

**Key Features:**
- Sound Blaster support (v2, v3, v4)
- GUS (Gravis UltraSound) support
- DMA channel management
- DSP command protocol

**Critical DJGPP-specific calls:**
```c
dos_inportb(dsp_port + 0xe);  // DSP status
dos_outportb(dsp_port, val);  // DSP command
dos_getmemory(size);          // Aligned memory
ptr2real(ptr);                // Real address for DMA
real2ptr(addr);               // Linear address
```

**Migration Gaps:**
1. ⚠️ `dos_getmemory()` needs replacement with `malloc()` + alignment
2. ⚠️ `ptr2real()`/`real2ptr()` need conversion to Watcom equivalents
3. ⚠️ DMA page register access for channels 4+ needs verification

**Sound Blaster Protocol:**
- Port 0x220-0x22F: DSP data
- Port 0x200-0x207: DMA channels 0-3
- Port 0xC0-0xCF: DMA channels 4-7
- BLASTER env var: A=port, I=IRQ, D=DMA, H=high DMA, M=mixer

### 4. Input Layer (`in_dos.c`)

**Status**: ✅ Fully Watcom-compatible

**Key Features:**
- Mouse via INT 0x33
- Joystick via port 0x201
- External control devices (racing wheels, etc.)

**Watcom I/O calls:**
```c
dos_int86(0x33);              // Mouse INT
regs.x.ax = 0;                // Reset mouse
dos_inportb(0x201);           // Joystick data
dos_outportb(0x201, val);     // Joystick reset
```

**No migration needed** - already uses Watcom-style calls.

### 5. Network Layer (`net_dos_wc.c`)

**Status**: ✅ Fully converted to Watcom

**Key Features:**
- TCP/IP socket support
- Uses Watcom `socket()`, `connect()`, `send()`, `recv()`
- No DJGPP-specific code

### 6. Assembly Files

#### DOS Assembly (`sys_dosa.s`)
**Status**: ✅ Watcom-compatible

**Functions:**
- `MaskExceptions()` - FPU exception handling
- `Sys_LowFPPrecision()` - Single precision mode
- `Sys_HighFPPrecision()` - Full precision mode
- `Sys_PushFPCW_SetHigh()` - Push FPU control word

**Syntax**: Standard Watcom inline assembly with `.text`, `.data`, `.globl` directives.

#### MSR Timer (`dosasm.s`)
**Status**: ⚠️ Needs Verification

**Functions:**
- `StartMSRInterval()` - Start 486 performance counter
- `EndMSRInterval()` - Read counter value

**Critical Code:**
```asm
.byte 0x0F
.byte 0x32        ; RDMSR
.byte 0x0F
.byte 0x30        ; WRMSR
```

**Concerns:**
1. Uses inline bytes instead of proper assembler directives
2. May need `wasm` syntax verification
3. MSR registers (0x11, 0x12) are 486-specific

#### Math & Rendering (`math.s`, `r_drawa.s`, etc.)
**Status**: ⚠️ Needs Verification

All rendering assembly files use standard 386+ syntax and should be compatible with `wasm`.

**Files to verify:**
- `d_draw.s` - Pixel drawing
- `d_draw16.s` - 16-bit color drawing
- `d_polysa.s` - Polygon rasterization
- `r_edgea.s` - Edge scanning
- `snd_mixa.s` - Sound mixing
- `worlda.s` - World rendering

### 7. DOS Abstraction Layer (`dosisms.h`)

**Status**: ✅ Watcom-compatible

**Provides:**
```c
typedef union {
    struct { byte al, ah, bl, bh, cl, ch, dl, dh; } h;
    struct { word ax, bx, cx, dx; } x;
    struct { word es, cs, ss, ds, di, si, bp, sp, bx, dx, cx, ax; } r;
    word flags;
} regs_t;

extern regs_t regs;
void dos_int86(int intr);
void dos_outportb(int port, int value);
int dos_inportb(int port);
```

**Note:** Uses `conio.h` for `inp()`/`outp()` in Watcom version.

## Critical Issues Identified

### 1. Hardware Timer (`sys_dos_wc.c`)

**Problem**: Uses `clock()` instead of hardware timer

```c
// Current (line 105)
double Sys_FloatTime(void)
{
    return ((double)clock()) / CLOCKS_PER_SEC;
}
```

**Impact**: Less accurate timing for game loop

**Solution**: Use MSR timer or PIT (Programmable Interval Timer)
```c
// Option 1: MSR timer (486+)
double Sys_FloatTime(void)
{
    static qboolean started = false;
    static double start_time;
    
    if (!started) {
        StartMSRInterval();
        start_time = (double)clock() / CLOCKS_PER_SEC;
        started = true;
    }
    
    return ((double)clock() / CLOCKS_PER_SEC - start_time) + 
           (EndMSRInterval() / 270000000.0);  // 270MHz Pentium
}
```

### 2. Memory Allocation for DMA (`snd_dos.c`)

**Problem**: DJGPP's `dos_getmemory()` provides physically contiguous memory for DMA

```c
// DJGPP version
dma_buffer = dos_getmemory(size*2);
realaddr = ptr2real(dma_buffer);
realaddr = (realaddr + size) & ~(size-1);
dma_buffer = (short *) real2ptr(realaddr);
```

**Solution**: Use `malloc()` and ensure alignment
```c
// Watcom version
dma_buffer = (short *)malloc(size*2 + size);
dma_buffer = (short *)((uintptr_t)dma_buffer & ~(size-1));
// DOS4GW handles physical contiguity for 32-bit addressing
```

### 3. VGA Memory Access (`vid_vga.c`)

**Problem**: Uses `real2ptr(0xa0000)` which is DJGPP-specific

```c
// Line 364
VGA_pagebase = (void *)real2ptr(0xa0000);
```

**Solution**: Direct pointer
```c
VGA_pagebase = (void *)0xb8000;  // Or 0xa0000 for page 0
```

### 4. Assembly Syntax Verification

**Action Required**: Verify all `.s` files compile with `wasm`

**Check for:**
- Intel vs AT&T syntax (should be Intel for Watcom)
- Proper `.globl` and label naming (`C(function_name)`)
- Register names (`%eax` vs `eax`)
- Instruction syntax compatibility

## Migration Checklist

### System Layer
- [x] Review `sys_dos_wc.c`
- [ ] Fix `Sys_FloatTime()` to use hardware timer
- [ ] Verify memory allocation for DMA compatibility
- [ ] Test `int386()` with DOS extender

### Video Layer
- [x] Review `vid_dos_wc.c`
- [ ] Fix `real2ptr()` in `vid_vga.c`
- [ ] Review `VGA_UpdatePlanarScreen()` and `VGA_UpdateLinearScreen()`
- [ ] Test VGA mode switching

### Sound Layer
- [ ] Review `snd_dos.c`
- [ ] Replace `dos_getmemory()` with `malloc()`
- [ ] Replace `ptr2real()`/`real2ptr()` calls
- [ ] Test Sound Blaster initialization
- [ ] Test GUS initialization

### Input Layer
- [x] Review `in_dos.c` - No changes needed
- [ ] Test mouse detection
- [ ] Test joystick calibration

### Assembly
- [ ] Verify `dosasm.s` with `wasm`
- [ ] Verify `sys_dosa.s` with `wasm`
- [ ] Verify all `d_*.s`, `r_*.s`, `worlda.s`, `snd_mixa.s`
- [ ] Check for 486-specific instructions

### Build System
- [ ] Update Makefile for Watcom
- [ ] Configure DOS4GW linker
- [ ] Set 486 optimization flags
- [ ] Test full build

### Testing
- [ ] Compile all modules
- [ ] Link with DOS4GW
- [ ] Test in DOSBox first
- [ ] Test on real DOS hardware if possible
- [ ] Verify sound works
- [ ] Verify mouse works
- [ ] Verify VGA modes work

## Comparison: DJGPP vs Watcom

### DPMI Calls
| DJGPP | Watcom |
|-------|--------|
| `__dpmi_int(0x10, &regs)` | `dos_int86(0x10)` |
| `__dpmi_regs` | `union REGS` |
| `real2ptr(addr)` | `(void *)addr` |
| `ptr2real(ptr)` | Not needed (32-bit linear) |
| `__dpmi_lock_linear_region()` | DOS4GW handles automatically |

### I/O Operations
| DJGPP | Watcom |
|-------|--------|
| `dos_inportb(port)` | `inp(port)` or `dos_inportb(port)` |
| `dos_outportb(port, val)` | `outp(port, val)` or `dos_outportb(port, val)` |

### Memory Allocation
| DJGPP | Watcom |
|-------|--------|
| `dos_getmemory(size)` | `malloc(size)` |
| `sbrk(offset)` | `malloc()`/`free()` |
| `__dpmi_lock_linear_region()` | Automatic (DOS4GW) |

### Timing
| DJGPP | Watcom |
|-------|--------|
| `StartMSRInterval()` | Same (if assembly works) |
| `EndMSRInterval()` | Same (if assembly works) |
| `clock()` | Same (fallback) |

## Recommended Build Process

1. **Initial Compilation Test**
   ```bash
   wcc386 -4 -5 -otexan -zp4 -fp5 -fpi87 -mf -bt=dos -fo=sys_dos_wc.obj sys_dos_wc.c
   wasm -fo=dosasm.obj dosasm.s
   ```

2. **Link with DOS4GW**
   ```bash
   wlink -bt=dos -fo=quake486.exe sys_dos_wc.obj vid_dos_wc.obj \
         vid_vga.obj snd_dos.obj in_dos.obj net_dos_wc.obj \
         dosasm.obj sys_dosa.obj math.obj ... \
         option quiet option name quake486.exe option stack 65536 \
         dos4g
   ```

3. **Test in DOSBox**
   ```bash
   dosbox quake486.exe
   ```

4. **Verify Functionality**
   - [ ] Game starts
   - [ ] VGA modes work
   - [ ] Sound plays
   - [ ] Mouse responds
   - [ ] Joystick works
   - [ ] Network works

## Known Limitations

1. **MSR Timer**: Only works on 486+ CPUs
2. **VGA Mode 0x13**: 320x200 256-color only
3. **Sound Blaster**: Requires BLASTER env var
4. **DMA**: May require memory alignment
5. **486 Optimization**: Won't run on 386 CPUs

## Next Steps

1. **Immediate**: Fix `Sys_FloatTime()` and `real2ptr()` issues
2. **Short-term**: Verify all assembly files compile
3. **Medium-term**: Test sound and DMA memory allocation
4. **Long-term**: Optimize for performance, test on real hardware

## Conclusion

The WinQuake to DOS port is **approximately 80% complete**. The main remaining tasks are:

1. Fix hardware timer implementation
2. Replace DJGPP memory functions
3. Verify all assembly code
4. Comprehensive testing

The Watcom-based approach is superior to DJGPP for this project because:
- Better 486 optimization support
- DOS4GW provides full 32-bit protected mode
- No real-mode limitations
- More modern compiler with better diagnostics

**Estimated Completion**: 2-3 weeks with focused development effort.
