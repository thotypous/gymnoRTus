# translates a model trained by gymnotools into C source code for compiling the recog module

from __future__ import division
import os
import sys
import re
import itertools
import numpy as np
import argparse
import common.cfg as cfg
from common.argp import ArgParser


def gen_filter(filename, filtered_features):
    assert all(idx >= cfg.DtcwptOffset for idx in filtered_features), \
           'FFT features are not yet supported in the RT module'
    in_size = int(np.log2(cfg.SpikesWinSize) + 1) * cfg.SpikesWinSize
    out_size = len(filtered_features)
    with HWriter(filename) as f:
        f.write('enum { NumFeatures = %d };\n\n' % out_size)
        f.write('static inline void filter_features(const float in[static %d], double out[static NumFeatures]) {\n' % in_size)
        for i, idx in enumerate(filtered_features):
            f.write('    out[%3d] = in[%4d];\n' % (i, idx - cfg.DtcwptOffset))
        f.write('}\n');


def gen_rescale(filename, rescale):
    minval = rescale[0,:]
    maxval = rescale[1,:]
    d = maxval - minval
    factor = 2./d
    offset = - minval - d/2.
    with HWriter(filename) as f:
        write_arr(f, 'rescaling_factor[NumFeatures]', factor)
        write_arr(f, 'rescaling_offset[NumFeatures]', offset)


def gen_svm(filename, svm):
    with HWriter(filename) as f:
        f.write('static const double svm_gamma = %.12e;\n\n' % svm.gamma)
        f.write('enum { svm_l = %d };\n\n' % svm.l);
        f.write('static const double svm_rho = %.12e;\n\n' % svm.rho)
        f.write('static const double svm_probA = %.12e;\n' % svm.probA)
        f.write('static const double svm_probB = %.12e;\n\n' % svm.probB)
        sv_coef_pad = np.concatenate((svm.sv_coef, np.zeros((4, ))))
        write_arr(f, 'svm_sv_coef[svm_l + 4]', sv_coef_pad)
        f.write('static const double svm_SV[svm_l][NumFeatures] ALIGNED(32) = {\n')
        for i in xrange(svm.l):
            f.write('    {' + ', '.join('%.12e'%x for x in svm.SV[i,:]) + '}, \n')
        f.write('};\n')


def gen_cfg(filename):
    with HWriter(filename) as f:
        f.write('enum { WaveletInSize = %d };\n' % cfg.SpikesWinSize)
        f.write('enum { Log2WaveletInSize = %d };\n' % int(np.log2(cfg.SpikesWinSize)))
        f.write('enum { NumChannels = %d };\n' % cfg.EnabledCh)
        f.write('enum { PaddedChannels = %d };\n' % (cfg.WordsNeedForAllCh*cfg.WordBytes*8//cfg.PaddedBits))
        f.write('enum { AfterRef = %d + 1 };\n' % cfg.SpikesAfterRef)
        f.write('enum { WaveletOutSize = (Log2WaveletInSize + 1) * WaveletInSize };\n')


def write_arr(f, name, contents):
    f.write('static const double %s ALIGNED(32) = {\n' % name)
    f.write('    ' + ', '.join('%.12e'%x for x in contents) + '\n')
    f.write('};\n\n')


class SVMModel(object):
    def __init__(self, f):
        self._read_header(f)
        self._read_contents(f)

    def _read_header(self, f):
        for line in f.xreadlines():
            a = line.strip().split()
            if a[0] == 'svm_type':
                assert a[1] == 'c_svc', 'svm_type not supported'
            elif a[0] == 'kernel_type':
                assert a[1] == 'rbf', 'kernel_type not supported'
            elif a[0] == 'gamma':
                self.gamma = float(a[1])
            elif a[0] == 'nr_class':
                assert a[1] == '2', 'only binary SVM is supported'
            elif a[0] == 'total_sv':
                self.l = int(a[1])
            elif a[0] == 'rho':
                self.rho = float(a[1])
            elif a[0] == 'label':
                pass
            elif a[0] == 'probA':
                self.probA = float(a[1])
            elif a[0] == 'probB':
                self.probB = float(a[1])
            elif a[0] == 'nr_sv':
                pass
            elif a[0] == 'SV':
                break
            else:
                raise SyntaxError('Invalid input')

    def _read_contents(self, f):
        lines = list(f.xreadlines())

        min_idx, max_idx = np.inf, 0
        for line in lines:
            iter_idx = lambda: (int(m.group(1))+1 for m in re.finditer(r'\s(\d+):', line))
            max_idx = max(itertools.chain([max_idx], iter_idx()))
            min_idx = min(itertools.chain([min_idx], iter_idx()))
        self.elements = max_idx - min_idx + 1

        self.sv_coef = np.zeros((self.l,))
        self.SV = np.zeros((self.l, self.elements))

        for i, line in enumerate(lines):
            a = line.strip().split()
            self.sv_coef[i] = float(a[0])
            for col, val in (c.split(':',1) for c in a[1:]):
                col = int(col)
                val = float(val)
                self.SV[i,col] = val

    def __repr__(self):
        return '<SVMModel l=%d gamma=%f probA=%f probB=%f>' % \
               (self.l, self.gamma, self.probA, self.probB)


class HWriter(file):
    def __init__(self, filename):
        file.__init__(self, filename, 'w')
    def __enter__(self):
        name = 'GYMNORTUS_' + re.sub(r'[^A-Z]', '_', self.name.upper())
        self.write('#ifndef %s\n' % name)
        self.write('#define %s\n' % name)
        self.write('// Autogenerated by %s\n\n' % sys.argv[0])
        return self
    def __exit__(self, type, value, traceback):
        self.write('\n#endif\n')
        self.close()


def main():
    description = 'Translates a model trained by gymnotools into C source code for compiling the recog module'
    parser = ArgParser(description=description, formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument('--filter', required=True, type=argparse.FileType('r'), help='Feature filter')
    parser.add_argument('--rescale', required=True, type=argparse.FileType('rb'), help='Rescaling factors')
    parser.add_argument('--svm', required=True, type=argparse.FileType('r'), help='SVM model')

    args = parser.parse_args()

    filtered_features = map(int, args.filter.xreadlines())

    rescale_num_features = os.fstat(args.rescale.fileno()).st_size // np.dtype(np.float32).itemsize // 2
    rescale = np.memmap(args.rescale, mode='r', dtype=np.float32, shape=(2, rescale_num_features))
    rescale = np.array(rescale)

    if rescale.shape[1] != len(filtered_features):
        rescale = rescale[:, filtered_features]

    svm = SVMModel(args.svm)
    assert svm.elements == rescale.shape[1], 'SVM model trained for an incorrect number of features'

    gen_filter('feature_filter.h', filtered_features)
    gen_rescale('rescaling_factors.h', rescale)
    gen_svm('svm_model.h', svm)
    gen_cfg('generated_cfg.h')


if __name__ == '__main__':
    main()
