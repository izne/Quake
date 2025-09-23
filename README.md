#  Quake 1 fast inverse square root retro-fit
### Implementation of the legendary fast inverse square root optimization across all the critical performance hotspots in Quake 1


## Overview
Lets have the famous q_rsqrt() from Quake 3 that has been first used in 1999 and put it into the 1996 source code of Quake 1

## Why?
To get more FPS on 486-class machines


- - - 

### Optimizations sqrt() to q_rsqrt():
- Core math functions (mathlib.c)
- Entity physics (sv_phys.c)
- Player movement (sv_user.c)
- View effects (view.c)
- Game logic (pr_cmds.c)