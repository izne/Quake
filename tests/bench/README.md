# Benchmark harness

Automated `timedemo demo1` runs under DOSBox with a **fixed cycle count**, so
numbers are reproducible run-to-run (repeats are byte-identical).

## Requirements

- Windows + DOSBox (default: `C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe`)
- A **local** run directory (DOSBox cannot mount UNC paths)
- Game data: `ID1\PAK0.PAK` (from a registered/shareware install)
- For the stock baseline: `QUAKE.EXE` + `CWSDPMI.EXE` (DJGPP binary)
- For our build: `dos4gw.exe` (DOS/4G extender stub)

The script self-heals: missing `PAK0.PAK`, `dos4gw.exe`, `CWSDPMI.EXE` and
`autoexec.cfg` are restored from `$QuakeData` on every run (the OS temp
cleaner likes to purge large files from the scratch dir).

## How results are captured

| Build | Result file | Notes |
|---|---|---|
| ours (`quake486.exe`) | `timedemo.txt` in run dir | hook in `CL_FinishTimeDemo` (`WinQuake/cl_demo.c`), appends compile date/time + `q_rsqrt=on/off` |
| stock (`QUAKE.EXE`) | `id1\qconsole.log` | run with `-condebug` |

No screen scraping, no keystrokes: the demo is started from the command line
(`+timedemo demo1`).

## Examples

```powershell
# current Watcom build (q_rsqrt on by default)
.\bench.ps1 -GameSrc ..\..\WinQuake\quake486.exe -GameExe quake486.exe `
            -ResultName timedemo.txt -DonePattern fps

# q_rsqrt OFF build:  wmake -f Makefile QRSQRT=    (then same command)
# q_rsqrt ON  build:  wmake -f Makefile            (then same command)

# stock Quake 1.06 baseline
.\bench.ps1 -GameExe QUAKE.EXE -GameArgs "-condebug +timedemo demo1" `
            -ResultName "id1\qconsole.log" -DonePattern fps

# microbenchmark: q_rsqrt() vs LibC sqrt() (tests/sq7test.c)
.\bench.ps1 -GameExe sq7test.exe -GameArgs "> sq7test.txt" `
            -ResultName sq7test.txt -DonePattern "faster|slower"
```

All runs append to `bench_log.txt` in the scratch dir.

## Fixed settings (do not change between compared rows)

```
machine=svga_s3  memsize=16  core=dynamic  cputype=486
cycles=fixed 80000
+timedemo demo1   (969 frames)
```
