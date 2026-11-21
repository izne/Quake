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
// r_edge.c

#include "quakedef.h"
#include "r_local.h"
#include "qtrace.h"

#if 0
// FIXME
the complex cases add new polys on most lines, so dont optimize for keeping them the same
have multiple free span lists to try to get better coherence?
low depth complexity -- 1 to 3 or so

this breaks spans at every edge, even hidden ones (bad)

have a sentinal at both ends?
#endif


edge_t	*auxedges;
edge_t	*r_edges, *edge_p, *edge_max;

surf_t	*surfaces, *surface_p, *surf_max;

// surfaces are generated in back to front order by the bsp, so if a surf
// pointer is greater than another one, it should be drawn in front
// surfaces[1] is the background, and is used as the active surface stack

edge_t	*newedges[MAXHEIGHT];
edge_t	*removeedges[MAXHEIGHT];

espan_t	*span_p, *max_span_p;

int		r_currentkey;

extern	int	screenwidth;

int	current_iv;

int	edge_head_u_shift20, edge_tail_u_shift20;

static void (*pdrawfunc)(void);

edge_t	edge_head;
edge_t	edge_tail;
edge_t	edge_aftertail;
edge_t	edge_sentinel;

float	fv;

void R_GenerateSpans (void);
void R_GenerateSpansBackward (void);

#ifdef QTRACE_ENABLE
static void R_StepActiveU_Trace (edge_t *pedge);
static void R_TraceNewEdges (int iv, edge_t *edge);
static int qtrace_step_debug;
static int qtrace_insert_debug;
#endif

#ifdef QTRACE_ENABLE
#define QTRACE_SCAN(tag, iv) do { \
	if ((iv) >= 128 && (iv) < 224) \
		QTRACE (tag, iv); \
	else \
		QTRACE_RATE (tag, iv, 32); \
} while (0)
#else
#define QTRACE_SCAN(tag, iv) ((void)0)
#endif

#ifdef QTRACE_ENABLE
static void R_TraceNewEdges (int iv, edge_t *edge)
{
	int		i;

	QTRACE (QT_INS_INFO, (int)edge);
	QTRACE (QT_INS_IV, iv);
	QTRACE (QT_INS_PTR, (int)edge_head.next);
	QTRACE (QT_INS_PTR, (int)&edge_tail);

	for (i=0 ; edge && i<64 ; i++, edge=edge->next)
	{
		QTRACE (QT_INS_PTR, (int)edge);
		QTRACE (QT_INS_U, edge->u);
		QTRACE (QT_INS_STEP, edge->u_step);
		QTRACE (QT_INS_NEXT, (int)edge->next);
		QTRACE (QT_INS_NEXTREMOVE, (int)edge->nextremove);
		QTRACE (QT_INS_OWNER, (int)edge->owner);
	}

	if (edge)
		QTRACE (QT_INS_CIRCULAR, (int)edge);
}

enum
{
	QEB_STEP_PEDGE = 1,
	QEB_STEP_PREV,
	QEB_STEP_NEXT,
	QEB_STEP_WEDGE,
	QEB_NEWEDGE,
	QEB_NEWEDGE_ORDER,
	QEB_REMOVEEDGE,
	QEB_ACTIVE_AFTER_INSERT,
	QEB_ACTIVE_AFTER_REMOVE,
	QEB_ACTIVE_BEFORE_STEP
};

static int QTraceValidEdgePtr (edge_t *e)
{
	if (e == &edge_head || e == &edge_tail ||
		e == &edge_aftertail || e == &edge_sentinel)
		return 1;

	if (r_edges == NULL || edge_max == NULL)
		return 0;

	if ((unsigned long)e >= (unsigned long)r_edges &&
		(unsigned long)e <  (unsigned long)edge_max &&
		(((unsigned long)e - (unsigned long)r_edges) % sizeof(edge_t)) == 0)
		return 1;

	return 0;
}

