/* Purpose: own accepted TCP streams and exchange complete IP datagrams.
 * Assumes: lib_socket:'udp-bind!'/2 and 'tcp-listen!'/3 set sockets nonblocking before
 * publication, so receive never waits while holding a foreign stream lock.
 * Guarantees: numeric endpoints retain their actual ports; oversized packets
 * raise instead of returning a truncated payload.
 * [tested: lib_socket; commit=781ee98e188c23ea7ef9298636d6e5e6c7fdc727].
 * Owns resources: accept_owner roots partial streams until finish_accept;
 * stream halves then share one descriptor, closed after the final reference.
 * Unpublished owners abort and release their resources during cleanup.
 * Guarded by: PL_get_stream locks borrowed descriptors; accepted halves use
 * atomic reference counts. Each unpublished owner belongs to its acquiring thread.
 * [tested: lib_socket; commit=781ee98e188c23ea7ef9298636d6e5e6c7fdc727].
 * Decides: signal checks use the host socket provider's 250ms wait interval;
 * accepted descriptors are nonblocking and do not use positive linger.
 * [source: https://github.com/SWI-Prolog/packages-clib/blob/a69cf00dcf0dd2e3ac1aa9565fbebf4aa4ceb5da/nonblockio.c#L452; commit=781ee98e188c23ea7ef9298636d6e5e6c7fdc727].
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#define SWIPL_WINDOWS_NATIVE_ACCESS 1
#include <SWI-Prolog.h>
#include <SWI-Stream.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <limits.h>

#ifdef __WINDOWS__
#include <ws2tcpip.h>
typedef SOCKET socket_fd;
typedef int address_length;
#define socket_descriptor(s) Swinsock(s)
#define socket_errno() WSAGetLastError()
#define invalid_socket INVALID_SOCKET
#define SHUT_RD SD_RECEIVE
#define SHUT_WR SD_SEND
#define SHUT_RDWR SD_BOTH
#else
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <time.h>
typedef int socket_fd;
typedef socklen_t address_length;
#define socket_descriptor(s) Sfileno(s)
#define socket_errno() errno
#define invalid_socket (-1)
#endif

static int native_error(const char *operation, int code, const char *message)
{ term_t error = PL_new_term_ref();
#ifdef __WINDOWS__
  char text[80];
  if (!message)
  { snprintf(text,sizeof(text),"Windows socket error %d",code); message=text; }
#else
  if (!message) message=strerror(code);
#endif
  if (!PL_unify_term(error,PL_FUNCTOR_CHARS,"error",2,
                      PL_FUNCTOR_CHARS,"socket_native_error",3,
                        PL_CHARS,operation,PL_INT,code,PL_UTF8_STRING,message,
                      PL_VARIABLE)) return FALSE;
  return PL_raise_exception(error);
}

static int locked_socket(term_t value, IOSTREAM **stream, socket_fd *fd)
{ if (!PL_get_stream(value,stream,SIO_INPUT)) return FALSE;
  *fd=socket_descriptor(*stream);
  if (*fd!=invalid_socket) return TRUE;
  if (!PL_release_stream(*stream)) return FALSE;
  return PL_domain_error("socket_stream",value);
}

static int address_terms(struct sockaddr_storage *address, address_length length,
                         term_t family, term_t host, term_t port)
{ char name[NI_MAXHOST]; const char *domain; int number;
  if (address->ss_family==AF_INET)
  { domain="ipv4"; number=ntohs(((struct sockaddr_in *)address)->sin_port); }
  else if (address->ss_family==AF_INET6)
  { domain="ipv6"; number=ntohs(((struct sockaddr_in6 *)address)->sin6_port); }
  else return PL_domain_error("ip_socket_family",family);
  int rc=getnameinfo((struct sockaddr *)address,length,name,sizeof(name),NULL,0,
                     NI_NUMERICHOST);
  if (rc) return native_error("getnameinfo",rc,gai_strerror(rc));
  return PL_unify_atom_chars(family,domain) && PL_unify_string_chars(host,name) &&
         PL_unify_integer(port,number);
}

static foreign_t socket_kind(term_t value, term_t kind)
{ IOSTREAM *stream; socket_fd fd; int type, listening=0;
  address_length length=sizeof(type);
  if (!locked_socket(value,&stream,&fd)) return FALSE;
  int rc=getsockopt(fd,SOL_SOCKET,SO_TYPE,(char *)&type,&length);
  if (!rc && type==SOCK_STREAM)
  { length=sizeof(listening);
    rc=getsockopt(fd,SOL_SOCKET,SO_ACCEPTCONN,(char *)&listening,&length); }
  int code=socket_errno();
  if (!PL_release_stream(stream)) return FALSE;
  if (rc) return native_error("getsockopt",code,NULL);
  if (type==SOCK_DGRAM) return PL_unify_atom_chars(kind,"udp");
  if (type==SOCK_STREAM)
    return PL_unify_atom_chars(kind,listening ? "listener" : "tcp");
  return PL_domain_error("tcp_or_udp_socket",value);
}

/* Workaround: swi-tcp-ipv6-peer - native accept formats an IPv6 peer as IPv4.
 * Read the complete address and source port from the connected descriptor.
 * https://github.com/SWI-Prolog/packages-clib/blob/a69cf00dcf0dd2e3ac1aa9565fbebf4aa4ceb5da/socket.c#L928
 */
