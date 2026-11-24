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
- **All 486/X5 benchmark figures in this document are from 86Box** with the
  configuration below. The one 14.4 FPS measurement ever taken on the real
  machine is historical only and is **not used as a reference** — emulation
  and real hardware do not produce comparable absolute numbers here.
- Reference in 86Box: stock `QUAKE.EXE -nosound -nocdaudio +timedemo demo1` =
  **16.3 FPS**
- Current final `QFIN486.EXE` (32px drawer, default in all current builds) =
  **17.9 FPS** in the same 86Box configuration

**K5:**

- AMD K5 with the same Matrox Millenium 2 and 16 MB RAM
- Reference: stock Quake with the original Pentium-scheduled asm = 22.2 FPS
- Watcom builds with the 16px drawer score 23.3–23.4 FPS; the +1.1 over stock
  comes from the changes shared by every build (q_rsqrt and the Watcom C path),
  not from K5 tuning
- With the new 32px span drawer the same builds score **24.5 FPS** (see below)
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
`fxch`/alignment/flag tuning. That structural change is the 32px span drawer
(section 4) — found by RDTSC phase profiling, which showed `D_DrawSpans16`
consuming ~31% of the frame and the per-segment FPU setup, not the pixel loop,
as the cost. A/B on real K5: 8px 21.2, 16px 23.3, 32px **24.5** FPS.

A later 24.7 FPS reading from `CPU=486` builds on the K5 rig was traced to the
486-only `-DREDUCED_EXPLOSION_PARTICLES` (1024→256 explosion particles), not to
486 FPU scheduling. Controlled A/Bs swapping 486 `math`/`d_polysa` ASM, `-4r
-fp3` CFLAGS and `wasm -4` onto the K5 build each scored the same 24.5; adding
only the particle define produced 24.7. `asm\K5\` stays portable — the particle
reduction is a visual trade-off and is deliberately not adopted.

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

### 4. 32-pixel span subdivision (`d_draw32.asm`)

A 19th renderer module, `d_draw32.asm`, draws textured spans in 32-pixel
segments instead of 16. RDTSC profiling on the real K5 showed the per-segment
FPU setup (`fdiv`/gradient work) dominates span drawing, so halving the number
of segments is a net win despite the longer unrolled pixel loop. Rendering is
visually identical to the 16px path.

The tables in the engineer-supplied file were corrected before use:
`reciprocal_table_32` was rescaled to signed 1.31 (`2^31/n`, matching
`reciprocal_table_16`), and `entryvec_table_32` had a spurious `LNoSteps`
entry at index 1 that shifted every handler by one pixel.

Selected by the `d_subdiv32` cvar, **on by default**:

```make
// d_init.c
cvar_t  d_subdiv32 = {"d_subdiv32", "1"};   // 1 = 32px, 0 + d_subdiv16 1 = 16px, 0 + d_subdiv16 0 = 8px
```

`d_draw32.obj` is linked for every ASM386 build from the single global source
`asm\d_draw32.asm`. It is not duplicated into the platform folders — those hold
only the modules with genuine per-CPU rewrites (`math`, `d_polysa`, `d_draw`,
`d_draw16`). No rendering flags or effects change — this is a pure speedup with
full visual fidelity.

---

## Optimization inventory

Every optimization in the tree, by scope. "Global" applies to all builds;
the CPU folders hold only the modules with genuine per-CPU rewrites.

| Scope | Optimization | Where | Notes |
|---|---|---|---|
| Global | Fast inverse square root (`q_rsqrt`) | `mathlib.c`, `sv_phys.c`, `sv_user.c`, `view.c`, `pr_cmds.c` | On by default (`QRSQRT`); real-hardware gain, DOSBox invisible |
| Global | OpenWatcom 1.9 + DOS4GW (was DJGPP/CWSDPMI) | whole C build | Register calling convention, aggressive inlining, tighter 486 code; `-ei` fixes 1-byte enum struct layout |
| Global | All renderer assembly translated GAS -> MASM | `asm\*.asm` (18 modules) | Original `.s` files pristine; `id386=1` compiles out C fallbacks; zero C renderer helpers |
| Global | **32-pixel span subdivision** | `asm\d_draw32.asm` (`d_subdiv32=1`) | New 19th module; halves per-segment FPU setup. +1.1 FPS K5, +1.0 Am5x86. Full visual fidelity |
| 486 / Am5x86 | Zero-`fxch` math | `asm\486\math.asm` | `BoxOnPlaneSide` computes dist1/dist2 in parallel x87 slots; `in[0..2]` kept resident across all 3 dot products; direct memory-operand FMULs |
| 486 / Am5x86 | Zero-`fxch` polygon signed-area test | `asm\486\d_polysa.asm` | `area = term2 - term1`, original sign convention preserved |
| 486 / Am5x86 | FPU setup rewrite in span drawers | `asm\486\d_draw.asm`, `asm\486\d_draw16.asm` | Sequential s/z, t/z, 1/z setup (1 `fxch` vs 13); reversed `[t]`/`[s]` `fistp` order (0 vs 8). `d_draw.asm` also 0 `fxch` in z-span setup (down from 4) |
| 486 / Am5x86 | Compiler/assembler codegen | `-4r -fp3`, `wasm -4` | 486 register calling, 387 FPU codegen |
| 486 / Am5x86 | Reduced explosion particles (1024 -> 256) | `-DREDUCED_EXPLOSION_PARTICLES` | **Visual reduction**, +0.2 FPS; the whole K5 24.7 reading came from this, not FPU scheduling |
| 486 / Am5x86 | Solid sky / no explosion dlight | `SKY=0`, `DLIGHT=0` | Opt-in, **off by default**; visual reductions |
| K5 | Compiler/assembler codegen | `-5r -fp5`, `wasm -5` | Pentium-targeted codegen; full visual effects (no particle reduction) |
| K5 | Assembly scheduling | `asm\K5\` (4 modules) | Folder holds `math`, `d_polysa`, `d_draw`, `d_draw16` but they are **byte-identical to the portable base**. All zero-`fxch`/alignment/flag rewrites were measured on real K5 and rejected (no gain). No K5-specific code optimization survives |

The two CPU folders contain exactly the four override modules
(`math`, `d_polysa`, `d_draw`, `d_draw16`); all other modules, including
`d_draw32.asm`, come from the single global `asm\` copy. The 32px drawer keeps
full visual fidelity everywhere. The only default-on visual reduction in the
tree is the particle count in `CPU=486`, inherited from the original 486 build;
it accounts for the 24.5 -> 24.7 difference if a 486 build is run on the K5
rig, and is deliberately not enabled for `CPU=K5`.

---

## Current builds and flags

`WinQuake/Makefile`:

```make
CPUCFLAGS   = -4r -fp3          # overridden to -5r -fp5 by CPU=K5
ASMTARGET   = -4                # overridden to -5 by CPU=K5
CFLAGS_BASE = $(CPUCFLAGS) -ei -otabehiklmnr -zp4 -fpi87 -mf -bt=dos -s -wx -zq -dDOS $(QRSQRT) -i=. -zri -zdl
ASMFLAGS    = $(ASMTARGET) -fp5 -mf -bt=dos
LINKFLAGS   = system dos4g option map=quake486.map option eliminate option stack=256k
ASM386      = 1     # link all 19 MASM renderer modules (18 converted + d_draw32)
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