static void QTraceBadEdge (int where, edge_t *e)
{
	QTRACE (QT_EDGE_BAD_WHERE, where);
	QTRACE (QT_EDGE_BAD_PTR, (int)e);
	QTRACE (QT_EDGE_BAD_FRAME, r_framecount);
}

static void QTraceCheckNewEdges (int iv, edge_t *edge)
{
	edge_t	*prev = NULL;

	for ( ; edge ; edge = edge->next)
	{
		if (!QTraceValidEdgePtr (edge))
		{
			QTraceBadEdge (QEB_NEWEDGE, edge);
			QTRACE (QT_EDGE_BAD_IV, iv);
			return;
		}
		if (prev != NULL && prev->u > edge->u)
		{
			QTraceBadEdge (QEB_NEWEDGE_ORDER, edge);
			QTRACE (QT_EDGE_BAD_AUX, prev->u);
			QTRACE (QT_EDGE_BAD_IV, iv);
			return;
		}
		prev = edge;
	}
}

static void QTraceCheckRemoveEdges (int iv, edge_t *edge)
{
	for ( ; edge ; edge = edge->nextremove)
	{
		if (!QTraceValidEdgePtr (edge))
		{
			QTraceBadEdge (QEB_REMOVEEDGE, edge);
			QTRACE (QT_EDGE_BAD_IV, iv);
			return;
		}
	}
}

static void QTraceCheckActiveList (int where)
{
	edge_t	*e = edge_head.next;
	edge_t	*prev = &edge_head;
	int		guard = 0;

	while (e != &edge_tail)
	{
		if (++guard > 10000)
		{
			QTRACE (QT_EDGE_BAD_AUX, guard);
			QTraceBadEdge (where, e);
			return;
		}
		if (!QTraceValidEdgePtr (e))
		{
			QTraceBadEdge (where, e);
			return;
		}
		if (e->prev != prev)
		{
			QTRACE (QT_EDGE_BAD_AUX, (int)e->prev);
			QTraceBadEdge (where, e);
			return;
		}
		if (!QTraceValidEdgePtr (e->next))
		{
			QTraceBadEdge (where, e->next);
			return;
		}
		prev = e;
		e = e->next;
	}
}

#define QTRACE_STEP_CHECK(e,w) do { \
	if (!QTraceValidEdgePtr (e)) \
	{ \
		QTraceBadEdge ((w), (e)); \
		return; \
	} \
} while (0)
#endif

void R_LeadingEdge (edge_t *edge);
void R_LeadingEdgeBackwards (edge_t *edge);
void R_TrailingEdge (surf_t *surf, edge_t *edge);


//=============================================================================


/*
==============
R_DrawCulledPolys
==============
*/
void R_DrawCulledPolys (void)
{
	surf_t			*s;
	msurface_t		*pface;

	currententity = &cl_entities[0];

	if (r_worldpolysbacktofront)
	{
		for (s=surface_p-1 ; s>&surfaces[1] ; s--)
		{
			if (!s->spans)
				continue;

			if (!(s->flags & SURF_DRAWBACKGROUND))
			{
				pface = (msurface_t *)s->data;
				R_RenderPoly (pface, 15);
			}
		}
	}
	else
	{
		for (s = &surfaces[1] ; s<surface_p ; s++)
		{
			if (!s->spans)
				continue;

			if (!(s->flags & SURF_DRAWBACKGROUND))
			{
				pface = (msurface_t *)s->data;
				R_RenderPoly (pface, 15);
			}
		}
	}
}


