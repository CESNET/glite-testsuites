#ident "$Header$"
/*
Copyright (c) Members of the EGEE Collaboration. 2004-2010.
See http://www.eu-egee.org/partners for details on the copyright holders.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/


#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netinet/in.h>
#include <netdb.h>
#include <errno.h>

#define BUFFSIZE 32

int main (int argc, char *argv[]) {
  int sock;
  struct hostent *hip;
  char *adrIPp;
  struct in_addr adrIP;
  struct sockaddr_in echoserver;
  char buffer[BUFFSIZE];
  unsigned int echolen;
  int received = 0;
  if (argc != 3) {
      fprintf(stderr, "USAGE: TCPecho <server_ip> <port>\n");
      exit(1);
  }
/* conversion from DNS to IPv4 */
  if ((hip = gethostbyname (argv[1])) == NULL) {
      fprintf(stderr,"Error with gethostbyname: %s",strerror(errno));
//      exit(1);
  }
  adrIP.s_addr = *(int *) hip->h_addr;
  adrIPp = (char *) inet_ntoa (adrIP);
/* Create the TCP socket */
  if ((sock = socket (PF_INET, SOCK_STREAM, IPPROTO_TCP)) < 0) {
      fprintf(stderr,"Failed to create socket: %s",strerror(errno));
      exit(1);
  }
/* Construct the server sockaddr_in structure */
  memset (&echoserver, 0, sizeof (echoserver));	/* Clear struct */
  echoserver.sin_family = AF_INET;	/* Internet/IP */
  echoserver.sin_addr.s_addr = inet_addr (adrIPp);	/* IP address */
  echoserver.sin_port = htons (atoi (argv[2]));	/* server port */
//  fprintf(stdout,"Connecting to: %s:%s\n", adrIPp, argv[2]);
/* Establish connection */
  if (connect (sock, (struct sockaddr *) &echoserver, sizeof (echoserver)) < 0) {
      //Die ("Failed to connect with server");
      fprintf(stderr,"Failed to connect with server (%s:%d): %s",adrIPp,atoi(argv[2]),strerror(errno));
      exit(1);
  } 
  shutdown (sock, 2);
//  fprintf(stdout," [OK]\n");
  exit(0);
}
