#
# Quake 1 Makefile for OpenWatcom C++ - 486 DOS Optimized
# Watcom C + DOS4GW  / Fast Inverse Square Root Optimized Version

# Compiler and tools
CC = wcc386
LINK = wlink
ASM = wasm

# Build directory
BUILDDIR = build

# q_rsqrt feature switch (used by CFLAGS_BASE below).  Build the original
# sqrt() version for A/B benchmarking with:  wmake -f Makefile QRSQRT=
QRSQRT = -dUSE_FAST_INVERSE_SQRT

# ASM386 switch: when set to 1, link the 18 converted MASM renderer modules
# (asm\*.asm) and define -DASM386=1 so quakedef.h enables id386=1, which
# compiles out the C renderer fallbacks in favour of the assembly routines.
#   Build with ASM: wmake -f Makefile all ASM386=1
ASM386 =

# Base compiler flags: 486 target (-4), 4-byte struct packing, inline FPU,
# DOS4GW target, full warnings (-wx), quiet (-zq).
# -ei: enumerated types are int (4 bytes), matching the gcc/DJGPP build.
#      Watcom's default is smallest-enum (1 byte), which shrinks structs like
#      daliasframetype_t/daliasskintype_t and desynchronises the alias/sprite
#      model file readers (pframetype + 1 then advances 1 byte instead of 4).
CFLAGS_BASE = -4 -ei -otexan -zp4 -fp5 -fpi87 -mf -bt=dos -s -wx -zq -dDOS $(QRSQRT) -i=.

# Default build keeps debug info (-d2) for crash diagnosis
CFLAGS = -d2 $(CFLAGS_BASE)

# When ASM386=1, enable id386 in the C sources and select the asm objects.
# (Watcom Make 1.9 uses !ifeq / !else / !endif; plain '=' reassignment.)
!ifeq ASM386 1
CFLAGS = $(CFLAGS) -DASM386=1
!endif

# Assembly flags
ASMFLAGS = -4 -fp5 -mf -bt=dos

# Linker flags for DOS4GW extender
LINKFLAGS = system dos4g option map=quake486.map option eliminate option stack=256k

# Source files - DOS/WinQuake specific
CSOURCES = cd_null.c chase.c cl_demo.c cl_input.c &
	cl_main.c cl_parse.c cl_tent.c cmd.c common.c &
    console.c crc.c cvar.c d_edge.c d_fill.c &
    d_init.c d_modech.c d_part.c d_polyse.c d_scan.c &
    d_sky.c d_sprite.c d_surf.c d_vars.c d_zpoint.c &
    draw.c host.c host_cmd.c keys.c mathlib.c &
    menu.c model.c nonintel.c pr_cmds.c pr_edict.c &
    pr_exec.c r_aclip.c r_alias.c r_bsp.c r_draw.c &
    r_edge.c r_efrag.c r_light.c r_main.c r_misc.c &
    r_part.c r_sky.c r_sprite.c r_surf.c r_vars.c &
    sbar.c screen.c snd_dma.c snd_dos.c snd_mem.c &
    snd_mix.c sv_main.c sv_move.c sv_phys.c sv_user.c &
    sys_dos_wc.c vid_dos_wc.c vid_vga.c view.c wad.c &
    world.c snd_gus.c zone.c in_dos.c vregset.c &
	net_main.c net_dos_wc.c	net_vcr.c net_loop.c &
	dos_int86.c 

# Assembly source files - FP control / VGA helpers only
ASMSOURCES = sys_dosa.s