/*
==============
R_BeginEdgeFrame
==============
*/
void R_BeginEdgeFrame (void)
{
	int		v;

	edge_p = r_edges;
	edge_max = &r_edges[r_numallocatededges];

	surface_p = &surfaces[2];	// background is surface 1,
								//  surface 0 is a dummy
	surfaces[1].spans = NULL;	// no background spans yet
	surfaces[1].flags = SURF_DRAWBACKGROUND;

// put the background behind everything in the world
	if (r_draworder.value)
	{
		pdrawfunc = R_GenerateSpansBackward;
		surfaces[1].key = 0;
		r_currentkey = 1;
	}
	else
	{
		pdrawfunc = R_GenerateSpans;
		surfaces[1].key = 0x7FFFFFFF;
		r_currentkey = 0;
	}

// FIXME: set with memset
	for (v=r_refdef.vrect.y ; v<r_refdef.vrectbottom ; v++)
	{
		newedges[v] = removeedges[v] = NULL;
	}
}


#if	!id386

/*
==============
R_InsertNewEdges

Adds the edges in the linked list edgestoadd, adding them to the edges in the
linked list edgelist.  edgestoadd is assumed to be sorted on u, and non-empty (this is actually newedges[v]).  edgelist is assumed to be sorted on u, with a
sentinel at the end (actually, this is the active edge table starting at
edge_head.next).
==============
*/
void R_InsertNewEdges (edge_t *edgestoadd, edge_t *edgelist)
{
	edge_t	*next_edge;

	do
	{
		next_edge = edgestoadd->next;
edgesearch:
		if (edgelist->u >= edgestoadd->u)
			goto addedge;
		edgelist=edgelist->next;
		if (edgelist->u >= edgestoadd->u)
			goto addedge;
		edgelist=edgelist->next;
		if (edgelist->u >= edgestoadd->u)
			goto addedge;
		edgelist=edgelist->next;
		if (edgelist->u >= edgestoadd->u)
			goto addedge;
		edgelist=edgelist->next;
		goto edgesearch;

	// insert edgestoadd before edgelist
addedge:
		edgestoadd->next = edgelist;
		edgestoadd->prev = edgelist->prev;
		edgelist->prev->next = edgestoadd;
		edgelist->prev = edgestoadd;
	} while ((edgestoadd = next_edge) != NULL);
}

#endif	// !id386
	

#if	!id386

/*
==============
R_RemoveEdges
==============
*/
void R_RemoveEdges (edge_t *pedge)
{

	do
	{
		pedge->next->prev = pedge->prev;
		pedge->prev->next = pedge->next;
	} while ((pedge = pedge->nextremove) != NULL);
}

#endif	// !id386


#if	!id386

/*
==============
R_StepActiveU
==============
*/
void R_StepActiveU (edge_t *pedge)
{
	edge_t		*pnext_edge, *pwedge;

	while (1)
	{
nextedge:
		pedge->u += pedge->u_step;
		if (pedge->u < pedge->prev->u)
			goto pushback;
		pedge = pedge->next;
			
		pedge->u += pedge->u_step;
		if (pedge->u < pedge->prev->u)
			goto pushback;
		pedge = pedge->next;
			
		pedge->u += pedge->u_step;
		if (pedge->u < pedge->prev->u)
			goto pushback;
		pedge = pedge->next;
			
		pedge->u += pedge->u_step;
		if (pedge->u < pedge->prev->u)
			goto pushback;
		pedge = pedge->next;
			
		goto nextedge;		
		
pushback:
		if (pedge == &edge_aftertail)
			return;
			
	// push it back to keep it sorted		
		pnext_edge = pedge->next;

	// pull the edge out of the edge list
		pedge->next->prev = pedge->prev;
		pedge->prev->next = pedge->next;

	// find out where the edge goes in the edge list
		pwedge = pedge->prev->prev;

		while (pwedge->u > pedge->u)
		{
			pwedge = pwedge->prev;
		}

	// put the edge back into the edge list
		pedge->next = pwedge->next;
		pedge->prev = pwedge;
		pedge->next->prev = pedge;
		pwedge->next = pedge;

		pedge = pnext_edge;
		if (pedge == &edge_tail)
			return;
	}
}

#endif	// !id386

