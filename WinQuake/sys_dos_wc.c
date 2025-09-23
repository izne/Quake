/*
Copyright (C) 1996-1997 Id Software, Inc.
Modified for OpenWatcom C++ compatibility

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  

See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

WATCOM C++ PORT NOTES:
- Converted DJGPP-specific DPMI calls to Watcom equivalents
- Replaced __dpmi_* functions with int386() and DOS4GW calls
- Modified memory management for Watcom's DOS4GW extender
- Converted inline assembly to Watcom syntax
*/

#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <limits.h>
#include <time.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/stat.h>
#include <string.h>
#include <conio.h>
#include <dos.h>
#include <i86.h>
#include <io.h>
#include <direct.h>
#include <unistd.h>

#include "quakedef.h"
#include "dosisms.h"

// Watcom-specific includes
#pragma pack(push, 1)

#define MINIMUM_WIN_MEMORY			0x800000
#define MINIMUM_WIN_MEMORY_LEVELPAK	(MINIMUM_WIN_MEMORY + 0x100000)

int			end_of_memory;
qboolean	lockmem, lockunlockmem, unlockmem;
static int	win95;

#define STDOUT	1

#define	KEYBUF_SIZE	256
static unsigned char	keybuf[KEYBUF_SIZE];
static int				keybuf_head=0;
static int				keybuf_tail=0;

static quakeparms_t	quakeparms;
int					sys_checksum;
static double		curtime = 0.0;
static double		lastcurtime = 0.0;
static double		oldtime = 0.0;

// Remove static from isDedicated - it's declared extern in quakedef.h
qboolean			isDedicated;

static int			minmem;

float				fptest_temp;

// Watcom: Use linker symbols instead of DJGPP-specific
extern char _end;
#define start_of_memory ((int)&_end)

//=============================================================================

// Watcom keyboard handling
byte        scantokey[128] = 
{ 
//  0           1       2       3       4       5       6       7 
//  8           9       A       B       C       D       E       F 
	0  ,    27,     '1',    '2',    '3',    '4',    '5',    '6', 
	'7',    '8',    '9',    '0',    '-',    '=',    K_BACKSPACE, 9, // 0 
	'q',    'w',    'e',    'r',    't',    'y',    'u',    'i', 
	'o',    'p',    '[',    ']',    13 ,    K_CTRL,'a',  's',      // 1 
	'd',    'f',    'g',    'h',    'j',    'k',    'l',    ';', 
	'\'' ,    '`',    K_SHIFT,'\\',  'z',    'x',    'c',    'v',      // 2 
	'b',    'n',    'm',    ',',    '.',    '/',    K_SHIFT,'*', 
	K_ALT,' ',   0  ,    K_F1, K_F2, K_F3, K_F4, K_F5,   // 3 
	K_F6, K_F7, K_F8, K_F9, K_F10,0  ,    0  , K_HOME, 
	K_UPARROW,K_PGUP,'-',K_LEFTARROW,'5',K_RIGHTARROW,'+',K_END, //4 
	K_DOWNARROW,K_PGDN,K_INS,K_DEL,0,0,             0,              K_F11, 
	K_F12,0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0,        // 5 
	0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0, 
	0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0,        // 6 
	0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0, 
	0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0         // 7 
}; 

byte        shiftscantokey[128] = 
{ 
//  0           1       2       3       4       5       6       7 
//  8           9       A       B       C       D       E       F 
	0  ,    27,     '!',    '@',    '#',    '$',    '%',    '^', 
	'&',    '*',    '(',    ')',    '_',    '+',    K_BACKSPACE, 9, // 0 
	'Q',    'W',    'E',    'R',    'T',    'Y',    'U',    'I', 
	'O',    'P',    '{',    '}',    13 ,    K_CTRL,'A',  'S',      // 1 
	'D',    'F',    'G',    'H',    'J',    'K',    'L',    ':', 
	'"' ,    '~',    K_SHIFT,'|',  'Z',    'X',    'C',    'V',      // 2 
	'B',    'N',    'M',    '<',    '>',    '?',    K_SHIFT,'*', 
	K_ALT,' ',   0  ,    K_F1, K_F2, K_F3, K_F4, K_F5,   // 3 
	K_F6, K_F7, K_F8, K_F9, K_F10,0  ,    0  , K_HOME, 
	K_UPARROW,K_PGUP,'_',K_LEFTARROW,'%',K_RIGHTARROW,'+',K_END, //4 
	K_DOWNARROW,K_PGDN,K_INS,K_DEL,0,0,             0,              K_F11, 
	K_F12,0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0,        // 5 
	0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0, 
	0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0,        // 6 
	0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0, 
	0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0  ,    0         // 7 
}; 

