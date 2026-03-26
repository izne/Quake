/*
 * dos_int86.c - DOS interrupt wrapper for Watcom
 * Provides dos_int86() using Watcom's int386()
 */

#include <i86.h>

extern union REGS regs;

int dos_int86(int vec)
{
    int386(vec, &regs, &regs);
    return 0;
}