#ifdef QTRACE_ENABLE
static void R_StepActiveU_Trace (edge_t *pedge)
{
	edge_t		*pnext_edge, *pwedge;
	int			outer_guard = 0;
	int			pushback_guard;

	QTRACE (QT_STEP_TRACE_ENTER, (int)pedge);
	if (qtrace_step_debug)
		QTRACE (QT_STEP_CP_ENTER_DONE, (int)pedge);

	while (1)
	{
trace_nextedge:
		QTRACE_STEP_CHECK (pedge, QEB_STEP_PEDGE);
		QTRACE_STEP_CHECK (pedge->prev, QEB_STEP_PREV);
		QTRACE_STEP_CHECK (pedge->next, QEB_STEP_NEXT);

		if (++outer_guard > 10000)
		{
			QTRACE (QT_STEP_RUNAWAY_OUTER, (int)pedge);
			QTRACE (QT_STEP_BAD_EDGE_U, pedge->u);
			QTRACE (QT_STEP_BAD_STEP, pedge->u_step);
			QTRACE (QT_STEP_BAD_PREV_U, pedge->prev->u);
			QTRACE (QT_STEP_BAD_PREV_PTR, (int)pedge->prev);
			QTRACE (QT_STEP_BAD_WEDGE_PTR, (int)pedge->next);
			return;
		}
		if (qtrace_step_debug)
			QTRACE (QT_STEP_CP_OUTER, outer_guard);

		pedge->u += pedge->u_step;
		if (pedge->u < pedge->prev->u)
			goto trace_pushback;
		pedge = pedge->next;

		pedge->u += pedge->u_step;
		if (pedge->u < pedge->prev->u)
			goto trace_pushback;
		pedge = pedge->next;

		pedge->u += pedge->u_step;
		if (pedge->u < pedge->prev->u)
			goto trace_pushback;
		pedge = pedge->next;

		pedge->u += pedge->u_step;
		if (pedge->u < pedge->prev->u)
			goto trace_pushback;
		pedge = pedge->next;

		goto trace_nextedge;

trace_pushback:
		if (pedge == &edge_aftertail)
		{
			QTRACE (QT_STEP_TRACE_EXIT, (int)pedge);
			return;
		}

		QTRACE_STEP_CHECK (pedge, QEB_STEP_PEDGE);
		QTRACE_STEP_CHECK (pedge->prev, QEB_STEP_PREV);
		QTRACE_STEP_CHECK (pedge->next, QEB_STEP_NEXT);

		if (qtrace_step_debug)
			QTRACE (QT_STEP_CP_PUSHBACK, (int)pedge);

	// push it back to keep it sorted
		pnext_edge = pedge->next;

	// pull the edge out of the edge list
		pedge->next->prev = pedge->prev;
		pedge->prev->next = pedge->next;

	// find out where the edge goes in the edge list
		pwedge = pedge->prev->prev;
		QTRACE_STEP_CHECK (pwedge, QEB_STEP_WEDGE);

		if (qtrace_step_debug)
			QTRACE (QT_STEP_CP_PULLED, (int)pedge);

		pushback_guard = 0;
		while (pwedge->u > pedge->u)
		{
			QTRACE_STEP_CHECK (pwedge->prev, QEB_STEP_WEDGE);
			pwedge = pwedge->prev;
			if (qtrace_step_debug)
				QTRACE (QT_STEP_CP_PB_LOOP, pushback_guard);
			if (++pushback_guard > 100000)
			{
				QTRACE (QT_STEP_RUNAWAY_PUSHBACK, (int)pedge);
				QTRACE (QT_STEP_BAD_EDGE_U, pedge->u);
				QTRACE (QT_STEP_BAD_PREV_U, pedge->prev->u);
				QTRACE (QT_STEP_BAD_HEAD_U, edge_head.u);
				QTRACE (QT_STEP_BAD_STEP, pedge->u_step);
				QTRACE (QT_STEP_BAD_PREV_PTR, (int)pedge->prev);
				QTRACE (QT_STEP_BAD_WEDGE_PTR, (int)pwedge);
				return;
			}
		}

		if (qtrace_step_debug)
			QTRACE (QT_STEP_CP_WEDGE, (int)pwedge);

	// put the edge back into the edge list
		QTRACE_STEP_CHECK (pwedge->next, QEB_STEP_WEDGE);
		pedge->next = pwedge->next;
		pedge->prev = pwedge;
		pedge->next->prev = pedge;
		pwedge->next = pedge;

		if (qtrace_step_debug)
			QTRACE (QT_STEP_CP_REINSERT, (int)pedge);

		QTRACE_STEP_CHECK (pnext_edge, QEB_STEP_PEDGE);
		pedge = pnext_edge;
		if (pedge == &edge_tail)
		{
			QTRACE (QT_STEP_TRACE_EXIT, (int)pedge);
			return;
		}

		if (qtrace_step_debug)
			QTRACE (QT_STEP_CP_NEXT, (int)pedge);
	}
}
#endif


