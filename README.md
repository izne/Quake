# Quake-O: Quake with optimizations

Stock Quake 1 plus a growing set of optional optimizations: the Quake 3-style
`q_rsqrt()`, a move from DJGPP/CWSDPMI to OpenWatcom 1.9 + DOS4GW, and a
complete MASM translation of the original hand-written DOS renderer assembly.
CPU-specific variants (486, K5, and potentially others) select their own
optimized assembly modules and compiler settings.

The goal: more FPS on period hardware, without changing how the game looks
unless you explicitly ask for it.

---

## Test hardware

**486 / Am5x86 (X5):**

- AMD Am5x86-X5 @ 160 MHz (4x40 MHz FSB)
- 16 MB EDO 70 ns, 256 KB L2
- Matrox Millenium 2 (PCI)
- Reference: **stock Quake 1.06 = 14.4 FPS** on this machine
- 86Box result, stock vs full-effects `CPU=486`: 16.3 vs 16.8 FPS

**K5:**

- AMD K5 with the same Matrox Millenium 2 and 16 MB RAM
- Reference: stock Quake with the original Pentium-scheduled asm = 22.2 FPS
- All Watcom builds, with or without K5-specific assembly, score 23.3 FPS:
  the +1.1 comes from the changes shared by every build (q_rsqrt and the
  Watcom C path), not from K5 tuning