# Object files (in build directory)
COBJS = $(BUILDDIR)\cd_null.obj $(BUILDDIR)\chase.obj $(BUILDDIR)\cl_demo.obj &
     $(BUILDDIR)\cl_input.obj $(BUILDDIR)\cl_main.obj $(BUILDDIR)\cl_parse.obj &
     $(BUILDDIR)\cl_tent.obj $(BUILDDIR)\cmd.obj $(BUILDDIR)\common.obj &
     $(BUILDDIR)\console.obj $(BUILDDIR)\crc.obj $(BUILDDIR)\cvar.obj &
     $(BUILDDIR)\d_edge.obj $(BUILDDIR)\d_fill.obj $(BUILDDIR)\d_init.obj &
     $(BUILDDIR)\d_modech.obj $(BUILDDIR)\d_part.obj $(BUILDDIR)\d_polyse.obj &
     $(BUILDDIR)\d_scan.obj $(BUILDDIR)\d_sky.obj $(BUILDDIR)\d_sprite.obj &
     $(BUILDDIR)\d_surf.obj $(BUILDDIR)\d_vars.obj $(BUILDDIR)\d_zpoint.obj &
     $(BUILDDIR)\draw.obj $(BUILDDIR)\host.obj $(BUILDDIR)\host_cmd.obj &
     $(BUILDDIR)\keys.obj $(BUILDDIR)\mathlib.obj $(BUILDDIR)\menu.obj &
     $(BUILDDIR)\model.obj $(BUILDDIR)\nonintel.obj $(BUILDDIR)\pr_cmds.obj &
     $(BUILDDIR)\pr_edict.obj $(BUILDDIR)\pr_exec.obj $(BUILDDIR)\r_aclip.obj &
     $(BUILDDIR)\r_alias.obj $(BUILDDIR)\r_bsp.obj $(BUILDDIR)\r_draw.obj &
     $(BUILDDIR)\r_edge.obj $(BUILDDIR)\r_efrag.obj $(BUILDDIR)\r_light.obj &
     $(BUILDDIR)\r_main.obj $(BUILDDIR)\r_misc.obj $(BUILDDIR)\r_part.obj &
     $(BUILDDIR)\r_sky.obj $(BUILDDIR)\r_sprite.obj $(BUILDDIR)\r_surf.obj &
     $(BUILDDIR)\r_vars.obj $(BUILDDIR)\sbar.obj $(BUILDDIR)\screen.obj &
     $(BUILDDIR)\snd_dma.obj $(BUILDDIR)\snd_dos.obj $(BUILDDIR)\snd_mem.obj &
     $(BUILDDIR)\snd_mix.obj $(BUILDDIR)\sv_main.obj $(BUILDDIR)\sv_move.obj &
     $(BUILDDIR)\sv_phys.obj $(BUILDDIR)\sv_user.obj $(BUILDDIR)\sys_dos_wc.obj &
     $(BUILDDIR)\vid_dos_wc.obj $(BUILDDIR)\vid_vga.obj $(BUILDDIR)\view.obj &
     $(BUILDDIR)\wad.obj $(BUILDDIR)\world.obj $(BUILDDIR)\snd_gus.obj &
     $(BUILDDIR)\zone.obj $(BUILDDIR)\in_dos.obj &
 	 $(BUILDDIR)\net_main.obj $(BUILDDIR)\net_dos_wc.obj $(BUILDDIR)\net_vcr.obj $(BUILDDIR)\net_loop.obj &
 	 $(BUILDDIR)\dos_int86.obj $(BUILDDIR)\vregset.obj

# Assembly object files
AOBJS = $(BUILDDIR)\sys_dosa.obj

# ASM386 renderer objects - the 18 converted MASM modules from asm\*.asm.
# These are included in the link only when ASM386=1 (see ALL_OBJS below).
ASM386_OBJS = $(BUILDDIR)\worlda.obj $(BUILDDIR)\r_varsa.obj $(BUILDDIR)\d_varsa.obj &
	$(BUILDDIR)\snd_mixa.obj $(BUILDDIR)\math.obj $(BUILDDIR)\d_polysa.obj &
	$(BUILDDIR)\d_draw.obj $(BUILDDIR)\d_draw16.obj $(BUILDDIR)\d_copy.obj &
	$(BUILDDIR)\d_scana.obj $(BUILDDIR)\r_aclipa.obj $(BUILDDIR)\r_aliasa.obj &
	$(BUILDDIR)\surf16.obj $(BUILDDIR)\d_parta.obj $(BUILDDIR)\surf8.obj &
	$(BUILDDIR)\d_spr8.obj $(BUILDDIR)\r_drawa.obj $(BUILDDIR)\r_edgea.obj

