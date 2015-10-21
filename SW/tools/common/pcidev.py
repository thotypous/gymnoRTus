import os
import glob
import numpy as np

import addrmap


def _readval(root, name):
    with open(os.path.join(root, name)) as f:
        return int(f.read(), 16)


def _writeval(root, name, value):
    with open(os.path.join(root, name), 'w') as f:
        f.write(str(value))


def find(vendor, device):
    for pci in glob.glob('/sys/devices/pci*'):
        for root, dirs, files in os.walk(pci):
            if len(set(files) & {'vendor', 'device'}) == 2:
                this_vendor = _readval(root, 'vendor')
                this_device = _readval(root, 'device')
                if this_vendor == vendor and this_device == device:
                    yield root


class PciDev(object):
    def __init__(self, vendor, device):
        root = list(find(vendor, device))
        assert(len(root) == 1)
        self.root = root[0]
        self._enable()
        self.bar = {}
    
    def _enable(self):
        if _readval(self.root, 'enable') == 0:
            _writeval(self.root, 'enable', 1)
        
    def map(self, bar):
        filename = os.path.join(self.root, 'resource%d' % bar)
        self.bar[bar] = np.memmap(filename, dtype=np.uint32, mode='r+')


class GymnortusPci(PciDev):
    def __init__(self):
        super(GymnortusPci, self).__init__(0x1172, 0x0de4)
        self.map(0)

    def setMocked(self, mocked):
        self.bar[0][addrmap.WMockADSetMocked] = 1 if mocked else 0

    def setOffset(self, ch, off):
        self.bar[0][addrmap.WSetOffset + ch] = off

    def resetTs(self):
        self.bar[0][addrmap.WResetTs] = 1
