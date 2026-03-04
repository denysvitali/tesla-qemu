/*
 * touch-proxy: Translates QEMU usb-tablet events into multitouch events
 * that QtCar's TouchDriver expects.
 *
 * QEMU usb-tablet provides: BTN_LEFT + ABS_X/ABS_Y
 * QtCar expects:            BTN_TOUCH + ABS_MT_POSITION_X/Y (multitouch)
 *
 * This program:
 *  1. Auto-detects the QEMU input device by scanning /dev/input/event*
 *  2. Creates a uinput virtual touchscreen with multitouch capabilities
 *  3. Translates events in a loop
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <sys/ioctl.h>

/* QEMU usb-tablet reports coordinates in 0..32767 range */
#define TABLET_MAX 32767
/* Output touchscreen resolution (matches QEMU display) */
#define TOUCH_X_MAX 1200
#define TOUCH_Y_MAX 1920

/* How long to wait for /dev/input and a tablet device to appear */
#define RETRY_MAX     30
#define RETRY_DELAY_S  1

static int try_find_tablet(void)
{
    DIR *dir;
    struct dirent *ent;
    char path[64];
    int fd;
    unsigned long evbits[2] = {0};
    unsigned long absbits[2] = {0};
    char name[256] = {0};

    dir = opendir("/dev/input");
    if (!dir)
        return -1;

    while ((ent = readdir(dir)) != NULL) {
        if (strncmp(ent->d_name, "event", 5) != 0)
            continue;

        snprintf(path, sizeof(path), "/dev/input/%s", ent->d_name);
        fd = open(path, O_RDONLY);
        if (fd < 0)
            continue;

        /* Check if device has absolute axes */
        if (ioctl(fd, EVIOCGBIT(0, sizeof(evbits)), evbits) < 0) {
            close(fd);
            continue;
        }

        /* Must have EV_ABS */
        if (!(evbits[0] & (1 << EV_ABS))) {
            close(fd);
            continue;
        }

        /* Check for ABS_X and ABS_Y */
        if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(absbits)), absbits) < 0) {
            close(fd);
            continue;
        }

        if ((absbits[0] & (1 << ABS_X)) && (absbits[0] & (1 << ABS_Y))) {
            ioctl(fd, EVIOCGNAME(sizeof(name)), name);
            fprintf(stderr, "touch-proxy: found tablet device: %s (%s)\n",
                    path, name);
            closedir(dir);
            return fd;
        }

        close(fd);
    }

    closedir(dir);
    return -1;
}

static int find_tablet_device(void)
{
    int fd, i;

    for (i = 0; i < RETRY_MAX; i++) {
        fd = try_find_tablet();
        if (fd >= 0)
            return fd;
        if (i == 0)
            fprintf(stderr, "touch-proxy: waiting for tablet device...\n");
        sleep(RETRY_DELAY_S);
    }

    fprintf(stderr, "touch-proxy: no tablet device found after %ds\n",
            RETRY_MAX * RETRY_DELAY_S);
    return -1;
}

static int create_uinput_device(void)
{
    int fd;
    struct uinput_setup setup;
    struct uinput_abs_setup abs_setup;

    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        perror("open /dev/uinput");
        return -1;
    }

    /* Enable event types */
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_EVBIT, EV_SYN);

    /* Enable BTN_TOUCH */
    ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH);

    /* Setup absolute axes */
    /* ABS_MT_SLOT */
    memset(&abs_setup, 0, sizeof(abs_setup));
    abs_setup.code = ABS_MT_SLOT;
    abs_setup.absinfo.minimum = 0;
    abs_setup.absinfo.maximum = 0; /* single touch slot */
    ioctl(fd, UI_ABS_SETUP, &abs_setup);

    /* ABS_MT_TRACKING_ID */
    memset(&abs_setup, 0, sizeof(abs_setup));
    abs_setup.code = ABS_MT_TRACKING_ID;
    abs_setup.absinfo.minimum = 0;
    abs_setup.absinfo.maximum = 65535;
    ioctl(fd, UI_ABS_SETUP, &abs_setup);

    /* ABS_MT_POSITION_X */
    memset(&abs_setup, 0, sizeof(abs_setup));
    abs_setup.code = ABS_MT_POSITION_X;
    abs_setup.absinfo.minimum = 0;
    abs_setup.absinfo.maximum = TOUCH_X_MAX;
    ioctl(fd, UI_ABS_SETUP, &abs_setup);

    /* ABS_MT_POSITION_Y */
    memset(&abs_setup, 0, sizeof(abs_setup));
    abs_setup.code = ABS_MT_POSITION_Y;
    abs_setup.absinfo.minimum = 0;
    abs_setup.absinfo.maximum = TOUCH_Y_MAX;
    ioctl(fd, UI_ABS_SETUP, &abs_setup);

    /* ABS_X / ABS_Y (single-touch, some drivers also read these) */
    memset(&abs_setup, 0, sizeof(abs_setup));
    abs_setup.code = ABS_X;
    abs_setup.absinfo.minimum = 0;
    abs_setup.absinfo.maximum = TOUCH_X_MAX;
    ioctl(fd, UI_ABS_SETUP, &abs_setup);

    memset(&abs_setup, 0, sizeof(abs_setup));
    abs_setup.code = ABS_Y;
    abs_setup.absinfo.minimum = 0;
    abs_setup.absinfo.maximum = TOUCH_Y_MAX;
    ioctl(fd, UI_ABS_SETUP, &abs_setup);

    /* Device identity */
    memset(&setup, 0, sizeof(setup));
    snprintf(setup.name, UINPUT_MAX_NAME_SIZE, "Tesla Touch Proxy");
    setup.id.bustype = BUS_VIRTUAL;
    setup.id.vendor = 0x1234;
    setup.id.product = 0x5678;
    setup.id.version = 1;

    if (ioctl(fd, UI_DEV_SETUP, &setup) < 0) {
        perror("UI_DEV_SETUP");
        close(fd);
        return -1;
    }

    if (ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("UI_DEV_CREATE");
        close(fd);
        return -1;
    }

    fprintf(stderr, "touch-proxy: created uinput device 'Tesla Touch Proxy'\n");
    return fd;
}

