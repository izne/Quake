#include "qtrace.h"

#ifdef QTRACE_ENABLE

#include <stdio.h>
#include <stddef.h>

typedef struct
{
	unsigned		tag;
	const char		*name;
} qtrace_name_t;

static const qtrace_name_t qtrace_names[] =
{
	{QT_VIEW_ENTER,			"VIEW_ENTER"},
	{QT_VIEW_EXIT,			"VIEW_EXIT"},
	{QT_SETUP_FRAME_DONE,	"SETUP_FRAME_DONE"},
	{QT_EDGE_DRAW_ENTER,	"EDGE_DRAW_ENTER"},
	{QT_EDGE_DRAW_EXIT,		"EDGE_DRAW_EXIT"},
	{QT_ENTITIES_ENTER,		"ENTITIES_ENTER"},
	{QT_ENTITIES_EXIT,		"ENTITIES_EXIT"},
	{QT_VIEWMODEL_ENTER,	"VIEWMODEL_ENTER"},
	{QT_VIEWMODEL_EXIT,		"VIEWMODEL_EXIT"},
	{QT_PARTICLES_ENTER,	"PARTICLES_ENTER"},
	{QT_PARTICLES_EXIT,		"PARTICLES_EXIT"},
	{QT_VID_UPDATE_ENTER,	"VID_UPDATE_ENTER"},
	{QT_VID_UPDATE_EXIT,	"VID_UPDATE_EXIT"},

	{QT_RENDER_WORLD_ENTER,	"RENDER_WORLD_ENTER"},
	{QT_RENDER_WORLD_EXIT,	"RENDER_WORLD_EXIT"},
	{QT_BSP_NODE,			"BSP_NODE"},
	{QT_RENDER_FACE,		"RENDER_FACE"},
	{QT_SCAN_EDGES_ENTER,	"SCAN_EDGES_ENTER"},
	{QT_SCAN_EDGES_EXIT,	"SCAN_EDGES_EXIT"},
	{QT_SCAN_LINE,			"SCAN_LINE"},
	{QT_SCAN_INSERT_BEFORE,	"SCAN_INSERT_BEFORE"},
	{QT_SCAN_INSERT_AFTER,	"SCAN_INSERT_AFTER"},
	{QT_SCAN_SPANS_BEFORE,	"SCAN_SPANS_BEFORE"},
	{QT_SCAN_SPANS_AFTER,	"SCAN_SPANS_AFTER"},
	{QT_SCAN_FLUSH_CHECK,	"SCAN_FLUSH_CHECK"},
	{QT_SCAN_REMOVE_BEFORE,	"SCAN_REMOVE_BEFORE"},
	{QT_SCAN_REMOVE_AFTER,	"SCAN_REMOVE_AFTER"},
	{QT_SCAN_STEP_BEFORE,	"SCAN_STEP_BEFORE"},
	{QT_SCAN_STEP_AFTER,	"SCAN_STEP_AFTER"},
	{QT_STEP_TRACE_ENTER,	"STEP_TRACE_ENTER"},
	{QT_STEP_TRACE_EXIT,	"STEP_TRACE_EXIT"},
	{QT_STEP_RUNAWAY_OUTER,	"STEP_RUNAWAY_OUTER"},
	{QT_STEP_RUNAWAY_PUSHBACK,"STEP_RUNAWAY_PUSHBACK"},
	{QT_STEP_BAD_EDGE_U,	"STEP_BAD_EDGE_U"},
	{QT_STEP_BAD_PREV_U,	"STEP_BAD_PREV_U"},
	{QT_STEP_BAD_HEAD_U,	"STEP_BAD_HEAD_U"},
	{QT_STEP_BAD_STEP,		"STEP_BAD_STEP"},
	{QT_STEP_BAD_PREV_PTR,	"STEP_BAD_PREV_PTR"},
	{QT_STEP_BAD_WEDGE_PTR,	"STEP_BAD_WEDGE_PTR"},
	{QT_STEP_CP_ENTER_DONE,	"STEP_CP_ENTER_DONE"},
	{QT_STEP_CP_OUTER,		"STEP_CP_OUTER"},
	{QT_STEP_CP_PUSHBACK,	"STEP_CP_PUSHBACK"},
	{QT_STEP_CP_PULLED,		"STEP_CP_PULLED"},
	{QT_STEP_CP_WEDGE,		"STEP_CP_WEDGE"},
	{QT_STEP_CP_REINSERT,	"STEP_CP_REINSERT"},
	{QT_STEP_CP_NEXT,		"STEP_CP_NEXT"},
	{QT_STEP_CP_PB_LOOP,	"STEP_CP_PB_LOOP"},
	{QT_POLY_TRACE_ENTER,	"POLY_TRACE_ENTER"},
	{QT_POLY_TRACE_EXIT,	"POLY_TRACE_EXIT"},
	{QT_POLY_TRACE_PRE,		"POLY_TRACE_PRE"},
	{QT_POLY_TRACE_SPAN,	"POLY_TRACE_SPAN"},
	{QT_POLY_TRACE_BAD_LCOUNT,"POLY_TRACE_BAD_LCOUNT"},
	{QT_POLY_TRACE_BAD_COUNT,"POLY_TRACE_BAD_COUNT"},
	{QT_POLY_TRACE_GUARD,	"POLY_TRACE_GUARD"},
	{QT_POST_EDGE_UNLOCK,	"POST_EDGE_UNLOCK"},
	{QT_POST_EDGE_UNLOCK_DONE,"POST_EDGE_UNLOCK_DONE"},
	{QT_POST_EDGE_SOUND_DONE,"POST_EDGE_SOUND_DONE"},
	{QT_POST_EDGE_LOCK_DONE,	"POST_EDGE_LOCK_DONE"},
	{QT_INS_INFO,			"INS_INFO"},
	{QT_INS_IV,				"INS_IV"},
	{QT_INS_PTR,			"INS_PTR"},
	{QT_INS_U,				"INS_U"},
	{QT_INS_STEP,			"INS_STEP"},
	{QT_INS_NEXT,			"INS_NEXT"},
	{QT_INS_NEXTREMOVE,		"INS_NEXTREMOVE"},
	{QT_INS_OWNER,			"INS_OWNER"},
	{QT_INS_CIRCULAR,		"INS_CIRCULAR"},
	{QT_FLUSH_UNLOCK,		"FLUSH_UNLOCK"},
	{QT_FLUSH_UNLOCK_DONE,	"FLUSH_UNLOCK_DONE"},
	{QT_FLUSH_SOUND_DONE,	"FLUSH_SOUND_DONE"},
	{QT_FLUSH_LOCK_DONE,	"FLUSH_LOCK_DONE"},
	{QT_FLUSH_DRAW_DONE,	"FLUSH_DRAW_DONE"},
	{QT_EDGE_BAD_WHERE,	"EDGE_BAD_WHERE"},
	{QT_EDGE_BAD_PTR,	"EDGE_BAD_PTR"},
	{QT_EDGE_BAD_AUX,	"EDGE_BAD_AUX"},
	{QT_EDGE_BAD_FRAME,	"EDGE_BAD_FRAME"},
	{QT_EDGE_BAD_IV,	"EDGE_BAD_IV"},
	{QT_VID_SWAP_ENTER,	"VID_SWAP_ENTER"},
	{QT_VID_SWAP_EXIT,	"VID_SWAP_EXIT"},
	{QT_VID_MODECHECK_DONE,"VID_MODECHECK_DONE"},
	{QT_VGA_WAIT_DONE,	"VGA_WAIT_DONE"},
	{QT_VGA_COPY_ENTER,	"VGA_COPY_ENTER"},
	{QT_VGA_COPY_EXIT,	"VGA_COPY_EXIT"},
	{QT_VGA_PLANAR_ENTER,	"VGA_PLANAR_ENTER"},
	{QT_VGA_PLANAR_EXIT,	"VGA_PLANAR_EXIT"},
	{QT_DRAW_SURFACES_ENTER,"DRAW_SURFACES_ENTER"},
	{QT_DRAW_SURFACES_EXIT,	"DRAW_SURFACES_EXIT"},
	{QT_DRAW_SURF,			"DRAW_SURF"},

	{QT_ALIAS_DRAW_ENTER,	"ALIAS_DRAW_ENTER"},
	{QT_ALIAS_DRAW_EXIT,	"ALIAS_DRAW_EXIT"},
	{QT_ALIAS_SETUP_DONE,	"ALIAS_SETUP_DONE"},
	{QT_ALIAS_PREPARE_ENTER,"ALIAS_PREPARE_ENTER"},
	{QT_ALIAS_PREPARE_EXIT,	"ALIAS_PREPARE_EXIT"},
	{QT_POLYSET_SPANS_ENTER,"POLYSET_SPANS_ENTER"},
	{QT_POLYSET_SPANS_EXIT,	"POLYSET_SPANS_EXIT"},
	{QT_SPRITE_ENTER,		"SPRITE_ENTER"},
	{QT_SPRITE_EXIT,		"SPRITE_EXIT"},

	{QT_SND_START,			"SND_START"},
	{QT_SND_PAINT_ENTER,	"SND_PAINT_ENTER"},
	{QT_SND_PAINT_EXIT,		"SND_PAINT_EXIT"},
	{QT_SND_CHAN_INFO,		"SND_CHAN_INFO"},
	{QT_SND_CHAN_DONE,		"SND_CHAN_DONE"},
	{QT_SND_XFER_ENTER,		"SND_XFER_ENTER"},
	{QT_SND_XFER_LOOP,		"SND_XFER_LOOP"},
	{QT_SND_XFER_EXIT,		"SND_XFER_EXIT"},

	{0, NULL}
};

