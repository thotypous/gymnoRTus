# scope - meant for usage with the continuousAcq kernel module

import sys
import common.cfg as cfg
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import itertools

MaxSample = (1 << cfg.ADBits) - 1

ch_index = int(sys.argv[1])  # which channel to plot

dev = open('/dev/rtf0', 'rb')

fig, ax = plt.subplots(subplot_kw={'axisbg': 'black'})

maxTime = cfg.SamplesPerWord*cfg.ScopeViewWords/cfg.SamplingRate
totalSamples = cfg.SamplesPerWord*cfg.ScopeViewWords

x = np.linspace(0, maxTime, totalSamples)
line, = ax.plot(x, np.zeros(totalSamples), c='#00ff00', ls='-', marker='.', ms=2.5)
ax.axis([0, maxTime, 0, cfg.ScopeVoltageScale])

def animate(i):
    allCh = np.frombuffer(dev.read(cfg.TotalCh*cfg.WordBytes*cfg.ScopeViewWords), dtype=np.uint16)
    line.set_ydata(cfg.ScopeVoltageScale * np.array(allCh[ch_index::cfg.TotalCh], dtype=np.float) / MaxSample)
    return line,

# Init only required for blitting to give a clean slate.
def init():
    line.set_ydata(np.ma.array(np.zeros(totalSamples), mask=True))
    return line,

ani = animation.FuncAnimation(fig, animate, itertools.cycle([0]), init_func=init,
    interval=cfg.ScopeRenderInterval, blit=True)
plt.show()