/*
==============
R_CleanupSpan
==============
*/
void R_CleanupSpan ()
{
	surf_t	*surf;
	int		iu;
	espan_t	*span;

// now that we've reached the right edge of the screen, we're done with any
// unfinished surfaces, so emit a span for whatever's on top
	surf = surfaces[1].next;
	iu = edge_tail_u_shift20;
	if (iu > surf->last_u)
	{
		span = span_p++;
		span->u = surf->last_u;
		span->count = iu - span->u;
		span->v = current_iv;
		span->pnext = surf->spans;
		surf->spans = span;
	}

// reset spanstate for all surfaces in the surface stack
	do
	{
		surf->spanstate = 0;
		surf = surf->next;
	} while (surf != &surfaces[1]);
}


/*
==============
R_LeadingEdgeBackwards
==============
*/
void R_LeadingEdgeBackwards (edge_t *edge)
{
	espan_t			*span;
	surf_t			*surf, *surf2;
	int				iu;

// it's adding a new surface in, so find the correct place
	surf = &surfaces[edge->surfs[1]];

// don't start a span if this is an inverted span, with the end
// edge preceding the start edge (that is, we've already seen the
// end edge)
	if (++surf->spanstate == 1)
	{
		surf2 = surfaces[1].next;

		if (surf->key > surf2->key)
			goto newtop;

	// if it's two surfaces on the same plane, the one that's already
	// active is in front, so keep going unless it's a bmodel
		if (surf->insubmodel && (surf->key == surf2->key))
		{
		// must be two bmodels in the same leaf; don't care, because they'll
		// never be farthest anyway
			goto newtop;
		}

continue_search:

		do
		{
			surf2 = surf2->next;
		} while (surf->key < surf2->key);

		if (surf->key == surf2->key)
		{
		// if it's two surfaces on the same plane, the one that's already
		// active is in front, so keep going unless it's a bmodel
			if (!surf->insubmodel)
				goto continue_search;

		// must be two bmodels in the same leaf; don't care which is really
		// in front, because they'll never be farthest anyway
		}

		goto gotposition;

newtop:
	// emit a span (obscures current top)
		iu = edge->u >> 20;

		if (iu > surf2->last_u)
		{
			span = span_p++;
			span->u = surf2->last_u;
			span->count = iu - span->u;
			span->v = current_iv;
			span->pnext = surf2->spans;
			surf2->spans = span;
		}

		// set last_u on the new span
		surf->last_u = iu;
				
gotposition:
	// insert before surf2
		surf->next = surf2;
		surf->prev = surf2->prev;
		surf2->prev->next = surf;
		surf2->prev = surf;
	}
}