static foreign_t socket_endpoint(term_t value, term_t side, term_t family,
                                  term_t host, term_t port)
{ IOSTREAM *stream; socket_fd fd; char *which;
  struct sockaddr_storage address; address_length length=sizeof(address);
  if (!PL_get_atom_chars(side,&which)) return PL_type_error("atom",side);
  int local=strcmp(which,"local")==0;
  if (!local && strcmp(which,"peer")!=0) return PL_domain_error("socket_side",side);
  if (!locked_socket(value,&stream,&fd)) return FALSE;
  int rc=local ? getsockname(fd,(struct sockaddr *)&address,&length)
               : getpeername(fd,(struct sockaddr *)&address,&length);
  int code=socket_errno();
  if (!PL_release_stream(stream)) return FALSE;
  if (rc) return native_error(local ? "getsockname" : "getpeername",code,NULL);
  return address_terms(&address,length,family,host,port);
}

static int would_block(int code)
{
#ifdef __WINDOWS__
  return code==WSAEWOULDBLOCK;
#else
  return code==EAGAIN || code==EWOULDBLOCK;
#endif
}

/* Workaround: swi-udp-ipv6-address - native udp_receive asserts for AF_INET6.
 * Use the OS address length and complete numeric endpoint for either family.
 * https://github.com/SWI-Prolog/packages-clib/blob/a69cf00dcf0dd2e3ac1aa9565fbebf4aa4ceb5da/socket.c#L539
 */
static foreign_t socket_receive(term_t value, term_t bytes, term_t family,
                                 term_t host, term_t port)
{ IOSTREAM *stream; socket_fd fd; char buffer[65536];
  struct sockaddr_storage address; address_length length=sizeof(address);
  int truncated=FALSE;
  if (!locked_socket(value,&stream,&fd)) return FALSE;
#ifdef __WINDOWS__
  int count=recvfrom(fd,buffer,sizeof(buffer),0,(struct sockaddr *)&address,&length);
#else
  struct iovec iov={buffer,sizeof(buffer)};
  struct msghdr message={0};
  message.msg_name=&address; message.msg_namelen=length;
  message.msg_iov=&iov; message.msg_iovlen=1;
  ssize_t count=recvmsg(fd,&message,0);
  length=message.msg_namelen; truncated=(message.msg_flags&MSG_TRUNC)!=0;
#endif
  int code=socket_errno();
  if (!PL_release_stream(stream)) return FALSE;
  if (count<0)
  { if (would_block(code)) return PL_unify_atom_chars(bytes,"blocked");
#ifndef __WINDOWS__
    if (code==EINTR)
      return PL_handle_signals()>=0 && PL_unify_atom_chars(bytes,"blocked");
#endif
    return native_error("receive",code,NULL);
  }
  if (truncated || count>65535) return PL_representation_error("complete_udp_datagram");
  return address_terms(&address,length,family,host,port) &&
         PL_unify_chars(bytes,PL_CODE_LIST|REP_ISO_LATIN_1,(size_t)count,buffer);
}

