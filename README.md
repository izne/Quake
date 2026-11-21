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

## The rollercoaster (bug hunt)

Getting the ASM renderer clean took several iterations:

1. **C renderer baseline** — correct but slow (~14 FPS vs stock 25.7 FPS in the
   fixed-cycle DOSBox harness). The 1.8x gap was entirely the missing ASM.

2. **First full-ASM build** — fast, but with garbled/black distant walls.

3. **`r_edgea.asm`** — two label fall-throughs were mistranslated
   (`LInsertAndExit` and `Lzcheck_for_newtop`). Fixed via a corrected file that
   was differentially validated against the original GAS with 20,000 randomized
   cases (0 mismatches). A C `R_GenerateSpans` fallback (`fd0e098`) served as a
   safe checkpoint; the corrected ASM was restored in `cfa7ce3`.

4. **Isolation** — a series of single-module builds narrowed the remaining
   artifact down:
   - `RUNWT` / C surface blocks: clean
   - `RUNM` (no `math.asm`) and `RUNC` (no `r_drawa.asm`): still glitched
   - `RUM3` / C mip3 only: **clean** — so the bug was specifically mip3 in
     `asm\surf8.asm`

5. **False leads** — a line-by-line audit declared the MASM mip3 faithful to
   `surf8.s`, and arithmetic models showed 0 mismatches in 200,000 cases. A C
   mip3 helper (`c_mips.c`, commit `7520e65`) fixed the image. Two attempted ASM
   rewrites (`M3ASM`, `M3ASM2`) failed and made the damage worse.

6. **Actual root cause** — an independent engineer compared the files with a
   GAS-vs-MASM differential harness (20,000 cases: 3,758 mismatches with the
   old file, 0 with the fix). Two AT&T-to-Intel operand orders were wrong at
   the end of mip3:

   ```asm
   add  edx, esi     ; wrong  -- GAS: addl %edx,%esi
   add  ebp, edi     ; wrong  -- GAS: addl %ebp,%edi

   add  esi, edx     ; correct
   add  edi, ebp     ; correct
   ```

   `esi` (source texture pointer) and `edi` (surface-cache destination) were
   therefore never advanced at the end of each vblock. Distant surfaces were
   rewritten into the same cache rows while the rest went stale. Single-vblock
   surfaces looked fine, which is why the bug appeared only at distance.

7. **Final fix** (`2f93464`) — applied the two-line correction, deleted
   `c_mips.c`, removed `-d2`, and committed. The build is 18/18 ASM again,
   qtrace compiled out, q_rsqrt on.

### Why the early "19 FPS" was not real

The broken mip3 was *faster* because it did less work: a small set of texels was
rewritten into the same cache addresses instead of walking the whole surface,
and large screen regions were served from stale cache. **16.4 FPS with full
drawing enabled is the meaningful number**, not 19 FPS from a partially
undrawn frame.

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
| All-ASM, aggressive 486 flags (`OPTALL.EXE` / current `ASMFINAL.EXE`) | **16.6** |
| Stock `QUAKE.EXE` | **16.3** |

Effectively stock parity, possibly a hair faster. The 0.3 FPS gap between the
two flag sets is small, but the aggressive set was clean in DOSBox and faster
in 86Box, so it was kept. Real-hardware validation is the next step.

---

## Test artifacts and provenance

All DOSBox test assets live in `C:\tmp\qtrace_run` (8.3 filenames):

| File | Meaning |
|---|---|
| `RUNFINAL.BAT` -> `ASMFINAL.EXE` | final committed all-ASM build (aggressive flags) |
| `RUNOPT.BAT` -> `OPTALL.EXE` | validated all-flags A/B build (code-identical to final) |
| `FINAL.EXE` | safe C `R_GenerateSpans` fallback |
| `PURE.EXE` | pure C renderer baseline |
| `QUAKE.EXE` | stock id Software binary |
| `archive\` | all diagnostic builds, BATs and configs |

SHA-256 hashes:

- `ASMFINAL.EXE` (aggressive flags, current final) — `1FA022603DC6DE1CEBF0A6ED4AED44F3C4FEE2D8C301999981CFA5E99D08B9DD`
- `OPTALL.EXE` — `4522B9FABEA29A6A661D6F5203AD80C00D6BDD1B2DB5579DED84CD4AA557DD9E`
  (same code, different build timestamp)
- `ASMFINAL_164.EXE` (archived, earlier flag set) — `CADFD1F62D60A31FD51DB8B09C80588B46CD3BD7D262017484E22D0DEC694C73`
- validated pre-final `M3FIX.EXE` (archived) — `AF3F4C6C9605A0D01B8E6C2E38A4DF444B215E077E78B5E136B65200F4029226`

`dosbox_c.conf` mounts `C:\tmp\qtrace_run` and launches the chosen EXE with
`+map e1m1`. Always verify the hash of the EXE actually launched before
quoting a number.

---

## Commit history (key milestones)

- `fd0e098` — C `R_GenerateSpans` fallback (safe checkpoint)
- `cfa7ce3` — corrected `r_edgea.asm`, full ASM renderer restored
- `7520e65` — C mip3 helper (clean image, diagnostic)
- `2f93464` — **final**: fixed mip3 pointer advance, removed C fallback, `-d2` off

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