static FILE			*qtrace_file;
static int			qtrace_busy;
static unsigned long	qtrace_seq;
static unsigned		qtrace_counts[256];

static void qtrace_hex32 (char *dst, unsigned long value)
{
	static const char digits[] = "0123456789ABCDEF";
	int			i;

	for (i = 0 ; i < 8 ; i++)
	{
		dst[i] = digits[(value >> 28) & 0xF];
		value <<= 4;
	}
	dst[8] = '\0';
}

static const char *qtrace_name (unsigned tag)
{
	const qtrace_name_t	*n;

	for (n = qtrace_names ; n->name ; n++)
	{
		if (n->tag == tag)
			return n->name;
	}
	return "UNKNOWN";
}

static unsigned qtrace_strlen (const char *s)
{
	unsigned	len = 0;

	while (*s++)
		len++;
	return len;
}

static unsigned qtrace_line (char *dst, unsigned tag, int payload)
{
	const char	*name = qtrace_name (tag);
	unsigned	len = 0;
	unsigned	i;
	char		seq[9];
	char		val[9];

	qtrace_hex32 (seq, qtrace_seq);
	qtrace_hex32 (val, (unsigned long)(unsigned)payload);

	while (seq[len])
	{
		dst[len] = seq[len];
		len++;
	}
	dst[len++] = ' ';

	for (i = 0 ; i < 22 ; i++)
	{
		if (i < qtrace_strlen (name))
			dst[len++] = name[i];
		else
			dst[len++] = ' ';
	}

	dst[len++] = ' ';
	for (i = 0 ; i < 8 ; i++)
		dst[len++] = val[i];
	dst[len++] = '\r';
	dst[len++] = '\n';
	dst[len] = '\0';

	return len;
}

