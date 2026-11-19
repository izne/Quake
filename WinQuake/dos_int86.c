/*
 * dos_int86.c - DOS interrupt wrapper for Watcom
 * Provides dos_int86() using Watcom's int386()
 */

#include <i86.h>

// Define the global regs structure - needed by vid_vga.c, in_dos.c, etc.
union REGS regs;

int dos_int86(int vec)
{
    int386(vec, &regs, &regs);
    return 0;
}