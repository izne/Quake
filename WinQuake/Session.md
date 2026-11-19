# Quake 1 DOS Port - Session Notes

## Project Goal

Port Quake 1 to DOS using OpenWatcom C compiler (Quake-qrsqrt project). The game builds and runs but crashes during initialization with huge memory allocation errors.

## Build Instructions

**IMPORTANT:** Always follow this order when building:

1. **Clean** - Remove previous build artifacts
   ```
   wmake -f Makefile clean
   ```

2. **All** - Compile the project
   ```
   wmake -f Makefile all
   ```

3. **Deploy** - Copy the executable to the run location
   ```
   wmake -f Makefile deploy
   ```

Full build command with environment setup:
```bash
export PATH="/c/WATCOM/BINNT:/c/WATCOM/BINW:$PATH" && export INCLUDE="/c/WATCOM/H" && export WATCOM="/c/WATCOM" && cd "Z:/Quake-qrsqrt/Quake/WinQuake" && wmake -f Makefile clean && wmake -f Makefile all && wmake -f Makefile deploy
```

## Environment

- **Compiler**: OpenWatcom C (wcc386)
- **Target**: DOS/WinQuake with 486 optimization
- **Build System**: wmake
- **Makefile Targets**: all, release, debug, profile, clean
- **Output**: quake486.exe

## Discoveries

1. **Root cause identified**: The crash occurs when loading the "player" model - huge allocation sizes like 1,766,355,408 bytes (0x69402010 in hex) are being requested
2. **Hunk memory is correctly set up**: hunk_size = 8,388,608 (8MB)
3. **Allocation sequence for player model**:
   - 13,748 bytes (header)
   - 12 bytes
   - 57,424 bytes (skins)
   - 848 bytes (triangles)
   - **1,766,355,408 bytes (HUGE!)**
4. **Problem is in DOS port code**, not the data files (original QUAKE.EXE works)
5. **Possible causes**: endianness issue, pointer/integer mismatch, or uninitialized memory in model loading code

## Accomplished

- Identified the crash is in player model loading
- Added safety checks to zone.c (Hunk_AllocName) to cap huge allocations
- Added safety checks to model.c in Mod_LoadAliasModel and Mod_LoadAliasSkin
- Removed duplicate initialization calls in host.c
- Build system works with OpenWatcom

## Modified Files

| File | Changes |
|------|---------|
| zone.c | Added safety caps in Hunk_AllocName to prevent allocations > 4MB |
| model.c | Added safety checks in Mod_LoadAliasModel and Mod_LoadAliasSkin |
| host.c | Removed duplicate initialization calls |

## Still In Progress

Finding the actual bug in the DOS port code that causes wrong size values to be calculated during model loading. The problem is likely in:

- **Endianness**: LittleLong not being applied correctly somewhere
- **Pointer arithmetic error**: Wrong offset calculations
- **Wrong data type usage**: Integer vs. pointer confusion in model.c

After capping allocations at 4MB, we now see negative size errors (-842,870,632), suggesting we're getting closer to the actual bug.

## Relevant Files

- **Z:/Quake-qrsqrt/Quake/WinQuake/zone.c** - Memory allocation, added safety caps
- **Z:/Quake-qrsqrt/Quake/WinQuake/model.c** - Model loading code, added safety checks
- **Z:/Quake-qrsqrt/Quake/WinQuake/host.c** - Host initialization, removed duplicate init calls
- **Z:/Quake-qrsqrt/Quake/WinQuake/r_main.c** - Rendering, R_InitTextures, etc.
- **Z:/Quake-qrsqrt/Quake/WinQuake/vid_dos_wc.c** - DOS video init
