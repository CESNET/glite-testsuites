top_srcdir=.
VPATH=${top_srcdir}/examples
CC=gcc
LIB_PATH=

SRC_CLI=canl_sample_client.c
OBJ_CLI=canl_sample_client.o

SRC_SER=canl_sample_server.c
OBJ_SER=canl_sample_server.o

LINK=${CC} ${LDFLAGS}
COMPILE=${CC} ${CFLAGS}

CFLAGS_SER=-Wall -g
LFLAGS_SER=${LIB_PATH} -lcanl_c

CFLAGS_CLI=-Wall -g
LFLAGS_CLI=${LIB_PATH} -lcanl_c

all: emi-canl-client emi-canl-server

emi-canl-client: ${OBJ_CLI}
	${LINK} $< ${LFLAGS_CLI} -o $@

${OBJ_CLI}: ${SRC_CLI} ${LIBCANL}
	${COMPILE} -c ${top_srcdir}/examples/${SRC_CLI} ${CFLAGS_CLI} -o $@

emi-canl-server: ${OBJ_SER}
	${LINK} $< ${LFLAGS_SER} -o $@

${OBJ_SER}: ${SRC_SER} ${LIBCANL}
	${COMPILE} -c ${top_srcdir}/examples/${SRC_SER} ${CFLAGS_SER} -o $@

clean:
	rm -rfv *.o emi-canl-server emi-canl-client