static foreign_t socket_shutdown(term_t value, term_t direction)
{ IOSTREAM *stream; socket_fd fd; int index;
  const int modes[]={SHUT_RD,SHUT_WR,SHUT_RDWR};
  if (!PL_get_integer_ex(direction,&index)) return FALSE;
  if (index<0 || index>=3) return PL_domain_error("socket_shutdown_direction",direction);
  if (!locked_socket(value,&stream,&fd)) return FALSE;
  int rc=shutdown(fd,modes[index]), code=socket_errno();
  if (!PL_release_stream(stream)) return FALSE;
  return rc ? native_error("shutdown",code,NULL) : TRUE;
}

/* Snew streams share a close authority, as clib's read/write callbacks do.
 * Its private socket blobs cannot import an OS descriptor. The public stream
 * interface supplies File byte I/O and descriptor access without that ABI.
 * https://github.com/SWI-Prolog/packages-clib/blob/a69cf00dcf0dd2e3ac1aa9565fbebf4aa4ceb5da/sockcommon.c#L119
 */
typedef struct connection connection;
typedef struct { connection *owner; IOSTREAM *stream; int output; } channel;
struct connection
{ socket_fd fd;
  atomic_uint references;
  atomic_bool aborting;
  channel ends[2];
};
typedef struct { connection *socket; atom_t roots[2]; } accept_owner;

static int close_descriptor(socket_fd fd)
{
#ifdef __WINDOWS__
  return closesocket(fd);
#else
  return close(fd);
#endif
}

static int release_connection(connection *owner)
{ if (atomic_fetch_sub(&owner->references,1)==1)
  { int result=owner->fd==invalid_socket ? 0 : close_descriptor(owner->fd);
    free(owner); return result;
  }
  return 0;
}

static int channel_exception(channel *end)
{ Sset_exception(end->stream,PL_exception(0)); errno=EPLEXCEPTION; return -1; }

static int channel_error(channel *end,const char *operation,int code)
{ native_error(operation,code,NULL); return channel_exception(end); }

static int interrupted(int code)
{
#ifdef __WINDOWS__
  return code==WSAEINTR;
#else
  return code==EINTR;
#endif
}

static int wait_channel(channel *end)
{ for (;;)
  { if (PL_handle_signals()<0) return channel_exception(end);
#ifdef __WINDOWS__
    fd_set set; FD_ZERO(&set); FD_SET(end->owner->fd,&set);
    struct timeval interval={0,250000};
    int ready=select(0,end->output ? NULL : &set,end->output ? &set : NULL,NULL,&interval);
#else
    struct pollfd watched={end->owner->fd,end->output ? POLLOUT : POLLIN,0};
    int ready=poll(&watched,1,250);
#endif
    if (ready>0) return TRUE;
    int code=socket_errno();
    if (ready<0 && !interrupted(code)) return channel_error(end,"wait",code);
  }
}

static ssize_t channel_transfer(void *handle,char *buffer,size_t length)
{ channel *end=handle;
  for (;;)
  { if (PL_handle_signals()<0) return channel_exception(end);
    if (end->output && atomic_load(&end->owner->aborting))
    { errno=EPIPE; return -1; }
#ifdef __WINDOWS__
    int size=length>INT_MAX ? INT_MAX : (int)length;
#else
    size_t size=length;
#endif
    ssize_t count=end->output ? send(end->owner->fd,buffer,size,0)
                              : recv(end->owner->fd,buffer,size,0);
    if (count>=0) return count;
    int code=socket_errno();
    if (would_block(code))
    { if (wait_channel(end)<0) return -1; }
    else if (!interrupted(code)) return channel_error(end,end->output ? "send" : "receive",code);
  }
}