// Watcom interrupt handler
void __interrupt __far TrapKey(void)
{
	keybuf[keybuf_head] = inp(0x60);
	outp(0x20, 0x20);
	keybuf_head = (keybuf_head + 1) & (KEYBUF_SIZE-1);
}

#define SC_UPARROW              0x48
#define SC_DOWNARROW    0x50
#define SC_LEFTARROW            0x4b
#define SC_RIGHTARROW   0x4d
#define SC_LEFTSHIFT   0x2a
#define SC_RIGHTSHIFT   0x36

void MaskExceptions (void);
void Sys_InitFloatTime (void);
void Sys_PushFPCW_SetHigh (void);
void Sys_PopFPCW (void);

#define LEAVE_FOR_CACHE (512*1024)
#define LOCKED_FOR_MALLOC (128*1024)

// Watcom Win95 detection
void Sys_DetectWin95 (void)
{
	union REGS regs;
	
	regs.w.ax = 0x160a;		/* Get Windows Version */
	int386(0x2f, &regs, &regs);

	if(regs.w.ax || regs.h.bh < 4)	/* Not windows or earlier than Win95 */
	{
		win95 = 0;
		lockmem = true;
		lockunlockmem = false;
		unlockmem = true;
	}
	else
	{
		win95 = 1;
		lockunlockmem = COM_CheckParm ("-winlockunlock");

		if (lockunlockmem)
			lockmem = true;
		else
			lockmem = COM_CheckParm ("-winlock");

		unlockmem = lockmem && !lockunlockmem;
	}
}

// Simplified memory allocation for Watcom/DOS4GW
void *dos_getmaxlockedmem(int *size)
{
	void *memory;
	int allocsize;
	int j;
	
	if (standard_quake)
		minmem = MINIMUM_WIN_MEMORY;
	else
		minmem = MINIMUM_WIN_MEMORY_LEVELPAK;

	j = COM_CheckParm("-winmem");
	if (j)
	{
		allocsize = ((int)(Q_atoi(com_argv[j+1]))) * 0x100000;
		if (allocsize < minmem)
			allocsize = minmem;
	}
	else
	{
		allocsize = minmem;
	}

	// Simple malloc for Watcom - DOS4GW handles memory management
	memory = malloc(allocsize);
	if (!memory)
	{
		// Try smaller amounts
		while (allocsize > 0x400000 && !memory)  // Don't go below 4MB
		{
			allocsize -= 0x100000;  // Reduce by 1MB
			memory = malloc(allocsize);
		}
	}
	
	if (!memory)
		Sys_Error("Can't allocate %d Mb of memory", allocsize / 0x100000);
	
	printf("Allocated %d Mb data\n", allocsize / 0x100000);
	
	*size = allocsize;
	return memory;
}

/*
============
Sys_FileTime

returns -1 if not present
============
*/
int	Sys_FileTime (char *path)
{
	struct	stat	buf;
	
	if (stat (path,&buf) == -1)
		return -1;
	
	return buf.st_mtime;
}

void Sys_mkdir (char *path)
{
	mkdir (path);
}

void Sys_Sleep(void)
{
}

char *Sys_ConsoleInput(void)
{
	static char	text[256];
	static int	len = 0;
	char		ch;

	if (!isDedicated)
		return NULL;

	if (! kbhit())
		return NULL;

	ch = getche();

	switch (ch)
	{
		case '\r':
			putch('\n');
			if (len)
			{
				text[len] = 0;
				len = 0;
				return text;
			}
			break;

		case '\b':
			putch(' ');
			if (len)
			{
				len--;
				putch('\b');
			}
			break;

		default:
			text[len] = ch;
			len = (len + 1) & 0xff;
			break;
	}

	return NULL;
}

void Sys_Init(void)
{
	MaskExceptions ();
	Sys_SetFPCW ();

	outp(0x43, 0x34); // set system timer to mode 2
	outp(0x40, 0);    // for the Sys_FloatTime() function
	outp(0x40, 0);

	Sys_InitFloatTime ();
}

