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
// !!! note that this file must match the corresponding C structures at all
// times !!!
//

// C macro for assembly - prefix with underscore for DOS
#define C(label) _##label

// plane_t structure
// !!! if this is changed, it must be changed in model.h too !!!
// !!! if the size of this is changed, the array lookup in SV_HullPointContents
//     must be changed too !!!
.equ pl_normal,0
.equ pl_dist,12
.equ pl_type,16
.equ pl_signbits,17
.equ pl_pad,18
.equ pl_size,20

// hull_t structure
// !!! if this is changed, it must be changed in model.h too !!!
.equ hu_clipnodes,0
.equ hu_planes,4
.equ hu_firstclipnode,8
.equ hu_lastclipnode,12
.equ hu_clip_mins,16
.equ hu_clip_maxs,28
.equ hu_size,40

// dnode_t structure
// !!! if this is changed, it must be changed in bspfile.h too !!!
.equ nd_planenum,0
.equ nd_children,4
.equ nd_mins,8
.equ nd_maxs,20
.equ nd_firstface,32
.equ nd_numfaces,36
.equ nd_size,40

// sfxcache_t structure
// !!! if this is changed, it much be changed in sound.h too !!!
.equ sfxc_length,0
.equ sfxc_loopstart,4
.equ sfxc_speed,8
.equ sfxc_width,12
.equ sfxc_stereo,16
.equ sfxc_data,20

// channel_t structure
// !!! if this is changed, it much be changed in sound.h too !!!
.equ ch_sfx,0
.equ ch_leftvol,4
.equ ch_rightvol,8
.equ ch_end,12
.equ ch_pos,16
.equ ch_looping,20
.equ ch_entnum,24
.equ ch_entchannel,28
.equ ch_origin,32
.equ ch_dist_mult,44
.equ ch_master_vol,48
.equ ch_size,52

// portable_samplepair_t structure
// !!! if this is changed, it much be changed in sound.h too !!!
.equ psp_left,0
.equ psp_right,4
.equ psp_size,8

