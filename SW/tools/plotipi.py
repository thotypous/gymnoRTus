# plotipi - meant for usage with the recog kernel module
from __future__ import division, print_function
import sys
import os
import atexit
import common.cfg as cfg
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import itertools

dev = os.open(cfg.RecogDev, os.O_RDONLY | os.O_NONBLOCK)
atexit.register(lambda: os.close(dev))

fig, ax = plt.subplots(subplot_kw={'axisbg': 'black'})

lineA, = ax.plot([], [], '.', c='#ff0000')
lineB, = ax.plot([], [], '.', c='#00ff00')
ax.axis([0, cfg.PlotIpiViewTime, 0, cfg.PlotIpiViewIpiScale])

ts_A = np.array([])
ts_B = np.array([])
ts_off = None
buf = b''

def animate(i):
    global buf, ts_off, ts_A, ts_B, lineA, lineB

    datum_size = 2*4
    try:
        buf += os.read(dev, datum_size*4096)
    except OSError:
        pass

    num_spk = len(buf) // datum_size
    usable_len = num_spk * datum_size
    buf_arr = np.frombuffer(buf[:usable_len], dtype=np.uint32).reshape((num_spk, 2))
    buf = buf[usable_len:]

    buf_ts = buf_arr[:,0].astype(np.float) * 1e3 / cfg.SamplingRate  # ms
    ts_A = np.concatenate((ts_A, buf_ts[buf_arr[:,1] == 1]))
    ts_B = np.concatenate((ts_B, buf_ts[buf_arr[:,1] == 2]))

    if ts_off is None:
        try:
            ts_off = min(itertools.chain(ts_A, ts_B))
        except ValueError:  # empty sequence
            ts_off = None
    elif max(itertools.chain(ts_A[-1:], ts_B[-1:])) - ts_off > cfg.PlotIpiViewTime * 1e3:
        ts_off += cfg.PlotIpiViewTime * 0.5e3
        ts_A = ts_A[ts_A >= ts_off]
        ts_B = ts_B[ts_B >= ts_off]

    lineA.set_data(1e-3 * (ts_A[1:] - ts_off), np.diff(ts_A))
    lineB.set_data(1e-3 * (ts_B[1:] - ts_off), np.diff(ts_B))

    return lineA, lineB

# Init only required for blitting to give a clean slate.
def init():
    return lineA, lineB

ani = animation.FuncAnimation(fig, animate, itertools.cycle([0]), init_func=init,
    interval=cfg.PlotIpiRenderInterval, blit=True)
plt.show()

