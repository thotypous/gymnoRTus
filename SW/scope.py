import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import itertools

def getSamples(buf):
    return np.array([(long(x)>>(12*i))&0xfff
                     for x in np.frombuffer(buf, dtype=np.uint64)
                     for i in xrange(5)], dtype=np.float)

dev = open('/dev/rtf0', 'rb')

fig, ax = plt.subplots()

x = np.linspace(0, 1, 5*1024)
line, = ax.plot(x, np.zeros(5*1024), 'k.-')
ax.axis([0, 1, 0, 2.5])

def animate(i):
    line.set_ydata(2.5*getSamples(dev.read(8*1024))/0xfff)
    return line,

#Init only required for blitting to give a clean slate.
def init():
    line.set_ydata(np.ma.array(np.zeros(5*1024), mask=True))
    return line,

ani = animation.FuncAnimation(fig, animate, itertools.cycle([0]), init_func=init,
    interval=50, blit=True)
plt.show()

