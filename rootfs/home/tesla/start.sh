#!/bin/bash

export DISPLAY=:0
export LD_LIBRARY_PATH=/usr/tesla/UI/lib:/lib
export MESA_LOADER_DRIVER_OVERRIDE=virtio_gpu_dri

# Start the UI
pushd /usr/tesla/UI/bin || exit
./QtCar $@
popd || exit
