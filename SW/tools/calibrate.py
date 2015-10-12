# calibrates DC offsets for the OffsetSubtractor

import os
import argparse
import subprocess
import numpy as np
import common.pcidev as pcidev
import common.path as path
import common.cfg as cfg
from common.argp import ArgParser


def middlescale():
    offset = (1 << (cfg.ADBits - 1)) - 1
    setOffsets(cfg.TotalCh * [offset])


def curroff():
    ko = os.path.join(path.sw, 'continuousAcq', 'gymnort_continuousacq.ko')
    assert subprocess.Popen(['insmod', ko]).wait() == 0
    
    samplesPerCh = int(cfg.CalibrateTime * cfg.SamplingRate)
    samples = cfg.TotalCh * samplesPerCh
    octets = samples * cfg.PaddedBits // 8
    
    with open(cfg.ContinuousAcqDev, 'rb') as dev:
        data = np.frombuffer(dev.read(octets), dtype=np.uint16)
        data = np.reshape(data, (samplesPerCh, cfg.TotalCh))

    assert subprocess.Popen(['rmmod', ko]).wait() == 0
    
    setOffsets(data.astype(np.float).mean(axis=0).round().astype(np.uint16))


def setOffsets(offsets):
    assert len(offsets) == cfg.TotalCh
    minvalue = 0
    maxvalue = (1 << cfg.ADBits) - 1
    dev = pcidev.GymnortusPci()
    for ch, offset in enumerate(offsets):
        print('ch %02d: offset = 0x%03x' % (ch, offset))
        assert offset >= minvalue
        assert offset <= maxvalue
        dev.setOffset(ch, offset)


def main():
    parser = ArgParser(
        description='Calibrates DC offsets for the OffsetSubtractor',
        formatter_class=argparse.RawDescriptionHelpFormatter)
    
    parser.add_argument('--middlescale', dest='action', action='store_const',
                        const=middlescale, default=parser.print_help,
                        help='Sets the offset to the middle of the scale')
    parser.add_argument('--curroff', dest='action', action='store_const',
                        const=curroff, default=parser.print_help,
                        help='Calibrates to the current measured offset')
    
    args = parser.parse_args()
    args.action()
    

if __name__ == '__main__':
    main()