/* Force ssize_t on Windows before nghttp2 headers (clang has no POSIX ssize_t). */
#ifndef NULLRAY_NGHTTP2_SSIZE_COMPAT_H
#define NULLRAY_NGHTTP2_SSIZE_COMPAT_H

#if defined(_WIN32) || defined(_WIN32_WCE)
#include <stddef.h>
#ifndef _SSIZE_T_DEFINED
typedef ptrdiff_t ssize_t;
#define _SSIZE_T_DEFINED
#endif
#endif

#endif