# The full object list fed to the linker: C objects + base asm + (optionally)
# the 18 ASM386 renderer objects.
!ifeq ASM386 1
ALL_OBJS = $(COBJS) $(AOBJS) $(ASM386_OBJS)
!else
ALL_OBJS = $(COBJS) $(AOBJS)
!endif


# Target executable
TARGET = quake486.exe

# Quake1 deployment directory
QUAKEDIR = C:\Users\izne\Downloads\_Quake1

# Default target
all: $(BUILDDIR) $(TARGET)

# Deploy to Quake1 directory
$(QUAKEDIR)\$(TARGET): $(TARGET)
	copy /y $(TARGET) $(QUAKEDIR)\$(TARGET)

deploy: $(QUAKEDIR)\$(TARGET)

# Create build directory
$(BUILDDIR):
	@if not exist $(BUILDDIR) mkdir $(BUILDDIR)

# Main executable
$(TARGET): $(ALL_OBJS)
	$(LINK) $(LINKFLAGS) name $@ file { $(ALL_OBJS) }

# Generic C compilation rule
{.}.c{$(BUILDDIR)}.obj:
	$(CC) $(CFLAGS) -fo=$@ $<

# Explicit assembly rule - FP control / VGA helpers
$(BUILDDIR)\sys_dosa.obj: sys_dosa.s
	$(ASM) $(ASMFLAGS) -fo=$@ $<

# Explicit assembly rules - 18 converted MASM renderer modules (asm\*.asm)
$(BUILDDIR)\worlda.obj:   asm\worlda.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\r_varsa.obj:  asm\r_varsa.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\d_varsa.obj:  asm\d_varsa.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\snd_mixa.obj: asm\snd_mixa.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\math.obj:     asm\math.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\d_polysa.obj: asm\d_polysa.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\d_draw.obj:   asm\d_draw.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\d_draw16.obj: asm\d_draw16.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\d_copy.obj:   asm\d_copy.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\d_scana.obj:  asm\d_scana.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\r_aclipa.obj: asm\r_aclipa.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\r_aliasa.obj: asm\r_aliasa.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\surf16.obj:   asm\surf16.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\d_parta.obj:  asm\d_parta.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\surf8.obj:    asm\surf8.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\d_spr8.obj:   asm\d_spr8.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\r_drawa.obj:  asm\r_drawa.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<
$(BUILDDIR)\r_edgea.obj:  asm\r_edgea.asm
	$(ASM) $(ASMFLAGS) -fo=$@ $<

# Clean up
clean: .SYMBOLIC
	@if exist $(BUILDDIR)\*.obj del $(BUILDDIR)\*.obj
	@if exist $(BUILDDIR) rmdir $(BUILDDIR)
	@if exist *.map del *.map
	@if exist $(TARGET) del $(TARGET)

# Release build (no debug info, maximum optimization)
release: .SYMBOLIC clean
	@echo Building optimized release version...
	@wmake CFLAGS="$(CFLAGS_BASE)"

# Debug build
debug: .SYMBOLIC clean
	@echo Building debug version...
	@wmake CFLAGS="-d2 $(CFLAGS_BASE)"

# Performance profiling build
profile: .SYMBOLIC
	@wmake CFLAGS="-d1 $(CFLAGS_BASE)"

# Help
help: .SYMBOLIC
	@echo Available targets:
	@echo   all      - Build optimized executable (default)
	@echo   release  - Maximum optimization, no debug info
	@echo   profile  - Build with profiling enabled
	@echo   clean    - Remove object files and executable
	@echo   help     - Show this help

#==============================================================================
# USAGE INSTRUCTIONS:
#==============================================================================
#
# 1. Set environment: set PATH=%PATH%;C:\WATCOM\BINNT;C:\WATCOM\BINW
# 2. Set WATCOM=C:\WATCOM
# 3. Run: wmake release
# 4. Copy quake486.exe and DOS4GW.EXE to your Quake directory
#
#==============================================================================