void Sys_Shutdown(void)
{
	if (!isDedicated)
	{
		// Restore keyboard interrupt
		_dos_setvect(0x09, _dos_getvect(0x09));
	}
}

#define SC_RSHIFT       0x36 
#define SC_LSHIFT       0x2a 

void Sys_SendKeyEvents (void)
{
	int k, next;
	int outkey;

	// get key events
	while (keybuf_head != keybuf_tail)
	{
		k = keybuf[keybuf_tail++];
		keybuf_tail &= (KEYBUF_SIZE-1);

		if (k==0xe0)
			continue;               // special / pause keys
		next = keybuf[(keybuf_tail-2)&(KEYBUF_SIZE-1)];
		if (next == 0xe1)
			continue;                               // pause key bullshit
		if (k==0xc5 && next == 0x9d) 
		{ 
			Key_Event (K_PAUSE, true);
			continue; 
		} 

		// extended keyboard shift key bullshit 
		if ( (k&0x7f)==SC_LSHIFT || (k&0x7f)==SC_RSHIFT ) 
		{ 
			if ( keybuf[(keybuf_tail-2)&(KEYBUF_SIZE-1)]==0xe0 ) 
				continue; 
			k &= 0x80; 
			k |= SC_RSHIFT; 
		} 

		if (k==0xc5 && keybuf[(keybuf_tail-2)&(KEYBUF_SIZE-1)] == 0x9d)
			continue; // more pause bullshit

		outkey = scantokey[k & 0x7f];

		if (k & 0x80)
			Key_Event (outkey, false);
		else
			Key_Event (outkey, true);
	}
}

// =======================================================================
// General routines
// =======================================================================

void Sys_Printf (char *fmt, ...)
{
	va_list		argptr;
	char		text[1024];
	
	va_start (argptr,fmt);
	vsprintf (text,fmt,argptr);
	va_end (argptr);

	if (cls.state == ca_dedicated)
		fprintf(stderr, "%s", text);
}

void Sys_AtExit (void)
{
	Sys_Shutdown();
}

void Sys_Quit (void)
{
	byte	screen[80*25*2];
	byte	*d;
	char	ver[6];
	int		i;
	union REGS regs;

	// load the sell screen before shutting everything down
	if (registered.value)
		d = COM_LoadHunkFile ("end2.bin"); 
	else
		d = COM_LoadHunkFile ("end1.bin"); 
	if (d)
		memcpy (screen, d, sizeof(screen));

	// write the version number directly to the end screen
	sprintf (ver, " v%4.2f", VERSION);
	for (i=0 ; i<6 ; i++)
		screen[0*80*2 + 72*2 + i*2] = ver[i];

	Host_Shutdown();

	// do the text mode sell screen
	if (d)
	{
		// Watcom: Direct VGA memory access
		memcpy ((void *)0xb8000, screen, 80*25*2); 
	
		// set text pos
		regs.w.ax = 0x0200; 
		regs.h.bh = 0; 
		regs.h.dl = 0; 
		regs.h.dh = 22;
		int386(0x10, &regs, &regs); 
	}
	else
		printf ("couldn't load endscreen.\n");

	exit(0);
}

void Sys_Error (char *error, ...)
{ 
	va_list     argptr;
	char        string[1024];
	
	va_start (argptr,error);
	vsprintf (string,error,argptr);
	va_end (argptr);

	Host_Shutdown();
	fprintf(stderr, "Error: %s\n", string);
	exit(0);
} 

int Sys_FileOpenRead (char *path, int *handle)
{
	int	h;
	struct stat	fileinfo;
	
	h = open (path, O_RDONLY|O_BINARY, 0666);
	*handle = h;
	if (h == -1)
		return -1;
	
	if (fstat (h,&fileinfo) == -1)
		Sys_Error ("Error fstating %s", path);

	return fileinfo.st_size;
}

int Sys_FileOpenWrite (char *path)
{
	int     handle;

	umask (0);
	
	handle = open(path,O_RDWR | O_BINARY | O_CREAT | O_TRUNC, 0666);

	if (handle == -1)
		Sys_Error ("Error opening %s: %s", path,strerror(errno));

	return handle;
}