/*
==============
R_TrailingEdge
==============
*/
void R_TrailingEdge (surf_t *surf, edge_t *edge)
{
	espan_t			*span;
	int				iu;

// don't generate a span if this is an inverted span, with the end
// edge preceding the start edge (that is, we haven't seen the
// start edge yet)
	if (--surf->spanstate == 0)
	{
		if (surf->insubmodel)
			r_bmodelactive--;

		if (surf == surfaces[1].next)
		{
		// emit a span (current top going away)
			iu = edge->u >> 20;
			if (iu > surf->last_u)
			{
				span = span_p++;
				span->u = surf->last_u;
				span->count = iu - span->u;
				span->v = current_iv;
				span->pnext = surf->spans;
				surf->spans = span;
			}

		// set last_u on the surface below
			surf->next->last_u = iu;
		}

		surf->prev->next = surf->next;
		surf->next->prev = surf->prev;
	}
}


// The ASM R_GenerateSpans/R_LeadingEdge translation emits incorrect spans.
// Keep the C version linked until the ASM translation is fixed.
#if	1

/*
==============
R_LeadingEdge
==============
*/
void R_LeadingEdge (edge_t *edge)
{
	espan_t			*span;
	surf_t			*surf, *surf2;
	int				iu;
	double			fu, newzi, testzi, newzitop, newzibottom;

	if (edge->surfs[1])
	{
	// it's adding a new surface in, so find the correct place
		surf = &surfaces[edge->surfs[1]];

	// don't start a span if this is an inverted span, with the end
	// edge preceding the start edge (that is, we've already seen the
	// end edge)
		if (++surf->spanstate == 1)
		{
			if (surf->insubmodel)
				r_bmodelactive++;

			surf2 = surfaces[1].next;

			if (surf->key < surf2->key)
				goto newtop;

		// if it's two surfaces on the same plane, the one that's already
		// active is in front, so keep going unless it's a bmodel
			if (surf->insubmodel && (surf->key == surf2->key))
			{
			// must be two bmodels in the same leaf; sort on 1/z
				fu = (float)(edge->u - 0xFFFFF) * (1.0 / 0x100000);
				newzi = surf->d_ziorigin + fv*surf->d_zistepv +
						fu*surf->d_zistepu;
				newzibottom = newzi * 0.99;

				testzi = surf2->d_ziorigin + fv*surf2->d_zistepv +
						fu*surf2->d_zistepu;

				if (newzibottom >= testzi)
				{
					goto newtop;
				}

				newzitop = newzi * 1.01;
				if (newzitop >= testzi)
				{
					if (surf->d_zistepu >= surf2->d_zistepu)
					{
						goto newtop;
					}
				}
			}

continue_search:

			do
			{
				surf2 = surf2->next;
			} while (surf->key > surf2->key);

			if (surf->key == surf2->key)
			{
			// if it's two surfaces on the same plane, the one that's already
			// active is in front, so keep going unless it's a bmodel
				if (!surf->insubmodel)
					goto continue_search;

			// must be two bmodels in the same leaf; sort on 1/z
				fu = (float)(edge->u - 0xFFFFF) * (1.0 / 0x100000);
				newzi = surf->d_ziorigin + fv*surf->d_zistepv +
						fu*surf->d_zistepu;
				newzibottom = newzi * 0.99;

				testzi = surf2->d_ziorigin + fv*surf2->d_zistepv +
						fu*surf2->d_zistepu;

				if (newzibottom >= testzi)
				{
					goto gotposition;
				}

				newzitop = newzi * 1.01;
				if (newzitop >= testzi)
				{
					if (surf->d_zistepu >= surf2->d_zistepu)
					{
						goto gotposition;
					}
				}

				goto continue_search;
			}

			goto gotposition;

newtop:
		// emit a span (obscures current top)
			iu = edge->u >> 20;

			if (iu > surf2->last_u)
			{
				span = span_p++;
				span->u = surf2->last_u;
				span->count = iu - span->u;
				span->v = current_iv;
				span->pnext = surf2->spans;
				surf2->spans = span;
			}

			// set last_u on the new span
			surf->last_u = iu;
				
gotposition:
		// insert before surf2
			surf->next = surf2;
			surf->prev = surf2->prev;
			surf2->prev->next = surf;
			surf2->prev = surf;
		}
	}
}


