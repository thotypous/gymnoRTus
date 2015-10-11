from __future__ import division
import numpy as np
import sys
import os

EnabledChannels = 11
MockADChannels = 16
ADBits = 12
BufSize = 1024


def main():
    offset = (1 << (ADBits - 1)) - 1
    minval = 0
    maxval = (1 << ADBits) - 1

    fillbuf = np.zeros((BufSize, MockADChannels - EnabledChannels))

    infile = sys.argv[1]
    siglen = os.path.getsize(infile) // np.dtype(np.int16).itemsize // EnabledChannels
    inarr = np.memmap(infile, mode='r', dtype=np.int16, shape=(siglen, EnabledChannels))

    for i in xrange(0, siglen, BufSize):
        inbuf = inarr[i:i + BufSize, :]
        outbuf = np.clip(np.concatenate((inbuf, fillbuf), axis=1) + offset, minval, maxval)
        sys.stdout.write(outbuf.astype(np.int16).tostring())


if __name__ == '__main__':
    main()
