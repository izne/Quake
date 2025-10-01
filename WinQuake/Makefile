#
# Quake 1 Makefile for OpenWatcom C++ - 486 DOS Optimized
# Watcom C + DOS4GW  / Fast Inverse Square Root Optimized Version

# Compiler and tools
CC = wcc386
LINK = wlink
ASM = wasm

# Build directory
BUILDDIR = build

# 486-optimized compiler flags
CFLAGS = -4 -5 -otexan -zp4 -fp5 -fpi87 -mf -bt=dos -s -wx -zq -d2 -dDOS -dUSE_FAST_INVERSE_SQRT -i=.

# Assembly flags
ASMFLAGS = -4 -fp5 -mf -bt=dos

# Linker flags for DPMI extender
#LINKFLAGS = system dos4g option map option eliminate option stack=256k
LINKFLAGS = system dos4g option map=quake486.map option eliminate option stack=256k



# Alternative linker flags for CWSDPMI
LINKFLAGS_CWSDPMI = system option nostub option map option eliminate option stack=256k

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
    world.c snd_gus.c zone.c in_dos.c &
	net_main.c net_dos_wc.c	net_vcr.c net_loop.c 

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
	$(BUILDDIR)\net_main.obj $(BUILDDIR)\net_dos_wc.obj $(BUILDDIR)\net_vcr.obj $(BUILDDIR)\net_loop.obj


# Target executable
TARGET = quake486.exe

# Default target
all: $(BUILDDIR) $(TARGET)

# Create build directory
$(BUILDDIR):
	@if not exist $(BUILDDIR) mkdir $(BUILDDIR)

# Main executable
$(TARGET): $(COBJS)
	$(LINK) $(LINKFLAGS) name $@ file { $(COBJS) }

# Generic C compilation rule
{.}.c{$(BUILDDIR)}.obj:
	$(CC) $(CFLAGS) -fo=$@ $<

# Clean up
clean: .SYMBOLIC
	@if exist $(BUILDDIR)\*.obj del $(BUILDDIR)\*.obj
	@if exist $(BUILDDIR) rmdir $(BUILDDIR)
	@if exist *.map del *.map
	@if exist $(TARGET) del $(TARGET)

# Release build (no debug info, maximum optimization)
release: .SYMBOLIC clean
	@echo Building optimized release version...
	@wmake CFLAGS="-d0 $(CFLAGS)"

# Debug build
debug: .SYMBOLIC clean
	@echo Building debug version...
	@wmake CFLAGS="-d2 $(CFLAGS)"

# Performance profiling build
profile: .SYMBOLIC
	@wmake CFLAGS="-d1 $(CFLAGS)"

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