/*
==============
R_GenerateSpans
==============
*/
void R_GenerateSpans (void)
{
	edge_t			*edge;
	surf_t			*surf;

	r_bmodelactive = 0;

// clear active surfaces to just the background surface
	surfaces[1].next = surfaces[1].prev = &surfaces[1];
	surfaces[1].last_u = edge_head_u_shift20;

// generate spans
	for (edge=edge_head.next ; edge != &edge_tail; edge=edge->next)
	{			
		if (edge->surfs[0])
		{
		// it has a left surface, so a surface is going away for this span
			surf = &surfaces[edge->surfs[0]];

			R_TrailingEdge (surf, edge);

			if (!edge->surfs[1])
				continue;
		}

		R_LeadingEdge (edge);
	}

	R_CleanupSpan ();
}

#endif	// !id386


/*
==============
R_GenerateSpansBackward
==============
*/
void R_GenerateSpansBackward (void)
{
	edge_t			*edge;

	r_bmodelactive = 0;

// clear active surfaces to just the background surface
	surfaces[1].next = surfaces[1].prev = &surfaces[1];
	surfaces[1].last_u = edge_head_u_shift20;

// generate spans
	for (edge=edge_head.next ; edge != &edge_tail; edge=edge->next)
	{			
		if (edge->surfs[0])
			R_TrailingEdge (&surfaces[edge->surfs[0]], edge);

		if (edge->surfs[1])
			R_LeadingEdgeBackwards (edge);
	}

	R_CleanupSpan ();
}


