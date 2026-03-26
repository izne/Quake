//

//

#include "asm_i386_asm.h"
#include "quakeasm.h"
#include "asm_draw.h"

	.data

LCopyWidth:		.long	0
LBlockSrcStep:	.long	0
LBlockDestStep:	.long	0
LSrcDelta:		.long	0
LDestDelta:		.long	0

#define bufptr	4+16

// copies 16 rows per plane at a pop; idea is that 16*512 = 8k, and since
// no Mode X mode is wider than 360, all the data should fit in the cache for
// the passes for the next 3 planes

	.text

.globl _VGA_UpdatePlanarScreen
_VGA_UpdatePlanarScreen:
	pushl	%ebp				// preserve caller's stack frame
	pushl	%edi
	pushl	%esi				// preserve register variables
	pushl	%ebx

	movl	_VGA_bufferrowbytes,%eax
	shll	$1,%eax
	movl	%eax,LBlockSrcStep
	movl	_VGA_rowbytes,%eax
	shll	$1,%eax
	movl	%eax,LBlockDestStep

	movl	$0x3C4,%edx
	movb	$2,%al
	outb	%al,%dx		// point the SC to the Map Mask
	incl	%edx

	movl	bufptr(%esp),%esi
	movl	_VGA_pagebase,%edi
	movl	_VGA_height,%ebp
	shrl	$1,%ebp

	movl	_VGA_width,%ecx
	movl	_VGA_bufferrowbytes,%eax
	subl	%ecx,%eax
	movl	%eax,LSrcDelta
	movl	_VGA_rowbytes,%eax
	shll	$2,%eax
	subl	%ecx,%eax
	movl	%eax,LDestDelta
	shrl	$4,%ecx
	movl	%ecx,LCopyWidth

LRowLoop:
	movb	$1,%al

LPlaneLoop:
	outb	%al,%dx
	movb	$2,%ah

	pushl	%esi
	pushl	%edi
LRowSetLoop:
	movl	LCopyWidth,%ecx
LColumnLoop:
	movb	12(%esi),%bh
	movb	8(%esi),%bl
	shll	$16,%ebx
	movb	4(%esi),%bh
	movb	(%esi),%bl
	movl	%ebx,(%edi)
	addl	$16,%esi
	addl	$4,%edi
	decl	%ecx
	jnz		LColumnLoop

	addl	LDestDelta,%edi
	addl	LSrcDelta,%esi
	decb	%ah
	jnz		LRowSetLoop

	popl	%edi
	popl	%esi
	incl	%esi

	shlb	$1,%al
	cmpb	$16,%al
	jnz		LPlaneLoop

	subl	$4,%esi
	addl	LBlockSrcStep,%esi
	addl	LBlockDestStep,%edi
	decl	%ebp
	jnz		LRowLoop

	popl	%ebx				// restore register variables
	popl	%esi
	popl	%edi
	popl	%ebp				// restore the caller's stack frame

	ret


#define srcptr			4+16
#define destptr			8+16
#define width			12+16
#define height			16+16
#define srcrowbytes		20+16
#define destrowbytes	24+16

.globl _VGA_UpdateLinearScreen
_VGA_UpdateLinearScreen:
	pushl	%ebp				// preserve caller's stack frame
	pushl	%edi
	pushl	%esi				// preserve register variables
	pushl	%ebx

	cld
	movl	srcptr(%esp),%esi
	movl	destptr(%esp),%edi
	movl	width(%esp),%ebx
	movl	srcrowbytes(%esp),%eax
	subl	%ebx,%eax
	movl	destrowbytes(%esp),%edx
	subl	%ebx,%edx
	shrl	$2,%ebx
	movl	height(%esp),%ebp
LLRowLoop:
	movl	%ebx,%ecx
	rep/movsl	(%esi),(%edi)
	addl	%eax,%esi
	addl	%edx,%edi
	decl	%ebp
	jnz		LLRowLoop

	popl	%ebx				// restore register variables
	popl	%esi
	popl	%edi
	popl	%ebp				// restore the caller's stack frame

	ret

