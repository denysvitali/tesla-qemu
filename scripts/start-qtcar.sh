#!/bin/bash
. /etc/tesla.env
. /etc/RunQtCar.env
. /etc/RunQtCar.vars 
export DISPLAY=:0
cd /usr/tesla/UI/bin
./QtCar $@