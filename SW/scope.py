import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import itertools

MaxSample = 0xfff
MaxVoltage = 2.5       # V
SampleBits = 12        # bits
NumWords = 1024        # words
SamplesPerWord = 5     # samples
WordBytes = 8          # bytes
SamplingRate = 50.e3   # Hz
RenderInterval = 10    # ms

def getSamples(buf):
    return np.array([(long(x)>>(SampleBits*i))&MaxSample
                     for x in np.frombuffer(buf, dtype=np.uint64)
                     for i in xrange(SamplesPerWord)], dtype=np.float)

dev = open('/dev/rtf0', 'rb')

fig, ax = plt.subplots(subplot_kw={'axisbg': 'black'})

maxTime = SamplesPerWord*NumWords/SamplingRate
totalSamples = SamplesPerWord*NumWords

x = np.linspace(0, maxTime, totalSamples)
line, = ax.plot(x, np.zeros(totalSamples), c='#00ff00', ls='-', marker='.', ms=2.5)
ax.axis([0, maxTime, 0, MaxVoltage])

def animate(i):
    line.set_ydata(MaxVoltage*getSamples(dev.read(WordBytes*NumWords))/MaxSample)
    return line,

#Init only required for blitting to give a clean slate.
def init():
    line.set_ydata(np.ma.array(np.zeros(totalSamples), mask=True))
    return line,

ani = animation.FuncAnimation(fig, animate, itertools.cycle([0]), init_func=init,
    interval=RenderInterval, blit=True)
plt.show()

