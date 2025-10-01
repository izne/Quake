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
```
CFLAGS = -4 -5 -otexan -zp4 -fp5 -fpi87 -mf -bt=dos -s -wx -zq -dDOS -dUSE_FAST_INVERSE_SQRT -i=.
ASMFLAGS = -4 -fp5 -mf -bt=dos
```


## Testing
Results of the experiment:
- Stock 1996 Quake 1.06: 14.4 FPS
- Stock 1996 Quake 1.06 + noaudio/nonetwor: ?? FPS
- GPL Quake - DJGPP/CWSDPMI: ?? FPS
- GPL Quake - Watcom C/DOS4GW: ?? FPS
- GPL Quake + Q_rsqrt() + DJGPP/CWSDPMI: ?? FPS
- GPL Quake + Q_rsqrt() + Watcom C/DOS4GW: ?? FPS
- GPL Quake + Q_rsqrt() + noaudio/nonetwork + DJGPP/CWSDPMI: ?? FPS
- GPL Quake + Q_rsqrt() + noaudio/nonetwork + Watcom C/DOS4GW: ?? FPS

## Modular testing
**tests/sq7test.c** - compares Q_rsqrt() with LibC's sqrt() using dnamic data generation and DOS protected mode.

Compile with the following optimizations
```
wcl386 -q -d0 -4r -ol -fp3 -lm -l=dos4g sq7test.c
```