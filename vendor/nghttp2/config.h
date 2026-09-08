/* Minimal build config for static client-only nghttp2 in nullray. */
#ifndef CONFIG_H
#define CONFIG_H

#define HAVE_ARPA_INET_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_NETINET_IP_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_TIME_H 1
#define HAVE_UNISTD_H 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define STDC_HEADERS 1

#define PACKAGE "nghttp2"
#define PACKAGE_NAME "nghttp2"
#define PACKAGE_STRING "nghttp2 1.64.0"
#define PACKAGE_TARNAME "nghttp2"
#define PACKAGE_URL "https://nghttp2.org/"
#define PACKAGE_VERSION "1.64.0"
#define VERSION "1.64.0"

#endif
