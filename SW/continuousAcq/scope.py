import sys
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import itertools

MaxSample = 0xfff
MaxVoltage = 2.5       # V
NumWords = 1280        # words
SamplesPerWord = 4     # samples
WordBytes = 8          # bytes
SamplingRate = 50.e3   # Hz
RenderInterval = 10    # ms

NumCh = 16             # number of channels
ChIndex = int(sys.argv[1])  # which channel to plot

dev = open('/dev/rtf0', 'rb')

fig, ax = plt.subplots(subplot_kw={'axisbg': 'black'})

maxTime = SamplesPerWord*NumWords/SamplingRate
totalSamples = SamplesPerWord*NumWords

x = np.linspace(0, maxTime, totalSamples)
line, = ax.plot(x, np.zeros(totalSamples), c='#00ff00', ls='-', marker='.', ms=2.5)
ax.axis([0, maxTime, 0, MaxVoltage])

def animate(i):
    allCh = np.frombuffer(dev.read(NumCh*WordBytes*NumWords), dtype=np.uint16)
    line.set_ydata(MaxVoltage * np.array(allCh[ChIndex::NumCh], dtype=np.float) / MaxSample)
    return line,

#Init only required for blitting to give a clean slate.
def init():
    line.set_ydata(np.ma.array(np.zeros(totalSamples), mask=True))
    return line,

ani = animation.FuncAnimation(fig, animate, itertools.cycle([0]), init_func=init,
    interval=RenderInterval, blit=True)
plt.show()

