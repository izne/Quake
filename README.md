#  Quake 1 fast inverse square root retro-fit
### Implementation of the legendary fast inverse square root optimization across all the critical performance hotspots in Quake 1.


## Overview
Lets have the famous q_rsqrt() from Quake 3 that has been first used in 1999 and put it into the 1996 source code of Quake 1. Additionally we are going to use another compiler (Watcom C), that can also bring 486-specific optimizations

## Why?
To get more FPS on 486 machines.

## Hardware for testing
The test machine is:
- AMD Am5x86-X5 at 160 MHz (4*40MHz FSB)
- 16 MB EDO 70ns
- 256KB L2 cache
- Wait states: 
- Matrox Millenium 2 on PCI
- Baseline (stock Quake 1.06): 14.4 FPS

- - - 

## Optimizations sqrt() to q_rsqrt():
- Core math functions (mathlib.c)
- Entity physics (sv_phys.c)
- Player movement (sv_user.c)
- View effects (view.c)
- Game logic (pr_cmds.c)

## Compiler optimizations for 486
Quake was written (for the DOS part) for DJGPP + CWSDPMI. This results in DJGPP-specific code (e.g. AT&T inline assembly, DPMI registers code for CWSDPMI, etc.). It was done because id Software targeted Pentium and DJGPP offered better results for that. In our case here, we are targeting 486 specifically and want to use a compiler that offers more optimizations for the 486 platform instead. And that would be the compiler known from Doom and DukeNukem3D - Watcom C + DOS4GW extender.
So here are the benefits that we hope to get by using Watcom C:
- aggressive register coloring (minimization of push/pop/mov use)
- shorter instruction stream
- better "straigh-line C loops" (used in span renderer) optimizations
- smaller (and faster for 486) binary files

## 486-optimized compiler flags
Current flags in `WinQuake/Makefile` (`CFLAGS_BASE`):
```
CFLAGS_BASE = -4 -ei -otexan -zp4 -fp5 -fpi87 -mf -bt=dos -s -wx -zq -dDOS $(QRSQRT) -i=.
QRSQRT      = -dUSE_FAST_INVERSE_SQRT        # A/B switch: wmake QRSQRT=  -> sqrt() build
ASMFLAGS    = -4 -fp5 -mf -bt=dos
```
Flag notes:
- `-4`  : target 486 instruction set (no Pentium scheduling - we want 486 code)
- `-ei` : enumerated types are 4 bytes, matching the original gcc/DJGPP build.
          Watcom's default 1-byte enums shrink structs like `daliasframetype_t`
          and crash the alias/skin model readers (fixed in `fbc81c4`)
- `-otexan -fp5 -fpi87` : aggressive opts + inline x87 (FPU present on all 486)
- `-zp4` : 4-byte struct packing, same as gcc
- (removed: `-5` Pentium targeting - wrong CPU for this project)

## Testing

### Benchmark methodology
- DOSBox 0.74-3, `cputype=486`, `core=dynamic`, **`cycles=fixed 80000`**, `machine=svga_s3`, `memsize=16`
- `+timedemo demo1` started from the command line, **969 frames**
- Results read from `timedemo.txt` (hook in `CL_FinishTimeDemo`) / `id1/qconsole.log` (`-condebug` for stock)
- Runs are near-deterministic at fixed cycles - identical builds repeat byte-identically
- Harness: `tests/bench/bench.ps1` (see `tests/bench/README.md`)

### Results (DOSBox, cycles=fixed 80000, demo1, 969 frames)
| Build | sound | `-nosound` |
|---|---|---|
| **Stock Quake 1.06** (DJGPP/CWSDPMI, `QUAKE.EXE`) | **25.7 fps** | **26.2 fps** |
| GPL Quake - Watcom C/DOS4GW, q_rsqrt=**off** | 13.9 fps | 14.2 fps |
| GPL Quake - Watcom C/DOS4GW, q_rsqrt=**on**  | 13.8 / 13.9 fps | 14.2 fps |

Reference (real hardware, the goal post): **stock Quake 1.06 = 14.4 FPS** on the
Am5x86-X5 @ 160 MHz test machine.

### Honest caveats
1. **q_rsqrt shows no gain in DOSBox.** DOSBox recompiles x87 onto the host FPU,
   so `fsqrt`/`fdiv` are artificially cheap and cannot model a real 486
   (where a single `fdiv` costs ~70-90 cycles). The microbenchmark
   `tests/sq7test.c` even reports q_rsqrt as **1.29x slower** in emulation
   (LibC sqrt 0.831 s vs Q_rsqrt 1.077 s, 1e6 iterations) - disassembly shows
   Watcom inlines `fsqrt` + 3 `fdiv` for the sqrt path. **Real-HW validation on
   the Am5x86 is still pending** - that is the number that matters.
2. **The 1.85x stock-vs-Watcom gap is the renderer assembly.** Stock Quake runs
   the hand-written x87 renderer asm (`id386=1`); our Watcom build falls back to
   the C renderer (`id386` is 0 because Watcom does not define `__i386__`).
   The `.s` files are gas/AT&T + C preprocessor syntax - OpenWatcom's `wasm`
   cannot assemble them (empirically confirmed; `ASSEMBLY_COMPATIBILITY.md`'s
   "all compatible" claim is wrong). Converting them (gas -> MASM, `-ecc`
   cdecl calling convention) is the single biggest remaining perf lever and is
   the planned next step.
3. Rows for DJGPP/GPL/q_rsqrt-on-DJGPP variants are still `??` (not yet built).

## Modular testing
**tests/sq7test.c** - compares Q_rsqrt() with LibC's sqrt() using dynamic data generation and DOS protected mode.

Compile with the following optimizations
```
wcl386 -q -d0 -4s -4r -fp5 -mf -ol -ol+ -op -ot -oh -ox -lm -l=dos4g sq7test.c
```

**tests/bench/bench.ps1** - automated DOSBox timedemo harness (see `tests/bench/README.md`).