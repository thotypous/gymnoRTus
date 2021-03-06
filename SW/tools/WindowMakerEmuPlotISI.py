# plots ISI computed from windows generated by WindowMakerEmu.bsim

import sys
import struct
import re
import numpy as np
import matplotlib.pyplot as plt
import common.cfg as cfg


def iterwins():
    for line in sys.stdin.xreadlines():
        m = re.search(r"timestamp: 'h([0-9a-f]+), size: 'h([0-9a-f]+), reference: 'h([0-9a-f]+)", line)
        if m:
            ts, size, ref = tuple(int(x,16) for x in m.groups())
            yield ts, size, ref


def main():
    arrts = np.array([ts - ref for ts, size, ref in iterwins()], dtype=np.float)
    arrts -= arrts[0]
    arrts /= cfg.SamplingRate
    plt.plot(arrts[1:], np.diff(arrts), 'k.-')
    plt.show()


if __name__ == '__main__':
    main()
