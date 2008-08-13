CC=gcc
CFLAGS=
EXEC=testSocket

all: $(EXEC)

testSocket: testSocket.c
	$(CC) -o $@ $< $(CFLAGS) 
	rm -f tests 
	ln -fs . tests

clean:
	rm -rf *.o tests $(EXEC)

