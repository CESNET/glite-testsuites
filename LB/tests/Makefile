CC=gcc
CFLAGS=-W -Wall -g -O2
LDFLAGS=
EXEC=testSocket JSON_checker

# XXX: license evil issues
JSON_URL=http://www.json.org/JSON_checker
JSON_SOURCES=JSON_checker.c JSON_checker.h main.c
JSON_OBJS=$(JSON_SOURCES:.c=.o)

all: $(EXEC)

fetch $(JSON_SOURCES):
	rm -fv $(JSON_SOURCES)
	wget -nv $(JSON_URL)/JSON_checker.c $(JSON_URL)/JSON_checker.h $(JSON_URL)/main.c
	sed -i 's/^}/    return 0;\n}\n/' main.c

testSocket: testSocket.c
	$(CC) -o $@ $< $(CFLAGS) 
	rm -f tests 
	ln -fs . tests

JSON_checker: $(JSON_OBJS)
	$(CC) -o $@ $+ $(LDFLAGS)

clean:
	rm -rvf *.o tests $(EXEC) *.tmp *.err

distclean:
	rm -fv $(JSON_SOURCES)

.c.o: %.o: %.c
	$(CC) $(CFLAGS) -I. -c $<
