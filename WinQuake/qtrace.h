#ifndef QTRACE_H
#define QTRACE_H

/*
 * Temporary file-based renderer trace.  Enabled only when QTRACE_ENABLE=1
 * is passed to wmake.  With QTRACE_ENABLE undefined every macro below
 * compiles away.
 */

#define QT_VIEW_ENTER             0x0100
#define QT_VIEW_EXIT              0x0101
#define QT_SETUP_FRAME_DONE       0x0110
#define QT_EDGE_DRAW_ENTER        0x0111
#define QT_EDGE_DRAW_EXIT         0x0112
#define QT_ENTITIES_ENTER         0x0113
#define QT_ENTITIES_EXIT          0x0114
#define QT_VIEWMODEL_ENTER        0x0115
#define QT_VIEWMODEL_EXIT         0x0116
#define QT_PARTICLES_ENTER        0x0117
#define QT_PARTICLES_EXIT         0x0118
#define QT_VID_UPDATE_ENTER       0x0120
#define QT_VID_UPDATE_EXIT        0x0121

#define QT_RENDER_WORLD_ENTER     0x0200
#define QT_RENDER_WORLD_EXIT      0x0201
#define QT_BSP_NODE               0x0202
#define QT_RENDER_FACE            0x0210
#define QT_SCAN_EDGES_ENTER       0x0220
#define QT_SCAN_EDGES_EXIT        0x0221
#define QT_SCAN_LINE              0x0222
#define QT_SCAN_INSERT_BEFORE     0x0223
#define QT_SCAN_INSERT_AFTER      0x0224
#define QT_SCAN_SPANS_BEFORE      0x0225
#define QT_SCAN_SPANS_AFTER       0x0226
#define QT_SCAN_FLUSH_CHECK       0x0227
#define QT_SCAN_REMOVE_BEFORE     0x0228
#define QT_SCAN_REMOVE_AFTER      0x0229
#define QT_SCAN_STEP_BEFORE       0x022A
#define QT_SCAN_STEP_AFTER        0x022B
#define QT_STEP_TRACE_ENTER       0x022C
#define QT_STEP_TRACE_EXIT        0x022D
#define QT_STEP_RUNAWAY_OUTER     0x022E
#define QT_STEP_RUNAWAY_PUSHBACK  0x022F
#define QT_STEP_BAD_EDGE_U        0x0238
#define QT_STEP_BAD_PREV_U        0x0239
#define QT_STEP_BAD_HEAD_U        0x023A
#define QT_STEP_BAD_STEP          0x023B
#define QT_STEP_BAD_PREV_PTR      0x023C
#define QT_STEP_BAD_WEDGE_PTR     0x023D
#define QT_STEP_CP_ENTER_DONE     0x0270
#define QT_STEP_CP_OUTER          0x0271
#define QT_STEP_CP_PUSHBACK       0x0272
#define QT_STEP_CP_PULLED         0x0273
#define QT_STEP_CP_WEDGE          0x0274
#define QT_STEP_CP_REINSERT       0x0275
#define QT_STEP_CP_NEXT           0x0276
#define QT_STEP_CP_PB_LOOP        0x0277
#define QT_POLY_TRACE_ENTER       0x0280
#define QT_POLY_TRACE_EXIT        0x0281
#define QT_POLY_TRACE_PRE         0x0282
#define QT_POLY_TRACE_SPAN        0x0283
#define QT_POLY_TRACE_BAD_LCOUNT  0x0284
#define QT_POLY_TRACE_BAD_COUNT   0x0285
#define QT_POLY_TRACE_GUARD       0x0286
#define QT_POST_EDGE_UNLOCK       0x0290
#define QT_POST_EDGE_UNLOCK_DONE  0x0291
#define QT_POST_EDGE_SOUND_DONE   0x0292
#define QT_POST_EDGE_LOCK_DONE    0x0293
#define QT_INS_INFO               0x02A0
#define QT_INS_IV                 0x02A1
#define QT_INS_PTR                0x02A2
#define QT_INS_U                  0x02A3
#define QT_INS_STEP               0x02A4
#define QT_INS_NEXT               0x02A5
#define QT_INS_NEXTREMOVE         0x02A6
#define QT_INS_OWNER              0x02A7
#define QT_INS_CIRCULAR           0x02A8
#define QT_FLUSH_UNLOCK           0x02B0
#define QT_FLUSH_UNLOCK_DONE      0x02B1
#define QT_FLUSH_SOUND_DONE       0x02B2
#define QT_FLUSH_LOCK_DONE        0x02B3
#define QT_FLUSH_DRAW_DONE        0x02B4
#define QT_EDGE_BAD_WHERE         0x02C0
#define QT_EDGE_BAD_PTR           0x02C1
#define QT_EDGE_BAD_AUX           0x02C2
#define QT_EDGE_BAD_FRAME         0x02C3
#define QT_EDGE_BAD_IV            0x02C4
#define QT_VID_SWAP_ENTER         0x02D0
#define QT_VID_SWAP_EXIT          0x02D1
#define QT_VID_MODECHECK_DONE     0x02D2
#define QT_VGA_WAIT_DONE          0x02D3
#define QT_VGA_COPY_ENTER         0x02D4
#define QT_VGA_COPY_EXIT          0x02D5
#define QT_VGA_PLANAR_ENTER       0x02D6
#define QT_VGA_PLANAR_EXIT        0x02D7
#define QT_DRAW_SURFACES_ENTER    0x0230
#define QT_DRAW_SURFACES_EXIT     0x0231
#define QT_DRAW_SURF              0x0232

#define QT_ALIAS_DRAW_ENTER       0x0240
#define QT_ALIAS_DRAW_EXIT        0x0241
#define QT_ALIAS_SETUP_DONE       0x0242
#define QT_ALIAS_PREPARE_ENTER    0x0243
#define QT_ALIAS_PREPARE_EXIT     0x0244
#define QT_POLYSET_SPANS_ENTER    0x0250
#define QT_POLYSET_SPANS_EXIT     0x0251
#define QT_SPRITE_ENTER           0x0260
#define QT_SPRITE_EXIT            0x0261

#define QT_SND_START              0x02E0
#define QT_SND_PAINT_ENTER        0x02E1
#define QT_SND_PAINT_EXIT         0x02E2
#define QT_SND_CHAN_INFO          0x02E3
#define QT_SND_CHAN_DONE          0x02E4
#define QT_SND_XFER_ENTER         0x02E5
#define QT_SND_XFER_LOOP          0x02E6
#define QT_SND_XFER_EXIT          0x02E7

#ifdef QTRACE_ENABLE

void qtrace_i_ (unsigned tag, int payload);
void qtrace_i4_ (unsigned tag, int a, int b, int c, int d);
void qtrace_rate_ (unsigned tag, int payload, unsigned every);

#define QTRACE(tag, payload) qtrace_i_ ((unsigned)(tag), (int)(payload))
#define QTRACE4(tag, a, b, c, d) \
	qtrace_i4_ ((unsigned)(tag), (int)(a), (int)(b), (int)(c), (int)(d))
#define QTRACE_RATE(tag, payload, every) \
	qtrace_rate_ ((unsigned)(tag), (int)(payload), (unsigned)(every))

#else

#define QTRACE(tag, payload) ((void)0)
#define QTRACE4(tag, a, b, c, d) ((void)0)
#define QTRACE_RATE(tag, payload, every) ((void)0)

#endif

#endif /* QTRACE_H */
