CC=gcc
CFLAGS=
EXEC=testSocket

all: $(EXEC)

testSocket: testSocket.c
	$(CC) -o $@ $< $(CFLAGS) 

clean:
	rm -rf *.o

mrproper: clean
	rm -rf $(EXEC)
