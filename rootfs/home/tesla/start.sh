#!/bin/bash

export DISPLAY=:0
export LD_LIBRARY_PATH=/usr/tesla/UI/lib:/lib
export MESA_LOADER_DRIVER_OVERRIDE=virtio_gpu
export EGL_PLATFORM=x11
export LIBGL_DRIVERS_PATH=/usr/lib/dri

# Create directories QtCar expects
mkdir -p /opt/games/run/i2v

# Start the UI in a restart loop.
# CarConfigChangeProcessRestarter kills QtCar on DV changes expecting a
# process supervisor to restart it. We emulate that here.
cd /usr/tesla/UI/bin || exit
while true; do
    echo "[start.sh] Starting QtCar..."
    ./QtCar --touch /dev/input/touch "$@"
    EXIT_CODE=$?
    # Exit code 137 = killed by signal (SIGKILL), 143 = SIGTERM
    if [ $EXIT_CODE -eq 137 ] || [ $EXIT_CODE -eq 143 ]; then
        echo "[start.sh] QtCar was killed (exit $EXIT_CODE), restarting in 2s..."
        sleep 2
    else
        echo "[start.sh] QtCar exited with code $EXIT_CODE, not restarting."
        break
    fi
done