- K5-specific modules live in `asm\K5\` and are selected with `CPU=K5`

**K5 negative result:** zero-`fxch` math, converted span drawers, genuine
16-byte loop alignment, `-5r -fp5`, and an A/B with `-5r -fp3 -oaxt` all
scored exactly the same 23.3 FPS on real hardware. An RDTSC microbenchmark on
the K5 confirmed why: cycles/call for original vs K5 code were
`TransformVector` 68 vs 69, `BoxOnPlaneSide` 75 vs 71, and `D_DrawZSpans`
5903 vs 6014 — two of three routines are slightly *slower* after the rewrite,
and the third saves only 4 cycles in a routine that is not per-frame hot.
The frame is limited by something other than the instruction scheduling we
changed. The scheduling rewrites were archived; `asm\K5\` currently holds the
original portable MASM translation, and `CPU=K5` differs from a default build
only by its compiler flags. Instruction-scheduling work for K5 is considered
maxed out — any further gain there must come from structural changes, not more
`fxch`/alignment/flag tuning.

An 86Box configuration is used for repeatable A/B runs on both machines.
DOSBox is used first for visual validation; 86Box only after rendering is
known clean. Real-hardware validation on either machine is still the decisive
test for cycle-level optimizations.

---

## What was done

### 1. Fast inverse square root

`q_rsqrt()` was applied to the critical float hotspots:

- `mathlib.c`
- `sv_phys.c` (entity physics)
- `sv_user.c` (player movement)
- `view.c` (view effects)
- `pr_cmds.c` (game logic)

Build switch in `WinQuake/Makefile`:

```make
QRSQRT = -dUSE_FAST_INVERSE_SQRT   # wmake QRSQRT=  -> original sqrt() build
```

It is on by default. **Caveat:** DOSBox recompiles x87 onto the host FPU, so
`fsqrt`/`fdiv` are artificially cheap there and q_rsqrt shows no gain (the
microbenchmark `tests/sq7test.c` even measures it 1.29x slower in emulation).
Real-hardware numbers are the ones that matter.

### 2. Watcom C / DOS4GW instead of DJGPP

DJGPP-specific AT&T inline assembly and CWSDPMI code were replaced so the project
builds with OpenWatcom 1.9 + DOS4GW, which generates tighter 486 code, uses
register calling conventions by default and aggressively inlines. Watcom's
default 1-byte enums had to be overridden with `-ei`; otherwise structs such as
`daliasframetype_t` shrank and the alias/skin model readers desynchronised.

### 3. All 18 renderer modules converted from GAS to MASM

The original `.s` files are left **pristine**. All 18 `asm\*.asm` modules were
translated from the GAS/AT&T sources:

```
sys_dosa   worlda    r_varsa   d_varsa   snd_mixa  math
d_polysa   d_draw    d_draw16  d_copy    d_scana   r_aclipa
r_aliasa   surf16    d_parta   surf8     d_spr8    r_drawa
r_edgea
```

With `ASM386=1` all of them are linked and `id386=1` compiles out the C
renderer fallbacks. The final build has **zero C renderer helpers**.

---

## Current builds and flags

`WinQuake/Makefile`:

```make
CPUCFLAGS   = -4r -fp3          # overridden to -5r -fp5 by CPU=K5
ASMTARGET   = -4                # overridden to -5 by CPU=K5
CFLAGS_BASE = $(CPUCFLAGS) -ei -otabehiklmnr -zp4 -fpi87 -mf -bt=dos -s -wx -zq -dDOS $(QRSQRT) -i=. -zri -zdl
ASMFLAGS    = $(ASMTARGET) -fp5 -mf -bt=dos
LINKFLAGS   = system dos4g option map=quake486.map option eliminate option stack=256k
ASM386      = 1     # link all 18 converted MASM renderer modules
QTRACE      =       # tracing compiled out
QRSQRT      = -dUSE_FAST_INVERSE_SQRT
```

Release builds omit `-d2`. `-5` is used only for `CPU=K5`; `-6` (Pentium Pro)
is deliberately avoided.

`CPU=486` takes `math`, `d_draw`, `d_draw16` and `d_polysa` from `asm\486\`,
uses `-4r -fp3`, and reduces explosion particles from 1024 to 256.
`CPU=K5` takes those four modules from `asm\K5\`, uses `-5r -fp5` and
`wasm -5`, and keeps full visual effects — it is the base for dropping in
K5-specific assembler later. Plain builds are unchanged: portable `asm\*`,
486 codegen, full effects.

`SKY=0` replaces the C two-layer sky mapper with a single-colour span fill, and
`DLIGHT=0` removes the explosion dynamic light; both are CPU=486 opt-in
performance options, off by default.

These flags are the result of an A/B against the earlier `-4 -otexan -fp5` set:
explicit 486 register calling convention (`-4r`), a speed-only optimiser set
with `-h` (expensive opts) and `-k` (prologue/epilogue in flow graph), 387 FPU
codegen (`-fp3`) instead of Pentium scheduling (`-fp5`), inlined FP rounding
(`-zri`) and direct `DS` load from `DGROUP` (`-zdl`). The old `-x` implied `-s`
(favour size), which partly fought `-t`; it is replaced by the explicit
`b,e,i,l,m,r` set. The new set rendered cleanly and measured slightly faster in
86Box, so it became the default.

---

## Benchmarks and results

### DOSBox harness (fixed cycles)

- DOSBox 0.74-3, `cputype=486`, `core=dynamic`, `cycles=fixed 80000`,
  `machine=svga_s3`, `memsize=16`
- `+timedemo demo1`, 969 frames
- Results from `timedemo.txt` (`CL_FinishTimeDemo` hook) / `id1/qconsole.log`
  (`-condebug` for stock)
- Harness: `tests/bench/bench.ps1` (see `tests/bench/README.md`)

| Build | sound | `-nosound` |
|---|---|---|
| Stock Quake 1.06 (DJGPP/CWSDPMI, `QUAKE.EXE`) | 25.7 fps | 26.2 fps |
| GPL Quake - Watcom, C renderer, q_rsqrt off | 13.9 fps | 14.2 fps |
| GPL Quake - Watcom, C renderer, q_rsqrt on | 13.8/13.9 fps | 14.2 fps |

(mid-project numbers; the final all-ASM build was validated visually in
DOSBox and benchmarked on 86Box.)

### 86Box (same config as the 14.4 FPS real-hardware reference)

Command: `-nosound -nocdaudio +timedemo demo1`

| Build | FPS |
|---|---|
| All-ASM, aggressive 486 flags (`ASMFINAL.EXE`) | 16.6 |
| `CPU=486` build with 486-optimised drawers (`Q486DRAW.EXE`) | 16.8 |
| `CPU=486` defaults (256 explosion particles, `Q486P256.EXE`) | 16.9 |
| `CPU=486` + `SKY=0` + `DLIGHT=0` (`Q486ALL.EXE`) | 17.3 |
| Stock `QUAKE.EXE` | **16.3** |

Each step was checked in DOSBox before benchmarking. The opt-out switches
(`SKY=0`, `DLIGHT=0`) and the reduced particle count are performance options:
they remove visible effects, so the full-effects numbers above are the fair
comparison against stock. Real-hardware validation on the Am5x86 remains the
decisive test; 86Box's timing model may not reflect all 486 instruction costs.

---

## Building

```bat
set WATCOM=C:\WATCOM
set PATH=C:\WATCOM\BINNT;C:\WATCOM\BINW;%PATH%
cd WinQuake
wmake -f Makefile all ASM386=1                       :: portable/full-effects build
wmake -f Makefile all ASM386=1 CPU=486               :: X5/486 build, visuals intact
wmake -f Makefile all ASM386=1 CPU=486 SKY=0 DLIGHT=0 :: max-performance 486 build
wmake -f Makefile all ASM386=1 CPU=K5                 :: K5 build, full effects
```

`QRSQRT=` produces the original `sqrt()` A/B build; `QTRACE=1` produces a
diagnostic trace build (never used for final/performance builds). `CPU=486`
also reduces explosion particles from 1024 to 256; `SKY=0` and `DLIGHT=0` are
opt-in visual trade-offs, off by default.
