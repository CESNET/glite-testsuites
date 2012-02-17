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
LFLAGS_SER=-L${LIB_PATH} -lcanl_c

CFLAGS_CLI=-Wall -g
LFLAGS_CLI=-L${LIB_PATH} -lcanl_c

all: client server

client: ${OBJ_CLI}
	${LINK} $< ${LFLAGS_CLI} -o $@

${OBJ_CLI}: ${SRC_CLI} ${LIBCANL}
	${COMPILE} -c ${top_srcdir}/examples/${SRC_CLI} ${CFLAGS_CLI} -o $@

server: ${OBJ_SER}
	${LINK} $< ${LFLAGS_SER} -o $@

${OBJ_SER}: ${SRC_SER} ${LIBCANL}
	${COMPILE} -c ${top_srcdir}/examples/${SRC_SER} ${CFLAGS_SER} -o $@

clean:
	rm -rfv *.o client server
