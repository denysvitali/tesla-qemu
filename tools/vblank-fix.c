/*
 * vblank-fix.c — LD_PRELOAD shim for QEMU/VirtIO GPU
 *
 * VirtIO GPU does not implement DRM_IOCTL_WAIT_VBLANK, so every call returns
 * ENOTSUP.  QtCar's render loop gates frame presentation on a successful
 * vblank wait, so the screen stays black.
 *
 * This shim intercepts ioctl() and returns 0 (success) for
 * DRM_IOCTL_WAIT_VBLANK, letting QtCar proceed to present each frame.
 *
 * DRM_IOCTL_WAIT_VBLANK = _IOWR('d', 0xa6, union drm_wait_vblank)
 *   sizeof(union drm_wait_vblank) = 24 on x86-64
 *   = (3<<30) | (0x64<<8) | 0xa6 | (24<<16) = 0xC01864a6
 */

#define _GNU_SOURCE
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <stdarg.h>
#include <unistd.h>
#include <time.h>

#define DRM_WAIT_VBLANK_IOCTL 0xC01864a6UL

int ioctl(int fd, unsigned long req, ...)
{
    va_list ap;
    va_start(ap, req);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    if (req == DRM_WAIT_VBLANK_IOCTL) {
        /* Fill the reply with a plausible vblank timestamp so callers
         * that inspect the result don't see stale request data. */
        if (arg) {
            /* union drm_wait_vblank: first 8 bytes are type+sequence (u32 each),
             * then tval_sec and tval_usec (long each). */
            struct {
                unsigned int type;
                unsigned int sequence;
                long         tval_sec;
                long         tval_usec;
            } *reply = arg;

            static unsigned int seq;
            struct timespec ts;
            clock_gettime(CLOCK_MONOTONIC, &ts);
            reply->type     = 0;
            reply->sequence = ++seq;
            reply->tval_sec  = ts.tv_sec;
            reply->tval_usec = ts.tv_nsec / 1000;
        }
        return 0;
    }

    return (int)syscall(SYS_ioctl, fd, req, arg);
}