static void emit(int fd, unsigned short type, unsigned short code, int value)
{
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = type;
    ev.code = code;
    ev.value = value;
    write(fd, &ev, sizeof(ev));
}

static inline int scale(int value, int in_max, int out_max)
{
    return (int)((long)value * out_max / in_max);
}

int main(void)
{
    int in_fd, out_fd;
    struct input_event ev;
    int tracking_id = 0;
    int touch_active = 0;
    int cur_x = 0, cur_y = 0;

    in_fd = find_tablet_device();
    if (in_fd < 0) {
        fprintf(stderr, "touch-proxy: no tablet device found\n");
        return 1;
    }

    out_fd = create_uinput_device();
    if (out_fd < 0) {
        close(in_fd);
        return 1;
    }

    /* Don't grab the device — let Xorg also see the tablet events so
     * Qt/X11 mouse input works. The proxy creates a parallel multitouch
     * device on /dev/input/touch for QtCar's TouchDriver (if it loads). */

    fprintf(stderr, "touch-proxy: running event loop\n");

    while (read(in_fd, &ev, sizeof(ev)) == sizeof(ev)) {
        switch (ev.type) {
        case EV_KEY:
            if (ev.code == BTN_LEFT || ev.code == BTN_TOUCH) {
                if (ev.value && !touch_active) {
                    /* Touch down */
                    touch_active = 1;
                    emit(out_fd, EV_ABS, ABS_MT_SLOT, 0);
                    emit(out_fd, EV_ABS, ABS_MT_TRACKING_ID, tracking_id++);
                    emit(out_fd, EV_ABS, ABS_MT_POSITION_X, cur_x);
                    emit(out_fd, EV_ABS, ABS_MT_POSITION_Y, cur_y);
                    emit(out_fd, EV_ABS, ABS_X, cur_x);
                    emit(out_fd, EV_ABS, ABS_Y, cur_y);
                    emit(out_fd, EV_KEY, BTN_TOUCH, 1);
                } else if (!ev.value && touch_active) {
                    /* Touch up */
                    touch_active = 0;
                    emit(out_fd, EV_ABS, ABS_MT_TRACKING_ID, -1);
                    emit(out_fd, EV_KEY, BTN_TOUCH, 0);
                }
            }
            break;

        case EV_ABS:
            if (ev.code == ABS_X) {
                cur_x = scale(ev.value, TABLET_MAX, TOUCH_X_MAX);
                if (touch_active) {
                    emit(out_fd, EV_ABS, ABS_MT_POSITION_X, cur_x);
                    emit(out_fd, EV_ABS, ABS_X, cur_x);
                }
            } else if (ev.code == ABS_Y) {
                cur_y = scale(ev.value, TABLET_MAX, TOUCH_Y_MAX);
                if (touch_active) {
                    emit(out_fd, EV_ABS, ABS_MT_POSITION_Y, cur_y);
                    emit(out_fd, EV_ABS, ABS_Y, cur_y);
                }
            }
            break;

        case EV_SYN:
            if (ev.code == SYN_REPORT)
                emit(out_fd, EV_SYN, SYN_REPORT, 0);
            break;
        }
    }

    ioctl(out_fd, UI_DEV_DESTROY);
    close(in_fd);
    close(out_fd);
    return 0;
}
