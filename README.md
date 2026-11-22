# Quake 1: fast inverse square root + full 486 assembly renderer

A retro-fit of the Quake 3-style `q_rsqrt()` into Quake 1 (1996), combined with a
move from DJGPP/CWSDPMI to OpenWatcom 1.9 + DOS4GW and a complete MASM
translation of the original hand-written DOS renderer assembly.

The goal: more FPS on a real 486, without losing the rendering id Software's
binary produced.

---

## Test hardware

- AMD Am5x86-X5 @ 160 MHz (4x40 MHz FSB)
- 16 MB EDO 70 ns, 256 KB L2
- Matrox Millenium 2 (PCI)
- Reference: **stock Quake 1.06 = 14.4 FPS** on this machine

An 86Box configuration modelling the same machine is used for repeatable A/B
runs. DOSBox is used first for visual validation; 86Box only after rendering is
known clean.

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
CFLAGS_BASE = -4r -ei -otabehiklmnr -zp4 -fp3 -fpi87 -mf -bt=dos -s -wx -zq -dDOS $(QRSQRT) -i=. -zri -zdl
ASMFLAGS    = -4 -fp5 -mf -bt=dos
LINKFLAGS   = system dos4g option map=quake486.map option eliminate option stack=256k
ASM386      = 1     # link all 18 converted MASM renderer modules
QTRACE      =       # tracing compiled out
QRSQRT      = -dUSE_FAST_INVERSE_SQRT
```

Release builds omit `-d2`. `-5`/`-6` are deliberately avoided (Pentium/PPro
targets).

`CPU=486` is an opt-in build that takes `math`, `d_draw`, `d_draw16` and
`d_polysa` from `asm\486\` into a separate `build_486` directory; plain builds
are unchanged. `SKY=0` additionally replaces the C two-layer sky mapper with a
single-colour span fill — a performance option, off by default.

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
| Final all-ASM, original flags (`ASMFINAL_164.EXE`, archived) | 16.4 |
| All-ASM, aggressive 486 flags (`OPTALL.EXE` / current `ASMFINAL.EXE`) | 16.6 |
| `CPU=486` build with 486-optimised drawers (`Q486DRAW.EXE`) | **16.8** |
| Stock `QUAKE.EXE` | **16.3** |

Progressively faster than stock in the same 86Box config. Each step was checked
in DOSBox first; the draw-file optimization added a further ~0.2 FPS. These are
small margins and real-hardware validation on the Am5x86 is still the decisive
test.

---

## Building

```bat
set WATCOM=C:\WATCOM
set PATH=C:\WATCOM\BINNT;C:\WATCOM\BINW;%PATH%
cd WinQuake
wmake -f Makefile all ASM386=1
```

`QRSQRT=` produces the original `sqrt()` A/B build; `QTRACE=1` produces a
diagnostic trace build (never used for final/performance builds).