static int channel_close(void *handle)
{ channel *end=handle;
  if (end->output) shutdown(end->owner->fd,SHUT_WR);
  return release_connection(end->owner);
}

static int channel_control(void *handle,int operation,void *argument)
{ channel *end=handle;
  switch (operation)
  {
#ifdef __WINDOWS__
    case SIO_GETWINSOCK:
#else
    case SIO_GETFILENO:
#endif
      *(socket_fd *)argument=end->owner->fd; return 0;
    case SIO_SETENCODING:
    case SIO_FLUSHOUTPUT: return 0;
    default: return -1;
  }
}
static IOFUNCTIONS channel_functions=
{ .read=channel_transfer, .write=channel_transfer, .close=channel_close, .control=channel_control };

static void abort_connection(connection *owner)
{ atomic_store(&owner->aborting,TRUE);
  if (owner->fd!=invalid_socket) shutdown(owner->fd,SHUT_RDWR);
}

static int dispose_accept_owner(accept_owner *owner,int published,int collecting)
{ connection *socket=owner->socket;
  if (!socket) return TRUE;
  owner->socket=NULL;
  int result=0;
  if (!published) abort_connection(socket);
  for (int i=1;i>=0;i--)
  { if (!published && owner->roots[i])
    { IOSTREAM *stream;
      if (PL_get_stream_from_blob(owner->roots[i],&stream,SIO_INPUT|SIO_OUTPUT|SIO_NOERROR))
      { /* Sclose consumes the stream locks, including this borrowed lock. */
        int closed=collecting ? Sgcclose(stream,0) : Sclose(stream);
        if (closed<0) result=-1;
      }
    }
    if (owner->roots[i]) PL_unregister_atom(owner->roots[i]);
  }
  if (release_connection(socket)<0) result=-1;
  return result==0;
}

static int release_accept_blob(atom_t atom)
{ accept_owner *owner=PL_blob_data(atom,NULL,NULL);
  dispose_accept_owner(owner,FALSE,TRUE); free(owner); return TRUE;
}
static PL_blob_t accept_owner_type=
{ .magic=PL_BLOB_MAGIC, .flags=PL_BLOB_NOCOPY, .name="socket_accept_owner",
  .release=release_accept_blob };

static int get_accept_owner(term_t value,accept_owner **owner)
{ PL_blob_t *type; size_t length;
  if (!PL_get_blob(value,(void **)owner,&length,&type) || type!=&accept_owner_type)
    return PL_type_error("socket_accept_owner",value);
  return TRUE;
}

static foreign_t socket_accept_owner(term_t value)
{ if (!PL_is_variable(value)) return PL_uninstantiation_error(value);
  accept_owner *owner=calloc(1,sizeof(*owner));
  if (!owner) return PL_resource_error("memory");
  return PL_unify_blob(value,owner,sizeof(*owner),&accept_owner_type);
}

static foreign_t socket_finish_accept(term_t value,term_t published)
{ accept_owner *owner; int transfer;
  if (!get_accept_owner(value,&owner) || !PL_get_bool_ex(published,&transfer)) return FALSE;
  if (dispose_accept_owner(owner,transfer,FALSE)) return TRUE;
  if (PL_exception(0)) return FALSE;
  return native_error("close",socket_errno(),NULL);
}

static foreign_t socket_abort_accept(term_t value)
{ accept_owner *owner;
  if (!get_accept_owner(value,&owner)) return FALSE;
  if (owner->socket) abort_connection(owner->socket);
  return TRUE;
}

static int configure_accepted(socket_fd fd)
{ struct linger immediate={0,0};
#ifdef __WINDOWS__
  u_long enabled=1;
  if (WSAEventSelect(fd,NULL,0)!=0 || ioctlsocket(fd,FIONBIO,&enabled)!=0) return FALSE;
#else
  int flags=fcntl(fd,F_GETFL,0);
  if (flags<0 || fcntl(fd,F_SETFL,flags|O_NONBLOCK)!=0) return FALSE;
#endif
  return setsockopt(fd,SOL_SOCKET,SO_LINGER,(char *)&immediate,sizeof(immediate))==0;
}

