/*
Copyright (C) 1996-1997 Id Software, Inc.

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
// d_parta.s
// x86 assembly-language 8-bpp particle-drawing code.
//

#include "../asm_i386.h"
#include "../quakeasm.h"
#include "../d_ifacea.h"
#include "../asm_draw.h"

#if	id386

//----------------------------------------------------------------------
// 8-bpp particle drawing code.
//----------------------------------------------------------------------

//FIXME: comments, full optimization

//----------------------------------------------------------------------
// 8-bpp particle queueing code.
//----------------------------------------------------------------------

	.text

.align 4
// for terje's Fp->Int optimization
.MAGIC:
        .long   0x59800004  

#define P	12+4

	.align 4
.globl C(D_DrawParticle)
C(D_DrawParticle):
	pushl	%ebp				// preserve caller's stack frame
	pushl	%edi				// preserve register variables
	pushl	%ebx

	movl	P(%esp),%edi

// FIXME: better FP overlap in general here

// transform point
//	VectorSubtract (p->org, r_origin, local);
	flds	pt_org+8(%edi)
	fsubs	C(r_origin)+8
	flds	pt_org+4(%edi)
	fsubs	C(r_origin)+4
	flds	C(r_origin)
	fsubrs	pt_org(%edi) // local[0] | local[1] | local[2]		

//	transformed[2] = DotProduct(local, r_ppn);		
	flds	C(r_ppn)		// r_ppn[0] | local[0] | local[1] | local[2]
	fmul	%st(1),%st(0)	// dot0 | local[0] | local[1] | local[2]
	flds	C(r_ppn)+4	// r_ppn[1] | dot0 | local[0] | local[1] | local[2]
	fmul	%st(3),%st(0)	// dot1 | dot0 | local[0] | local[1] | local[2]
	flds	C(r_ppn)+8	// r_ppn[2] | dot1 | dot0 | local[0] |
						//  local[1] | local[2]
	fmul	%st(5),%st(0)	// dot2 | dot1 | dot0 | local[0] | local[1] | local[2]
	faddp	%st(0),%st(1) // dot2 + dot1 | dot0 | local[0] | local[1] |
						  //  local[2]
	faddp	%st(0),%st(1) // z | local[0] | local[1] | local[2]
	fld		%st(0)		// z | z | local[0] | local[1] | local[2]

//	if (transformed[2] < PARTICLE_Z_CLIP)
//		return;
	fcomps	float_particle_z_clip		// z | local[0] | local[1] | local[2]
	fnstsw	%ax
	fdivrs	float_1						// 1/z | local[0] | local[1] | local[2]
	testb	$1,%ah
	jnz		LPop4AndDone

	fxch	%st(3)						// local[2] | local[0] | local[1] | 1/z

//	transformed[1] = DotProduct(local, r_pup);
	flds	C(r_pup)					// r_pup[0] | local[2] | local[0] | local[1] | 1/z
	fmul	%st(2),%st(0)				// dot0 | local[2] | local[0] | local[1] | 1/z 
	flds	C(r_pup)+4					// r_pup[1] | dot0 | local[2] | local[0] | local[1] | 1/z 
	fmul	%st(4),%st(0)	// dot1 | dot0 | local[2] | local[0] | local[1] | 1/z 
	flds	C(r_pup)+8	// r_pup[2] | dot1 | dot0 | local[2] | local[0] | local[1] | 1/z 
	fmul	%st(3),%st(0)	// dot2 | dot1 | dot0 | local[2] | local[0] | local[1] | 1/z 
	faddp	%st(0),%st(1) // dot2 + dot1 | dot0 | local[2] | local[0] | local[1] | 1/z 
	faddp	%st(0),%st(1) // y | local[2] | local[0] | local[1] | 1/z 

// project and store y
	fmul	%st(4),%st(0)	// y/z | local[2] | local[0] | local[1] | 1/z 
	fsubrs	C(ycenter)		// v | local[2] | local[0] | local[1] | 1/z 
	fadds	float_point5	// v.5 | local[2] | local[0] | local[1] | 1/z 
	fistpl	DP_v			// local[2] | local[0] | local[1] | 1/z 

//	transformed[0] = DotProduct(local, r_pright);

	fmuls	C(r_pright)+8			// dot2 | local[0] | local[1] | 1/z

//  have the cpu load v while fpu does the fmul 
	movl	DP_v,%edx

	fxch	%st(2)					// local[1] | local[0] | dot2 | 1/z
	fmuls	C(r_pright)+4			// dot1 | local[0] | dot2 | 1/z
	fxch	%st(1)					// local[0] | dot1 | dot2 | 1/z
	fmuls	C(r_pright)				// dot0 | dot1 | dot2 | 1/z
	faddp	%st(0),%st(1) 			// dot0 + dot1 | dot2 | 1/z
	faddp	%st(0),%st(1)			// x | 1/z

// project and store the point
	fmul	%st(1),%st(0)	// x/z | 1/z
	fadds	C(xcenter)		// u | 1/z
	fadds	float_point5	// u.5 | 1/z
	fistpl	DP_u			// 1/z :: 28-34 cycles

	fmuls	DP_32768		// 1/z * 0x8000

//  have the cpu load u while fpu does the fmul 
	movl	DP_u,%eax

// if ((v > d_vrectbottom_particle) || 
// 	(u > d_vrectright_particle) ||
// 	(v < d_vrecty) ||
// 	(u < d_vrectx))
// {
// 	continue;
// }

	movl	C(d_vrectbottom_particle),%ebx
	movl	C(d_vrectright_particle),%ecx
	cmpl	%ebx,%edx
	jg		LPop1AndDone
	cmpl	%ecx,%eax
	jg		LPop1AndDone
	movl	C(d_vrecty),%ebx
	movl	C(d_vrectx),%ecx
	cmpl	%ebx,%edx
	jl		LPop1AndDone

	cmpl	%ecx,%eax
	jl		LPop1AndDone

	flds	pt_color(%edi)	// color | 1/z * 0x8000
	fistpl	DP_Color		// 1/z * 0x8000
	
	movl	C(d_viewbuffer),%ebx

	addl	%eax,%ebx
	movl	C(d_scantable)(,%edx,4),%edi		// point to the pixel

	imull	C(d_zrowbytes),%edx		// point to the z pixel

	leal	(%edx,%eax,2),%edx
	movl	C(d_pzbuffer),%eax

	fistpl	izi

	addl	%ebx,%edi
	addl	%eax,%edx

// pix = izi >> d_pix_shift;

	movl	izi,%eax
	movl	C(d_pix_shift),%ecx
	shrl	%cl,%eax
	movl	izi,%ebp

// if (pix < d_pix_min)
// 		pix = d_pix_min;
// else if (pix > d_pix_max)
//  	pix = d_pix_max;

	movl	C(d_pix_min),%ebx
	movl	C(d_pix_max),%ecx
	cmpl	%ebx,%eax
	jnl		LTestPixMax
	movl	%ebx,%eax
	jmp		LTestDone

LTestPixMax:
	cmpl	%ecx,%eax
	jng		LTestDone
	movl	%ecx,%eax
LTestDone:

	movb	DP_Color,%ch

	movl	C(d_y_aspect_shift),%ebx
	testl	%ebx,%ebx
	jnz		LDefault

	cmpl	$4,%eax
	ja		LDefault

	jmp		DP_EntryTable-4(,%eax,4)

// 1x1
.globl	DP_1x1
DP_1x1:
	cmpw	%bp,(%edx)		// just one pixel to do
	jg		LDone
	movw	%bp,(%edx)
	movb	%ch,(%edi)
	jmp		LDone

// 2x2
.globl	DP_2x2
DP_2x2:
	pushl	%esi
	movl	C(screenwidth),%ebx
	movl	C(d_zrowbytes),%esi

	cmpw	%bp,(%edx)
	jg		L2x2_1
	movw	%bp,(%edx)
	movb	%ch,(%edi)
L2x2_1:
	cmpw	%bp,2(%edx)
	jg		L2x2_2
	movw	%bp,2(%edx)
	movb	%ch,1(%edi)
L2x2_2:
	cmpw	%bp,(%edx,%esi,1)
	jg		L2x2_3
	movw	%bp,(%edx,%esi,1)
	movb	%ch,(%edi,%ebx,1)
L2x2_3:
	cmpw	%bp,2(%edx,%esi,1)
	jg		L2x2_4
	movw	%bp,2(%edx,%esi,1)
	movb	%ch,1(%edi,%ebx,1)
L2x2_4:

	popl	%esi
	jmp		LDone

// 3x3
.globl	DP_3x3
DP_3x3:
	pushl	%esi
	movl	C(screenwidth),%ebx
	movl	C(d_zrowbytes),%esi

	cmpw	%bp,(%edx)
	jg		L3x3_1
	movw	%bp,(%edx)
	movb	%ch,(%edi)
L3x3_1:
	cmpw	%bp,2(%edx)
	jg		L3x3_2
	movw	%bp,2(%edx)
	movb	%ch,1(%edi)
L3x3_2:
	cmpw	%bp,4(%edx)
	jg		L3x3_3
	movw	%bp,4(%edx)
	movb	%ch,2(%edi)
L3x3_3:

	cmpw	%bp,(%edx,%esi,1)
	jg		L3x3_4
	movw	%bp,(%edx,%esi,1)
	movb	%ch,(%edi,%ebx,1)
L3x3_4:
	cmpw	%bp,2(%edx,%esi,1)
	jg		L3x3_5
	movw	%bp,2(%edx,%esi,1)
	movb	%ch,1(%edi,%ebx,1)
L3x3_5:
	cmpw	%bp,4(%edx,%esi,1)
	jg		L3x3_6
	movw	%bp,4(%edx,%esi,1)
	movb	%ch,2(%edi,%ebx,1)
L3x3_6:

	cmpw	%bp,(%edx,%esi,2)
	jg		L3x3_7
	movw	%bp,(%edx,%esi,2)
	movb	%ch,(%edi,%ebx,2)
L3x3_7:
	cmpw	%bp,2(%edx,%esi,2)
	jg		L3x3_8
	movw	%bp,2(%edx,%esi,2)
	movb	%ch,1(%edi,%ebx,2)
L3x3_8:
	cmpw	%bp,4(%edx,%esi,2)
	jg		L3x3_9
	movw	%bp,4(%edx,%esi,2)
	movb	%ch,2(%edi,%ebx,2)
L3x3_9:

	popl	%esi
	jmp		LDone


// 4x4
.globl	DP_4x4
DP_4x4:
	pushl	%esi
	movl	C(screenwidth),%ebx
	movl	C(d_zrowbytes),%esi

	cmpw	%bp,(%edx)
	jg		L4x4_1
	movw	%bp,(%edx)
	movb	%ch,(%edi)
L4x4_1:
	cmpw	%bp,2(%edx)
	jg		L4x4_2
	movw	%bp,2(%edx)
	movb	%ch,1(%edi)
L4x4_2:
	cmpw	%bp,4(%edx)
	jg		L4x4_3
	movw	%bp,4(%edx)
	movb	%ch,2(%edi)
L4x4_3:
	cmpw	%bp,6(%edx)
	jg		L4x4_4
	movw	%bp,6(%edx)
	movb	%ch,3(%edi)
L4x4_4:

	cmpw	%bp,(%edx,%esi,1)
	jg		L4x4_5
	movw	%bp,(%edx,%esi,1)
	movb	%ch,(%edi,%ebx,1)
L4x4_5:
	cmpw	%bp,2(%edx,%esi,1)
	jg		L4x4_6
	movw	%bp,2(%edx,%esi,1)
	movb	%ch,1(%edi,%ebx,1)
L4x4_6:
	cmpw	%bp,4(%edx,%esi,1)
	jg		L4x4_7
	movw	%bp,4(%edx,%esi,1)
	movb	%ch,2(%edi,%ebx,1)
L4x4_7:
	cmpw	%bp,6(%edx,%esi,1)
	jg		L4x4_8
	movw	%bp,6(%edx,%esi,1)
	movb	%ch,3(%edi,%ebx,1)
L4x4_8:

	leal	(%edx,%esi,2),%edx
	leal	(%edi,%ebx,2),%edi

	cmpw	%bp,(%edx)
	jg		L4x4_9
	movw	%bp,(%edx)
	movb	%ch,(%edi)
L4x4_9:
	cmpw	%bp,2(%edx)
	jg		L4x4_10
	movw	%bp,2(%edx)
	movb	%ch,1(%edi)
L4x4_10:
	cmpw	%bp,4(%edx)
	jg		L4x4_11
	movw	%bp,4(%edx)
	movb	%ch,2(%edi)
L4x4_11:
	cmpw	%bp,6(%edx)
	jg		L4x4_12
	movw	%bp,6(%edx)
	movb	%ch,3(%edi)
L4x4_12:

	cmpw	%bp,(%edx,%esi,1)
	jg		L4x4_13
	movw	%bp,(%edx,%esi,1)
	movb	%ch,(%edi,%ebx,1)
L4x4_13:
	cmpw	%bp,2(%edx,%esi,1)
	jg		L4x4_14
	movw	%bp,2(%edx,%esi,1)
	movb	%ch,1(%edi,%ebx,1)
L4x4_14:
	cmpw	%bp,4(%edx,%esi,1)
	jg		L4x4_15
	movw	%bp,4(%edx,%esi,1)
	movb	%ch,2(%edi,%ebx,1)
L4x4_15:
	cmpw	%bp,6(%edx,%esi,1)
	jg		L4x4_16
	movw	%bp,6(%edx,%esi,1)
	movb	%ch,3(%edi,%ebx,1)
L4x4_16:

	popl	%esi
	jmp		LDone

// default case, handling any size particle
LDefault:

// count = pix << d_y_aspect_shift;

	movl	%eax,%ebx
	movl	%eax,DP_Pix
	movb	C(d_y_aspect_shift),%cl
	shll	%cl,%ebx

// for ( ; count ; count--, pz += d_zwidth, pdest += screenwidth)
// {
// 	for (i=0 ; i<pix ; i++)
// 	{
// 		if (pz[i] <= izi)
// 		{
// 			pz[i] = izi;
// 			pdest[i] = color;
// 		}
// 	}
// }

LGenRowLoop:
	movl	DP_Pix,%eax

LGenColLoop:
	cmpw	%bp,-2(%edx,%eax,2)
	jg		LGSkip
	movw	%bp,-2(%edx,%eax,2)
	movb	%ch,-1(%edi,%eax,1)
LGSkip:
	decl	%eax			// --pix
	jnz		LGenColLoop

	addl	C(d_zrowbytes),%edx
	addl	C(screenwidth),%edi

	decl	%ebx			// --count
	jnz		LGenRowLoop

LDone:
	popl	%ebx				// restore register variables
	popl	%edi
	popl	%ebp				// restore the caller's stack frame
	ret

LPop6AndDone:
	fstp	%st(0)
	fstp	%st(0)
LPop4AndDone:
	fstp	%st(0)
	fstp	%st(0)
	fstp	%st(0)
LPop1AndDone:
	fstp	%st(0)
	jmp		LDone

#endif	// id386
