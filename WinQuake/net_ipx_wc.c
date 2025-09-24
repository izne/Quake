// net_ipx_wc.c - Watcom stub for Quake DOS build
// Provides dummy IPX networking functions so the game links and runs
// without needing DPMI or real IPX support.

#include "quakedef.h"
#include "net_ipx.h"

//ipxAvailable = false;

int IPX_Init(void) {
    Con_Printf("IPX networking disabled in this build\n");
    return -1; // fail init
}

void IPX_Shutdown(void) {
    // nothing
}

void IPX_Listen (qboolean state) {
    // nothing
}

int IPX_GetMessage(qsocket_t *sock) {
    return 0;
}

int IPX_SendMessage(qsocket_t *sock, sizebuf_t *data) {
    return 0;
}

int IPX_CanSendMessage(qsocket_t *sock) {
    return 0;
}

int IPX_SendUnreliableMessage(qsocket_t *sock, sizebuf_t *data) {
    return 0;
}

int  IPX_Connect (int socket, struct qsockaddr *addr) {
    return 0;
}

int  IPX_CheckNewConnections (void) {
    return 0;
}
