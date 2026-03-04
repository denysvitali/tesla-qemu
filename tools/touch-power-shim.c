/*
 * touch-power-shim: LD_PRELOAD shim that overrides
 * ManagedQtCarTouchDriver::isPowered() to always return true.
 *
 * In a real Tesla, POWER_touchState is set by the power manager when the
 * touchscreen hardware is powered on. In our QEMU VM there's no power
 * manager, so the touch driver never opens /dev/input/touch.
 *
 * We also override isDisplayOn() since it may gate the touch driver too.
 *
 * Build: gcc -shared -fPIC -o touch-power-shim.so touch-power-shim.c
 * Usage: LD_PRELOAD=/usr/local/lib/touch-power-shim.so ./QtCar ...
 */

/* ManagedQtCarTouchDriver::isPowered() -> _ZN23ManagedQtCarTouchDriver9isPoweredEv */
int _ZN23ManagedQtCarTouchDriver9isPoweredEv(void *this) {
    return 1;
}

/* ManagedQtCarTouchDriver::isDisplayOn() -> _ZN23ManagedQtCarTouchDriver11isDisplayOnEv */
int _ZN23ManagedQtCarTouchDriver11isDisplayOnEv(void *this) {
    return 1;
}
