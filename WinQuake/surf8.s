/*

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

*/
//
// surf8.s
// x86 assembly-language 8 bpp surface block drawing code.
//

#include "asm_i386_asm.h"
#include "quakeasm.h"
#include "asm_draw.h"

#if	id386

	.data

sb_v:		.long	0

	.text

	.align 4
.globl _R_Surf8Start
_R_Surf8Start:

//----------------------------------------------------------------------
// Surface block drawer for mip level 0
//----------------------------------------------------------------------

	.align 4
.globl _R_DrawSurfaceBlock8_mip0
_R_DrawSurfaceBlock8_mip0:
	pushl	%ebp				// preserve caller's stack frame
	pushl	%edi
	pushl	%esi				// preserve register variables
	pushl	%ebx

//		for (v=0 ; v<numvblocks ; v++)
//		{
	movl	_r_lightptr,%ebx
	movl	_r_numvblocks,%eax

	movl	%eax,sb_v
	movl	_prowdestbase,%edi

	movl	_pbasesource,%esi

Lv_loop_mip0:

//			lightleft = lightptr[0];
//			lightright = lightptr[1];
//			lightdelta = (lightleft - lightright) & 0xFFFFF;
	movl	(%ebx),%eax			// lightleft
	movl	4(%ebx),%edx		// lightright

	movl	%eax,%ebp
	movl	_r_lightwidth,%ecx

	movl	%edx,_lightright
	subl	%edx,%ebp

	andl	$0xFFFFF,%ebp
	leal	(%ebx,%ecx,4),%ebx

//			lightptr += lightwidth;
	movl	%ebx,_r_lightptr

//			lightleftstep = (lightptr[0] - lightleft) >> blockdivshift;
//			lightrightstep = (lightptr[1] - lightright) >> blockdivshift;
//			lightdeltastep = ((lightleftstep - lightrightstep) & 0xFFFFF) |
//					0xF0000000;
	movl	4(%ebx),%ecx	// lightptr[1]
	movl	(%ebx),%ebx		// lightptr[0]

	subl	%eax,%ebx
	subl	%edx,%ecx

	sarl	$4,%ecx
	orl		$0xF0000000,%ebp

	sarl	$4,%ebx
	movl	%ecx,_lightrightstep

	subl	%ecx,%ebx
	andl	$0xFFFFF,%ebx

	orl		$0xF0000000,%ebx
	subl	%ecx,%ecx	// high word must be 0 in loop for addressing

	movl	%ebx,_lightdeltastep
	subl	%ebx,%ebx	// high word must be 0 in loop for addressing

Lblockloop8_mip0:
	movl	%ebp,_lightdelta
	movb	14(%esi),%cl

	sarl	$4,%ebp
	movb	%dh,%bh

	movb	15(%esi),%bl
	addl	%ebp,%edx

	movb	%dh,%ch
	addl	%ebp,%edx

	movb	0x12345678(%ebx),%ah
LBPatch0:
	movb	13(%esi),%bl

	movb	0x12345678(%ecx),%al
LBPatch1:
	movb	12(%esi),%cl

	movb	%dh,%bh
	addl	%ebp,%edx

	rorl	$16,%eax
	movb	%dh,%ch

	addl	%ebp,%edx
	movb	0x12345678(%ebx),%ah
LBPatch2:

	movb	11(%esi),%bl
	movb	0x12345678(%ecx),%al
LBPatch3:

	movb	10(%esi),%cl
	movl	%eax,12(%edi)

	movb	%dh,%bh
	addl	%ebp,%edx

	movb	%dh,%ch
	addl	%ebp,%edx

	movb	0x12345678(%ebx),%ah
LBPatch4:
	movb	9(%esi),%bl

	movb	0x12345678(%ecx),%al
LBPatch5:
	movb	8(%esi),%cl

	movb	%dh,%bh
	addl	%ebp,%edx

	rorl	$16,%eax
	movb	%dh,%ch

	addl	%ebp,%edx
	movb	0x12345678(%ebx),%ah
LBPatch6:

	movb	7(%esi),%bl
	movb	0x12345678(%ecx),%al
