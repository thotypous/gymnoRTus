# generates a .spikes file from winCollect FIFO output
#
# based on rtuma's cli

from __future__ import division
import numpy as np
import sys, struct, itertools
import subprocess
import argparse
import common.cfg as cfg
from common.argp import ArgParser
from common.compat import where

# Constants
headerLen = 4 + 8 + 4 + 4
# Header format:
#  lastEventLen
#  offset on .spikes (i64)
#  samples
#  numChannels


def iter_fifo_windows(fifofile):
    bytes_per_size = cfg.WordsNeedForAllCh * cfg.WordBytes
    padded_nchan = cfg.WordsNeedForAllCh * cfg.SamplesPerWord
    nchan = cfg.EnabledCh
    
    bits = cfg.ADBits
    conv_ratio = cfg.VoltageScale / (1 << (bits - 1))
    
    first_ts = None
    
    while True:
        sizeref = fifofile.read(4)
        if sizeref == '':
            break
        size, ref = struct.unpack('HH', sizeref)
        ts, = struct.unpack('I', fifofile.read(4))
        if first_ts is None:
            first_ts = ts
        ts -= first_ts
        win = np.frombuffer(fifofile.read(bytes_per_size * size), dtype=np.int16)
        win = win.reshape((size, padded_nchan))[:,:nchan].copy().reshape((nchan*size,))
        win = np.array(win, dtype=np.float) * conv_ratio   # convert to voltage
        yield size, ref, ts, win


def check_window(window, nchan, winSize, onlyAbove, satLow, satHigh):
    listWin = [window[c:nchan*winSize:nchan] for c in xrange(nchan)]

    indexes_onlyabove = where(window > onlyAbove)
    indexes_satLow = where(window < satLow)
    indexes_satHigh = where(window > satHigh)

    chan_to_remove = set( x % nchan for x in itertools.chain(indexes_satLow, indexes_satHigh) )
    chan_to_include = set( x % nchan for x in indexes_onlyabove)

    final_chans = chan_to_include - chan_to_remove
    listWinDic = {}
    for c in final_chans:
        listWinDic.update({c: listWin[c]})

    return listWinDic


def main():
    description = 'Generates a .spikes file from winCollect FIFO output'
    parser = ArgParser(description=description, formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument('fifofile', type=argparse.FileType('r'), help='Input data (from winCollect FIFO)')
    parser.add_argument('outfile', type=argparse.FileType('w'), help='Output file (.spikes)')
    parser.add_argument('--fixedwin', help='Fixed window (use for single-fish data files)', action='store_true')
    parser.add_argument('--windowSize', type=int, default=cfg.SpikesWinSize, help='Window size, if --fixedwin')
    parser.add_argument('--afterRef', type=int, default=cfg.SpikesAfterRef, help='Samples after reference point, if --fixedwin')
    parser.add_argument('--saturation', type=str, help='high,low saturation level to filter out')
    parser.add_argument('--onlyabove', type=float, default=0.0, help='Only output spikes above this amplitude')
    parser.add_argument('--winlen', type=argparse.FileType('w'), help='Output original window lengths to a text file')

    args = parser.parse_args()
    
    fifofile = args.fifofile
    nchan = cfg.EnabledCh
    outfile = args.outfile

    fixedwin = args.fixedwin
    windowSize = args.windowSize
    afterRef = args.afterRef

    saturation = args.saturation
    satHigh = np.inf
    satLow = -np.inf
    if saturation is not None:
        satHigh = float(saturation.split(',')[0].strip())
        satLow = float(saturation.split(',')[1].strip())
    onlyAbove = args.onlyabove
    winlenFile = args.winlen
    
    afterRef += 1  # calc correction
    lastEventLen = 0

    for size, ref, ts, win in iter_fifo_windows(fifofile):
        if winlenFile:
            winlenFile.write('%d\n' % size)
        if fixedwin == True:
            samples = windowSize
            window = np.zeros((windowSize, nchan))
            win = win.reshape((size, nchan))
            # cut end
            if ref > afterRef:
                win = win[:-ref+afterRef,:]
                ref = afterRef
                size = win.shape[0]
            # cut start
            if size > windowSize:
                win = win[size-windowSize:,:]
                size = win.shape[0]
            # copy to fixed size window
            assert ref <= afterRef
            assert size <= windowSize
            endpos = windowSize - afterRef + ref
            startpos = endpos - size
            window[startpos:endpos,:] = win
            # fill any remaining samples with DC level
            for i in xrange(0, startpos):
                window[i,:] = window[startpos,:]
            for i in xrange(endpos, windowSize):
                window[i,:] = window[endpos-1,:]
            # make array plain once again
            window = window.reshape((windowSize*nchan,))
        else:
            samples = size
            window = win
        
        filtered_windowsDic = check_window(window, nchan, samples, onlyAbove, satLow, satHigh)
        offset = ts*nchan*np.dtype('float32').itemsize

        outfile.write(struct.pack('i', lastEventLen))
        outfile.write(struct.pack('q', offset))
        outfile.write(struct.pack('i', samples))
        outfile.write(struct.pack('i', len(filtered_windowsDic)))
        lastLengths = 0
        for c in sorted(filtered_windowsDic.keys()):
            outfile.write(struct.pack('i', c))
            buff = filtered_windowsDic[c].astype(np.dtype('float32')).tostring()
            outfile.write(buff)
            lastLengths = lastLengths + 4 + len(buff)

        lastEventLen = headerLen + lastLengths


if __name__ == '__main__':
    main()