/*
==============
R_ScanEdges

Input: 
newedges[] array
	this has links to edges, which have links to surfaces

Output:
Each surface has a linked list of its visible spans
==============
*/
void R_ScanEdges (void)
{
	int		iv, bottom;
	byte	basespans[MAXSPANS*sizeof(espan_t)+CACHE_SIZE];
	espan_t	*basespan_p;
	surf_t	*s;

	QTRACE (QT_SCAN_EDGES_ENTER, r_framecount);
#ifdef QTRACE_ENABLE
	if (r_framecount >= 0x7FFFFFFF)
		qtrace_insert_debug = 1;
	if (r_framecount >= 0x7FFFFFFF)
		qtrace_step_debug = 1;
#endif

	basespan_p = (espan_t *)
			((long)(basespans + CACHE_SIZE - 1) & ~(CACHE_SIZE - 1));
	max_span_p = &basespan_p[MAXSPANS - r_refdef.vrect.width];

	span_p = basespan_p;

// clear active edges to just the background edges around the whole screen
// FIXME: most of this only needs to be set up once
	edge_head.u = r_refdef.vrect.x << 20;
	edge_head_u_shift20 = edge_head.u >> 20;
	edge_head.u_step = 0;
	edge_head.prev = NULL;
	edge_head.next = &edge_tail;
	edge_head.surfs[0] = 0;
	edge_head.surfs[1] = 1;
	
	edge_tail.u = (r_refdef.vrectright << 20) + 0xFFFFF;
	edge_tail_u_shift20 = edge_tail.u >> 20;
	edge_tail.u_step = 0;
	edge_tail.prev = &edge_head;
	edge_tail.next = &edge_aftertail;
	edge_tail.surfs[0] = 1;
	edge_tail.surfs[1] = 0;
	
	edge_aftertail.u = -1;		// force a move
	edge_aftertail.u_step = 0;
	edge_aftertail.next = &edge_sentinel;
	edge_aftertail.prev = &edge_tail;

// FIXME: do we need this now that we clamp x in r_draw.c?
	edge_sentinel.u = 2000 << 24;		// make sure nothing sorts past this
	edge_sentinel.prev = &edge_aftertail;

//	
// process all scan lines
//
	bottom = r_refdef.vrectbottom - 1;

	for (iv=r_refdef.vrect.y ; iv<bottom ; iv++)
	{
		current_iv = iv;
		QTRACE_RATE (QT_SCAN_LINE, iv, 32);
		fv = (float)iv;

	// mark that the head (background start) span is pre-included
		surfaces[1].spanstate = 1;

		QTRACE_SCAN (QT_SCAN_INSERT_BEFORE, iv);
#ifdef QTRACE_ENABLE
		if (qtrace_insert_debug && newedges[iv])
			R_TraceNewEdges (iv, newedges[iv]);
		if (qtrace_step_debug && newedges[iv])
			QTraceCheckNewEdges (iv, newedges[iv]);
#endif
		if (newedges[iv])
		{
			R_InsertNewEdges (newedges[iv], edge_head.next);
		}
#ifdef QTRACE_ENABLE
		if (qtrace_step_debug && newedges[iv])
			QTraceCheckActiveList (QEB_ACTIVE_AFTER_INSERT);
#endif
		QTRACE_SCAN (QT_SCAN_INSERT_AFTER, iv);

		QTRACE_SCAN (QT_SCAN_SPANS_BEFORE, iv);
		(*pdrawfunc) ();
		QTRACE_SCAN (QT_SCAN_SPANS_AFTER, iv);

	// flush the span list if we can't be sure we have enough spans left for
	// the next scan
		QTRACE_SCAN (QT_SCAN_FLUSH_CHECK, iv);
		if (span_p >= max_span_p)
		{
			QTRACE (QT_FLUSH_UNLOCK, iv);
			VID_UnlockBuffer ();
			QTRACE (QT_FLUSH_UNLOCK_DONE, iv);
			S_ExtraUpdate ();	// don't let sound get messed up if going slow
			QTRACE (QT_FLUSH_SOUND_DONE, iv);
			VID_LockBuffer ();
			QTRACE (QT_FLUSH_LOCK_DONE, iv);
		
			if (r_drawculledpolys)
			{
				R_DrawCulledPolys ();
			}
			else
			{
				D_DrawSurfaces ();
			}
			QTRACE (QT_FLUSH_DRAW_DONE, iv);

		// clear the surface span pointers
			for (s = &surfaces[1] ; s<surface_p ; s++)
				s->spans = NULL;

			span_p = basespan_p;
		}

		QTRACE_SCAN (QT_SCAN_REMOVE_BEFORE, iv);
#ifdef QTRACE_ENABLE
		if (qtrace_step_debug && removeedges[iv])
			QTraceCheckRemoveEdges (iv, removeedges[iv]);
#endif
		if (removeedges[iv])
			R_RemoveEdges (removeedges[iv]);
#ifdef QTRACE_ENABLE
		if (qtrace_step_debug && removeedges[iv])
			QTraceCheckActiveList (QEB_ACTIVE_AFTER_REMOVE);
#endif
		QTRACE_SCAN (QT_SCAN_REMOVE_AFTER, iv);

		QTRACE_SCAN (QT_SCAN_STEP_BEFORE, iv);
		if (edge_head.next != &edge_tail)
		{
#ifdef QTRACE_ENABLE
			if (qtrace_step_debug)
				QTraceCheckActiveList (QEB_ACTIVE_BEFORE_STEP);
#endif
#ifdef QTRACE_ENABLE
			R_StepActiveU_Trace (edge_head.next);
#else
			R_StepActiveU (edge_head.next);
#endif
		}
		QTRACE_SCAN (QT_SCAN_STEP_AFTER, iv);
	}

// do the last scan (no need to step or sort or remove on the last scan)

	current_iv = iv;
	fv = (float)iv;

// mark that the head (background start) span is pre-included
	surfaces[1].spanstate = 1;

	if (newedges[iv])
		R_InsertNewEdges (newedges[iv], edge_head.next);

	(*pdrawfunc) ();

// draw whatever's left in the span list
	if (r_drawculledpolys)
		R_DrawCulledPolys ();
	else
		D_DrawSurfaces ();

	QTRACE (QT_SCAN_EDGES_EXIT, r_framecount);
}