LBPatch7:

	movb	6(%esi),%cl
	movl	%eax,8(%edi)

	movb	%dh,%bh
	addl	%ebp,%edx

	movb	%dh,%ch
	addl	%ebp,%edx

	movb	0x12345678(%ebx),%ah
LBPatch8:
	movb	5(%esi),%bl

	movb	0x12345678(%ecx),%al
LBPatch9:
	movb	4(%esi),%cl

	movb	%dh,%bh
	addl	%ebp,%edx

	rorl	$16,%eax
	movb	%dh,%ch

	addl	%ebp,%edx
	movb	0x12345678(%ebx),%ah
LBPatch10:

	movb	3(%esi),%bl
	movb	0x12345678(%ecx),%al
LBPatch11:

	movb	2(%esi),%cl
	movl	%eax,4(%edi)

	movb	%dh,%bh
	addl	%ebp,%edx

	movb	%dh,%ch
	addl	%ebp,%edx

	movb	0x12345678(%ebx),%ah
LBPatch12:
	movb	1(%esi),%bl

	movb	0x12345678(%ecx),%al
LBPatch13:
	movb	(%esi),%cl

	movb	%dh,%bh
	addl	%ebp,%edx

	rorl	$16,%eax
	movb	%dh,%ch

	movb	0x12345678(%ebx),%ah
LBPatch14:
	movl	_lightright,%edx

	movb	0x12345678(%ecx),%al
LBPatch15:
	movl	_lightdelta,%ebp

	movl	%eax,(%edi)

	addl	_sourcetstep,%esi
	addl	_surfrowbytes,%edi

	addl	_lightrightstep,%edx
	addl	_lightdeltastep,%ebp

	movl	%edx,_lightright
	jc		Lblockloop8_mip0

//			if (pbasesource >= r_sourcemax)
//				pbasesource -= stepback;

	cmpl	_r_sourcemax,%esi
	jb		LSkip_mip0
	subl	_r_stepback,%esi
LSkip_mip0:

	movl	_r_lightptr,%ebx
	decl	sb_v

	jnz		Lv_loop_mip0

	popl	%ebx				// restore register variables
	popl	%esi
	popl	%edi
	popl	%ebp				// restore the caller's stack frame
	ret


//----------------------------------------------------------------------
// Surface block drawer for mip level 1
//----------------------------------------------------------------------

	.align 4
.globl _R_DrawSurfaceBlock8_mip1
_R_DrawSurfaceBlock8_mip1:
	pushl	%ebp				// preserve caller's stack frame
	pushl	%edi
	pushl	%esi				// preserve register variables
	pushl	%ebx

//		for (v=0 ; v<numvblocks ; v++)
//		{
	movl	_r_lightptr,%ebx
	movl	_r_numvblocks,%eax

	movl	%eax,sb_v
	movl	_prowdestbase,%edi

	movl	_pbasesource,%esi

Lv_loop_mip1:

//			lightleft = lightptr[0];
//			lightright = lightptr[1];
//			lightdelta = (lightleft - lightright) & 0xFFFFF;
	movl	(%ebx),%eax			// lightleft
	movl	4(%ebx),%edx		// lightright

	movl	%eax,%ebp
	movl	_r_lightwidth,%ecx

	movl	%edx,_lightright
	subl	%edx,%ebp

	andl	$0xFFFFF,%ebp
	leal	(%ebx,%ecx,4),%ebx

//			lightptr += lightwidth;
	movl	%ebx,_r_lightptr

//			lightleftstep = (lightptr[0] - lightleft) >> blockdivshift;
//			lightrightstep = (lightptr[1] - lightright) >> blockdivshift;
//			lightdeltastep = ((lightleftstep - lightrightstep) & 0xFFFFF) |
//					0xF0000000;
	movl	4(%ebx),%ecx	// lightptr[1]
	movl	(%ebx),%ebx		// lightptr[0]

	subl	%eax,%ebx
	subl	%edx,%ecx

	sarl	$3,%ecx
	orl		$0x70000000,%ebp

	sarl	$3,%ebx
	movl	%ecx,_lightrightstep

	subl	%ecx,%ebx
	andl	$0xFFFFF,%ebx

	orl		$0xF0000000,%ebx
	subl	%ecx,%ecx	// high word must be 0 in loop for addressing

	movl	%ebx,_lightdeltastep
	subl	%ebx,%ebx	// high word must be 0 in loop for addressing

