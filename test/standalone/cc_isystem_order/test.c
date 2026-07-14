#include <fcntl.h>
#include <stddef.h>

#ifndef TEST_OVERRIDE_FCNTL_SEEN
#error user -isystem fcntl.h was not searched before bundled libc headers
#endif

#ifndef TEST_OVERRIDE_STDDEF_SEEN
#error user -isystem stddef.h was not searched before compiler builtin headers
#endif

#if __GLIBC__ != 2 || __GLIBC_MINOR__ != 28
#error fcntl.h did not resolve to the target's bundled glibc headers
#endif

static size_t size;

int use_headers(void) {
    return O_RDONLY + (int)size;
}