void Sys_FileClose (int handle)
{
	close (handle);
}

void Sys_FileSeek (int handle, int position)
{
	lseek (handle, position, SEEK_SET);
}

int Sys_FileRead (int handle, void *dest, int count)
{
	return read (handle, dest, count);
}

int Sys_FileWrite (int handle, void *data, int count)
{
	return write (handle, data, count);
}

void Sys_MakeCodeWriteable (unsigned long startaddr, unsigned long length)
{
	// Parameters unused in DOS4GW - memory is always writeable
	(void)startaddr;  // Suppress unused parameter warning
	(void)length;     // Suppress unused parameter warning
}

// Watcom timer functions
double Sys_FloatTime (void)
{
	static unsigned long basetime = 0;
	unsigned long newtime;
	
	// Use clock() for simplicity
	newtime = clock();
	
	if (!basetime)
		basetime = newtime;
		
	return (double)(newtime - basetime) / CLOCKS_PER_SEC;
}

void Sys_InitFloatTime (void)
{
	int		j;

	Sys_FloatTime ();
	oldtime = curtime;

	j = COM_CheckParm("-starttime");
	if (j)
	{
		curtime = (double) (Q_atof(com_argv[j+1]));
	}
	else
	{
		curtime = 0.0;
	}
	lastcurtime = curtime;
}

void Sys_GetMemory(void)
{
	int		j;

	j = COM_CheckParm("-mem");
	if (j)
	{
		quakeparms.memsize = (int) (Q_atof(com_argv[j+1]) * 1024 * 1024);
		quakeparms.membase = malloc (quakeparms.memsize);
	}
	else
	{
		quakeparms.membase = dos_getmaxlockedmem (&quakeparms.memsize);
	}

	fprintf(stderr, "malloc'd: %d\n", quakeparms.memsize);

	if (COM_CheckParm ("-heapsize"))
	{
		int tsize = Q_atoi (com_argv[COM_CheckParm("-heapsize") + 1]) * 1024;
		if (tsize < quakeparms.memsize)
			quakeparms.memsize = tsize;
	}
}

void Sys_PageInProgram(void)
{
	end_of_memory = (int)sbrk(0);
	printf ("Loaded %d Mb image\n", (end_of_memory - start_of_memory) / 0x100000);
}

void Sys_NoFPUExceptionHandler(int whatever)
{
	(void)whatever;  // Suppress unused parameter warning
	printf ("\nError: Quake requires a floating-point processor\n");
	exit (0);
}

void Sys_DefaultExceptionHandler(int whatever)
{
	(void)whatever;  // Suppress unused parameter warning
}

// Watcom keyboard interrupt installation
void (__interrupt __far *old_kb_handler)(void);

int main (int c, char **v)
{
	double			time, oldtime, newtime;
	static	char	cwd[1024];

	printf ("Quake v%4.2f\n", VERSION);
	
	// make sure there's an FPU
	signal(SIGFPE, Sys_NoFPUExceptionHandler);
	signal(SIGABRT, Sys_DefaultExceptionHandler);
	signal(SIGINT, Sys_DefaultExceptionHandler);

	if (fptest_temp >= 0.0)
		fptest_temp += 0.1;

	COM_InitArgv (c, v);

	quakeparms.argc = com_argc;
	quakeparms.argv = com_argv;

	Sys_DetectWin95 ();
	Sys_PageInProgram ();
	Sys_GetMemory ();

	atexit (Sys_AtExit);	// in case we crash

	_getcwd (cwd, sizeof(cwd));
	if (cwd[strlen(cwd)-1] == '/') 
		cwd[strlen(cwd)-1] = 0;
	quakeparms.basedir = cwd;

	isDedicated = (COM_CheckParm ("-dedicated") != 0);

	Sys_Init ();

	if (!isDedicated)
	{
		// Install keyboard handler
		old_kb_handler = _dos_getvect(0x09);
		_dos_setvect(0x09, TrapKey);
	}
	
	Host_Init(&quakeparms);

	oldtime = Sys_FloatTime ();
	while (1)
	{
		newtime = Sys_FloatTime ();
		time = newtime - oldtime;

		if (cls.state == ca_dedicated && (time<sys_ticrate.value))
			continue;

		Host_Frame (time);
		oldtime = newtime;
	}
}

#pragma pack(pop)