Lblockloop8_mip1:
	movl	%ebp,_lightdelta
	movb	6(%esi),%cl

	sarl	$3,%ebp
	movb	%dh,%bh

	movb	7(%esi),%bl
	addl	%ebp,%edx

	movb	%dh,%ch
	addl	%ebp,%edx

	movb	0x12345678(%ebx),%ah
LBPatch22:
	movb	5(%esi),%bl

	movb	0x12345678(%ecx),%al
LBPatch23:
	movb	4(%esi),%cl

	movb	%dh,%bh
	addl	%ebp,%edx

	rorl	$16,%eax
	movb	%dh,%ch

	addl	%ebp,%edx
	movb	0x12345678(%ebx),%ah
LBPatch24:

	movb	3(%esi),%bl
	movb	0x12345678(%ecx),%al
LBPatch25:

	movb	2(%esi),%cl
	movl	%eax,4(%edi)

	movb	%dh,%bh
	addl	%ebp,%edx

	movb	%dh,%ch
	addl	%ebp,%edx

	movb	0x12345678(%ebx),%ah
LBPatch26:
	movb	1(%esi),%bl

	movb	0x12345678(%ecx),%al
LBPatch27:
	movb	(%esi),%cl

	movb	%dh,%bh
	addl	%ebp,%edx

	rorl	$16,%eax
	movb	%dh,%ch

	movb	0x12345678(%ebx),%ah
LBPatch28:
	movl	_lightright,%edx

	movb	0x12345678(%ecx),%al
LBPatch29:
	movl	_lightdelta,%ebp

	movl	%eax,(%edi)
	movl	_sourcetstep,%eax

	addl	%eax,%esi
	movl	_surfrowbytes,%eax

	addl	%eax,%edi
	movl	_lightrightstep,%eax

	addl	%eax,%edx
	movl	_lightdeltastep,%eax

	addl	%eax,%ebp
	movl	%edx,_lightright

	jc		Lblockloop8_mip1

//			if (pbasesource >= r_sourcemax)
//				pbasesource -= stepback;

	cmpl	_r_sourcemax,%esi
	jb		LSkip_mip1
	subl	_r_stepback,%esi
LSkip_mip1:

	movl	_r_lightptr,%ebx
	decl	sb_v

	jnz		Lv_loop_mip1

	popl	%ebx				// restore register variables
	popl	%esi
	popl	%edi
	popl	%ebp				// restore the caller's stack frame
	ret


//----------------------------------------------------------------------
// Surface block drawer for mip level 2
//----------------------------------------------------------------------

	.align 4
.globl _R_DrawSurfaceBlock8_mip2
_R_DrawSurfaceBlock8_mip2:
	pushl	%ebp				// preserve caller's stack frame
	pushl	%edi
	pushl	%esi				// preserve register variables
	pushl	%ebx

//		for (v=0 ; v<numvblocks ; v++)
//		{
	movl	_r_lightptr,%ebx
	movl	_r_numvblocks,%eax

	movl	%eax,sb_v
	movl	_prowdestbase,%edi

	movl	_pbasesource,%esi

Lv_loop_mip2:

//			lightleft = lightptr[0];
//			lightright = lightptr[1];
//			lightdelta = (lightleft - lightright) & 0xFFFFF;
	movl	(%ebx),%eax			// lightleft
	movl	4(%ebx),%edx		// lightright

	movl	%eax,%ebp
	movl	_r_lightwidth,%ecx

	movl	%edx,_lightright
	subl	%edx,%ebp

	andl	$0xFFFFF,%ebp
	leal	(%ebx,%ecx,4),%ebx

//			lightptr += lightwidth;
	movl	%ebx,_r_lightptr