### 86Box X5 (all 486 / Am5x86 figures in this document)

All numbers in this section were measured in 86Box, not on real hardware. The
only comparison that matters here is like-for-like within 86Box: stock
`QUAKE.EXE` = **16.3 FPS** versus the current final `QFIN486.EXE` = **17.9 FPS**.
The historical 14.4 FPS reading from the real machine is not a valid reference
for these numbers and is not used as one.

Command: `-nosound -nocdaudio +timedemo demo1`

| Build | FPS |
|---|---|
| All-ASM, aggressive 486 flags (`ASMFINAL.EXE`) | 16.6 |
| `CPU=486` build with 486-optimised drawers (`Q486DRAW.EXE`) | 16.8 |
| `CPU=486` defaults (256 explosion particles, `Q486P256.EXE`) | 16.9 |
| `CPU=486` + `SKY=0` + `DLIGHT=0` (`Q486ALL.EXE`) | 17.3 |
| **Current final, 32px drawer** (`QFIN486.EXE`) | **17.9** |
| Stock `QUAKE.EXE` | **16.3** |

Each step was checked in DOSBox before benchmarking. The opt-out switches
(`SKY=0`, `DLIGHT=0`) and the reduced particle count are performance options:
they remove visible effects, so the full-effects numbers above are the fair
comparison against stock. `QFIN486.EXE` is the current default build with the
32px drawer; its 17.9 is +1.0 over the same EXE with the 16px drawer (16.9),
a pure speedup with no visual change from the drawer itself. Real-hardware
validation on the Am5x86 remains the decisive test; 86Box's timing model may
not reflect all 486 instruction costs.

### Span subdivision A/B (full visual fidelity, no opt-outs)

Same EXE per CPU, only the `d_subdiv32` / `d_subdiv16` cvars changed. Both CPUs
scale monotonically 8 < 16 < 32; the 16px control matches the earlier independent
baseline exactly, so the gain is from the drawer and not link layout.

| CPU | 8px | 16px | **32px (default)** | Gain |
|---|---:|---:|---:|---:|
| AMD K5 (real hardware) | 21.2 | 23.3–23.4 | **24.5** | +1.1 (+4.7%) |
| AMD Am5x86-X5 160 (86Box) | 15.3 | 16.9 | **17.9** | +1.0 (+6%) |

For reference, TurboQuake's `586QUAKE.EXE` scores 24.0 FPS on the same K5 rig;
the 32px build is faster while keeping full effects. Final EXEs:

| EXE | Target | FPS | SHA-256 |
|---|---|---:|---|
| `QFINK5.EXE` | AMD K5 | 24.5 | `9596A38B7E4EE56ECDE8496E9FF58976862E5179625636A3C2D19CFDC5EC9732` |
| `QFIN486.EXE` | Am5x86 / 486 | 17.9 | `302D7D3BC189DAD2A4658D60881DC8EDC59F6D41410E9356B1BA370324D2BEBA` |

Both were validated visually in DOSBox (16px and 32px frames identical-looking)
and on real K5 ("looks like stock Quake, just faster"). They are new files —
no previously deployed final EXE was overwritten.

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
opt-in visual trade-offs, off by default. None of these affect the 32px drawer,
which is on by default through `d_subdiv32` and keeps full visual fidelity.

To A/B the span drawer at runtime without rebuilding:

```
+ d_subdiv32 1                        :: 32px (default)
+ d_subdiv32 0 + d_subdiv16 1         :: 16px
+ d_subdiv32 0 + d_subdiv16 0         :: 8px
```
