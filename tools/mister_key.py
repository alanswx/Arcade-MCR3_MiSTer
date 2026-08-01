#!/usr/bin/env python3
"""Inject keystrokes into MiSTer via a uinput virtual keyboard.

mrext's REST API has no input endpoint (every guess falls through to the SPA
catch-all), so this is how the bench gets driven remotely. MiSTer reads
/dev/input/event* and hot-plugs new devices, so a uinput keyboard is seen as
a real one and follows the standard MiSTer arcade key defaults:
    5 = Coin 1,  6 = Coin 2,  1 = Start 1,  2 = Start 2,
    arrows = stick,  LCtrl/LAlt/Space = buttons 1-3.

Usage:  mister_key.py 5 1            # coin, then start
        mister_key.py --hold 0.5 up  # hold a key longer
"""
import fcntl, os, struct, sys, time

UINPUT = "/dev/uinput"
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
EV_SYN, EV_KEY = 0x00, 0x01

KEYS = {
    "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10,
    "0": 11, "esc": 1, "enter": 28, "space": 57, "lctrl": 29, "lalt": 56,
    "lshift": 42, "tab": 15, "up": 103, "down": 108, "left": 105, "right": 106,
    "f12": 88, "f1": 59, "a": 30, "s": 31, "d": 32, "w": 17,
}


def emit(fd, typ, code, val):
    # input_event on armv7l: struct timeval (two longs) + u16 + u16 + s32
    os.write(fd, struct.pack("llHHi", 0, 0, typ, code, val))


def syn(fd):
    emit(fd, EV_SYN, 0, 0)


def main():
    args = sys.argv[1:]
    hold = 0.08
    if args and args[0] == "--hold":
        hold = float(args[1])
        args = args[2:]
    if not args:
        print(__doc__)
        return 1

    fd = os.open(UINPUT, os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for code in KEYS.values():
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)

    # struct uinput_user_dev: name[80] + input_id(4*u16) + ff_effects_max +
    # 4 * abs arrays of 64 s32 each
    dev = struct.pack("80sHHHHi", b"mrext-virtual-kbd", 0x03, 0x1234, 0x5678, 1, 0)
    dev += b"\x00" * (64 * 4 * 4)
    os.write(fd, dev)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(3.0)          # let MiSTer notice the new device (a fresh core
                             # load needs longer than 1s - it re-scans inputs)

    for name in args:
        code = KEYS.get(name.lower())
        if code is None:
            print(f"unknown key {name!r}")
            continue
        emit(fd, EV_KEY, code, 1); syn(fd)
        time.sleep(hold)
        emit(fd, EV_KEY, code, 0); syn(fd)
        print(f"pressed {name}")
        time.sleep(0.35)

    time.sleep(0.3)
    fcntl.ioctl(fd, UI_DEV_DESTROY)
    os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