//			lightleftstep = (lightptr[0] - lightleft) >> blockdivshift;
//			lightrightstep = (lightptr[1] - lightright) >> blockdivshift;
//			lightdeltastep = ((lightleftstep - lightrightstep) & 0xFFFFF) |
//					0xF0000000;
	movl	4(%ebx),%ecx	// lightptr[1]
	movl	(%ebx),%ebx		// lightptr[0]

	subl	%eax,%ebx
	subl	%edx,%ecx

	sarl	$2,%ecx
	orl		$0x30000000,%ebp

	sarl	$2,%ebx
	movl	%ecx,_lightrightstep

	subl	%ecx,%ebx

	andl	$0xFFFFF,%ebx

	orl		$0xF0000000,%ebx
	subl	%ecx,%ecx	// high word must be 0 in loop for addressing

	movl	%ebx,_lightdeltastep
	subl	%ebx,%ebx	// high word must be 0 in loop for addressing

Lblockloop8_mip2:
	movl	%ebp,_lightdelta
	movb	2(%esi),%cl

	sarl	$2,%ebp
	movb	%dh,%bh

	movb	3(%esi),%bl
	addl	%ebp,%edx

	movb	%dh,%ch
	addl	%ebp,%edx

	movb	0x12345678(%ebx),%ah
LBPatch18:
	movb	1(%esi),%bl

	movb	0x12345678(%ecx),%al
LBPatch19:
	movb	(%esi),%cl

	movb	%dh,%bh
	addl	%ebp,%edx

	rorl	$16,%eax
	movb	%dh,%ch

	movb	0x12345678(%ebx),%ah
LBPatch20:
	movl	_lightright,%edx

	movb	0x12345678(%ecx),%al
LBPatch21:
	movl	_lightdelta,%ebp

	movl	%eax,(%edi)
	movl	_sourcetstep,%eax

	addl	%eax,%esi
	movl	_surfrowbytes,%eax

	addl	%eax,%edi
	movl	_lightrightstep,%eax

	addl	%eax,%edx
	movl	_lightdeltastep,%eax

	addl	%eax,%ebp
	movl	%edx,_lightright

	jc		Lblockloop8_mip2

//			if (pbasesource >= r_sourcemax)
//				pbasesource -= stepback;

	cmpl	_r_sourcemax,%esi
	jb		LSkip_mip2
	subl	_r_stepback,%esi
LSkip_mip2:

	movl	_r_lightptr,%ebx
	decl	sb_v

	jnz		Lv_loop_mip2

	popl	%ebx				// restore register variables
	popl	%esi
	popl	%edi
	popl	%ebp				// restore the caller's stack frame
	ret


//----------------------------------------------------------------------
// Surface block drawer for mip level 3
//----------------------------------------------------------------------

	.align 4
.globl _R_DrawSurfaceBlock8_mip3
_R_DrawSurfaceBlock8_mip3:
	pushl	%ebp				// preserve caller's stack frame
	pushl	%edi
	pushl	%esi				// preserve register variables
	pushl	%ebx

//		for (v=0 ; v<numvblocks ; v++)
//		{
	movl	_r_lightptr,%ebx
	movl	_r_numvblocks,%eax

	movl	%eax,sb_v
	movl	_prowdestbase,%edi

	movl	_pbasesource,%esi

Lv_loop_mip3:

//			lightleft = lightptr[0];
//			lightright = lightptr[1];
//			lightdelta = (lightleft - lightright) & 0xFFFFF;
	movl	(%ebx),%eax			// lightleft
	movl	4(%ebx),%edx		// lightright

	movl	%eax,%ebp
	movl	_r_lightwidth,%ecx

	movl	%edx,_lightright
	subl	%edx,%ebp

	andl	$0xFFFFF,%ebp
	leal	(%ebx,%ecx,4),%ebx

	movl	%ebp,_lightdelta
//			lightptr += lightwidth;
	movl	%ebx,_r_lightptr

