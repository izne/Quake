// c_mips.c - validated C fallback for the ASM mip3 surface block drawer.
//
// Used by ASM386 builds: asm\surf8.asm mip3 jumps to C_Mip3_.
// The other three mip routines remain in ASM.

#include "quakedef.h"
#include "r_local.h"

extern int	lightleft, sourcesstep, blocksize, sourcetstep;
extern int	lightdelta, lightdeltastep;
extern int	lightright, lightleftstep, lightrightstep, blockdivshift;
extern unsigned	blockdivmask;
extern void	*prowdestbase;
extern unsigned char	*pbasesource;
extern int	surfrowbytes;
extern unsigned	*r_lightptr;
extern int	r_stepback, r_lightwidth, r_numvblocks;
extern unsigned char	*r_sourcemax;

void C_Mip3 (void)
{
	int	v, i, b, lightstep, lighttemp, light;
	unsigned char	pix, *psource, *prowdest;

	psource = pbasesource;
	prowdest = prowdestbase;

	for (v=0 ; v<r_numvblocks ; v++)
	{
		lightleft = r_lightptr[0];
		lightright = r_lightptr[1];
		r_lightptr += r_lightwidth;
		lightleftstep = (r_lightptr[0] - lightleft) >> 1;
		lightrightstep = (r_lightptr[1] - lightright) >> 1;

		for (i=0 ; i<2 ; i++)
		{
			lighttemp = lightleft - lightright;
			lightstep = lighttemp >> 1;
			light = lightright;

			for (b=1 ; b>=0 ; b--)
			{
				pix = psource[b];
				prowdest[b] = ((unsigned char *)vid.colormap)[(light & 0xFF00) + pix];
				light += lightstep;
			}

			psource += sourcetstep;
			lightright += lightrightstep;
			lightleft += lightleftstep;
			prowdest += surfrowbytes;
		}

		if (psource >= r_sourcemax)
			psource -= r_stepback;
	}
}