static int owned_channel(accept_owner *owner,int index,term_t value)
{ connection *socket=owner->socket; channel *end=&socket->ends[index];
  end->owner=socket; end->output=index;
  IOSTREAM *stream=Snew(end,(index ? SIO_OUTPUT : SIO_INPUT)|SIO_FBUF|SIO_RECORDPOS,
                       &channel_functions);
  if (!stream) return PL_resource_error("memory");
  atomic_fetch_add(&socket->references,1);
  end->stream=stream;
  if (!PL_unify_stream(value,stream) || !PL_get_atom(value,&owner->roots[index]))
  { Sclose(stream); end->stream=NULL; return FALSE; }
  PL_register_atom(owner->roots[index]);
  return TRUE;
}

static foreign_t socket_try_accept(term_t value,term_t listener,term_t input,term_t output)
{ accept_owner *owner; IOSTREAM *stream; socket_fd fd;
  if (!get_accept_owner(value,&owner)) return FALSE;
  if (owner->socket) return PL_permission_error("reuse","socket_accept_owner",value);
  connection *socket=calloc(1,sizeof(*socket));
  if (!socket) return PL_resource_error("memory");
  owner->socket=socket; socket->fd=invalid_socket;
  atomic_init(&socket->references,1); atomic_init(&socket->aborting,FALSE);
  if (!locked_socket(listener,&stream,&fd)) return FALSE;
#ifdef __linux__
  socket->fd=accept4(fd,NULL,NULL,SOCK_CLOEXEC|SOCK_NONBLOCK);
#else
  socket->fd=accept(fd,NULL,NULL);
#endif
  int code=socket_errno();
  if (!PL_release_stream(stream)) return FALSE;
  if (socket->fd==invalid_socket)
  { if (would_block(code) || interrupted(code))
      return PL_unify_atom_chars(input,"blocked") && PL_unify_atom_chars(output,"blocked");
    return native_error("accept",code,NULL);
  }
  if (!configure_accepted(socket->fd)) return native_error("configure",socket_errno(),NULL);
  term_t streams=PL_new_term_refs(2);
  return owned_channel(owner,0,streams) && owned_channel(owner,1,streams+1) &&
         PL_unify(input,streams) && PL_unify(output,streams+1);
}

static foreign_t socket_abort(term_t value)
{ IOSTREAM *stream;
  if (!PL_get_stream(value,&stream,SIO_INPUT|SIO_NOERROR)) return TRUE;
  socket_fd fd=socket_descriptor(stream);
  if (stream->functions==&channel_functions)
  { channel *end=stream->handle; abort_connection(end->owner); }
  else if (fd!=invalid_socket) shutdown(fd,SHUT_RDWR);
  return PL_release_stream_noerror(stream);
}

static foreign_t socket_monotonic(term_t value)
{
#ifdef __WINDOWS__
  double seconds=(double)GetTickCount64()/1000.0;
#else
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC,&now)!=0) return native_error("clock_gettime",errno,NULL);
  double seconds=(double)now.tv_sec+(double)now.tv_nsec/1000000000.0;
#endif
  return PL_unify_float(value,seconds);
}

install_t install_lib_socket(void)
{ PL_register_foreign("kind",2,socket_kind,0);
  PL_register_foreign("endpoint",5,socket_endpoint,0);
  PL_register_foreign("receive",5,socket_receive,0);
  PL_register_foreign("shutdown",2,socket_shutdown,0);
  PL_register_foreign("accept_owner",1,socket_accept_owner,0);
  PL_register_foreign("try_accept",4,socket_try_accept,0);
  PL_register_foreign("finish_accept",2,socket_finish_accept,0);
  PL_register_foreign("abort_accept",1,socket_abort_accept,0);
  PL_register_foreign("abort",1,socket_abort,0);
  PL_register_foreign("monotonic",1,socket_monotonic,0);
}