//			lightleftstep = (lightptr[0] - lightleft) >> blockdivshift;
//			lightrightstep = (lightptr[1] - lightright) >> blockdivshift;
//			lightdeltastep = ((lightleftstep - lightrightstep) & 0xFFFFF) |
//					0xF0000000;
	movl	4(%ebx),%ecx	// lightptr[1]
	movl	(%ebx),%ebx		// lightptr[0]

	subl	%eax,%ebx
	subl	%edx,%ecx

	sarl	$1,%ecx

	sarl	$1,%ebx
	movl	%ecx,_lightrightstep

	subl	%ecx,%ebx
	andl	$0xFFFFF,%ebx

	sarl	$1,%ebp
	orl		$0xF0000000,%ebx

	movl	%ebx,_lightdeltastep
	subl	%ebx,%ebx	// high word must be 0 in loop for addressing

	movb	1(%esi),%bl
	subl	%ecx,%ecx	// high word must be 0 in loop for addressing

	movb	%dh,%bh
	movb	(%esi),%cl

	addl	%ebp,%edx
	movb	%dh,%ch

	movb	0x12345678(%ebx),%al
LBPatch16:
	movl	_lightright,%edx

	movb	%al,1(%edi)
	movb	0x12345678(%ecx),%al
LBPatch17:

	movb	%al,(%edi)
	movl	_sourcetstep,%eax

	addl	%eax,%esi
	movl	_surfrowbytes,%eax

	addl	%eax,%edi
	movl	_lightdeltastep,%eax

	movl	_lightdelta,%ebp
	movb	(%esi),%cl

	addl	%eax,%ebp
	movl	_lightrightstep,%eax

	sarl	$1,%ebp
	addl	%eax,%edx

	movb	%dh,%bh
	movb	1(%esi),%bl

	addl	%ebp,%edx
	movb	%dh,%ch

	movb	0x12345678(%ebx),%al
LBPatch30:
	movl	_sourcetstep,%edx

	movb	%al,1(%edi)
	movb	0x12345678(%ecx),%al
LBPatch31:

	movb	%al,(%edi)
	movl	_surfrowbytes,%ebp

	addl	%edx,%esi
	addl	%ebp,%edi

//			if (pbasesource >= r_sourcemax)
//				pbasesource -= stepback;

	cmpl	_r_sourcemax,%esi
	jb		LSkip_mip3
	subl	_r_stepback,%esi
LSkip_mip3:

	movl	_r_lightptr,%ebx
	decl	sb_v

	jnz		Lv_loop_mip3

	popl	%ebx				// restore register variables
	popl	%esi
	popl	%edi
	popl	%ebp				// restore the caller's stack frame
	ret


.globl _R_Surf8End
_R_Surf8End:

//----------------------------------------------------------------------
// Code patching routines
//----------------------------------------------------------------------
	.data

	.align 4
LPatchTable8:
	.long	LBPatch0-4
	.long	LBPatch1-4
	.long	LBPatch2-4
	.long	LBPatch3-4
	.long	LBPatch4-4
	.long	LBPatch5-4
	.long	LBPatch6-4
	.long	LBPatch7-4
	.long	LBPatch8-4
	.long	LBPatch9-4
	.long	LBPatch10-4
	.long	LBPatch11-4
	.long	LBPatch12-4
	.long	LBPatch13-4
	.long	LBPatch14-4
	.long	LBPatch15-4
	.long	LBPatch16-4
	.long	LBPatch17-4
	.long	LBPatch18-4
	.long	LBPatch19-4
	.long	LBPatch20-4
	.long	LBPatch21-4
	.long	LBPatch22-4
	.long	LBPatch23-4
	.long	LBPatch24-4
	.long	LBPatch25-4
	.long	LBPatch26-4
	.long	LBPatch27-4
	.long	LBPatch28-4
	.long	LBPatch29-4
	.long	LBPatch30-4
	.long	LBPatch31-4

	.text

	.align 4
.globl _R_Surf8Patch
_R_Surf8Patch:
	pushl	%ebx

	movl	_colormap,%eax
	movl	$LPatchTable8,%ebx
	movl	$32,%ecx
LPatchLoop8:
	movl	(%ebx),%edx
	addl	$4,%ebx
	movl	%eax,(%edx)
	decl	%ecx
	jnz		LPatchLoop8

	popl	%ebx

	ret

#endif	// id386
