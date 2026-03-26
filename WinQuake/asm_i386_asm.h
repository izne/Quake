//
// asm_i386_asm.h - Assembly-only header (NO preprocessor directives)
//

// plane_t structure
.equ pl_normal,0
.equ pl_dist,12
.equ pl_type,16
.equ pl_signbits,17
.equ pl_pad,18
.equ pl_size,20

// hull_t structure
.equ hu_clipnodes,0
.equ hu_planes,4
.equ hu_firstclipnode,8
.equ hu_lastclipnode,12
.equ hu_clip_mins,16
.equ hu_clip_maxs,28
.equ hu_size,40

// dnode_t structure
.equ nd_planenum,0
.equ nd_children,4
.equ nd_mins,8
.equ nd_maxs,20
.equ nd_firstface,32
.equ nd_numfaces,36
.equ nd_size,40

// sfxcache_t structure
.equ sfxc_length,0
.equ sfxc_loopstart,4
.equ sfxc_speed,8
.equ sfxc_width,12
.equ sfxc_stereo,16
.equ sfxc_data,20

// channel_t structure
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
.equ psp_left,0
.equ psp_right,4
.equ psp_size,8