static unsigned qtrace_line4 (char *dst, unsigned tag,
	int a, int b, int c, int d)
{
	const char	*name = qtrace_name (tag);
	unsigned	len = 0;
	unsigned	i;
	int			values[4];
	int			v;

	qtrace_hex32 (dst, qtrace_seq);
	len = 8;
	dst[len++] = ' ';

	for (i = 0 ; i < 22 ; i++)
	{
		if (i < qtrace_strlen (name))
			dst[len++] = name[i];
		else
			dst[len++] = ' ';
	}

	dst[len++] = ' ';
	values[0] = a;
	values[1] = b;
	values[2] = c;
	values[3] = d;
	for (v = 0 ; v < 4 ; v++)
	{
		char val[9];

		qtrace_hex32 (val, (unsigned long)(unsigned)values[v]);
		for (i = 0 ; i < 8 ; i++)
			dst[len++] = val[i];
		if (v != 3)
			dst[len++] = ' ';
	}

	dst[len++] = '\r';
	dst[len++] = '\n';
	dst[len] = '\0';
	return len;
}

static void qtrace_raw (const char *text, unsigned len)
{
	if (qtrace_file == NULL)
		return;
	fwrite (text, 1, len, qtrace_file);
	fflush (qtrace_file);
}

static void qtrace_open (void)
{
	static const char header[] =
		"QTRACE.LOG renderer phase trace\r\n"
		"SEQ       EVENT                  PAYLOAD\r\n";

	if (qtrace_file != NULL)
		return;

	qtrace_file = fopen ("QTRACE.LOG", "wb");
	if (qtrace_file == NULL)
		return;

	qtrace_raw (header, sizeof (header) - 1);
}

void qtrace_i_ (unsigned tag, int payload)
{
	char	line[80];
	unsigned	len;

	if (qtrace_busy)
		return;

	qtrace_busy = 1;
	qtrace_open ();
	if (qtrace_file != NULL)
	{
		qtrace_seq++;
		len = qtrace_line (line, tag, payload);
		qtrace_raw (line, len);
	}
	qtrace_busy = 0;
}

void qtrace_i4_ (unsigned tag, int a, int b, int c, int d)
{
	char	line[80];
	unsigned	len;

	if (qtrace_busy)
		return;

	qtrace_busy = 1;
	qtrace_open ();
	if (qtrace_file != NULL)
	{
		qtrace_seq++;
		len = qtrace_line4 (line, tag, a, b, c, d);
		qtrace_raw (line, len);
	}
	qtrace_busy = 0;
}

void qtrace_rate_ (unsigned tag, int payload, unsigned every)
{
	unsigned	index = tag & 0xFF;
	unsigned	count = ++qtrace_counts[index];

	if (count == 1 || (every && (count % every) == 0))
		qtrace_i_ (tag, payload);
}

#endif /* QTRACE_ENABLE */
