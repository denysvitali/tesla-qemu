#!/bin/bash

export DISPLAY=:0
export LD_LIBRARY_PATH=/usr/tesla/UI/lib:/lib

# Start the UI
pushd /usr/tesla/UI || exit
./bin/QtCar
popd || exit
