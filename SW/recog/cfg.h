#ifndef GYMNORTUS_CFG_H
#define GYMNORTUS_CFG_H

enum { WaveletInSize = 128 };
enum { Log2WaveletInSize = 7 };

// Derived values
enum { WaveletOutSize = (Log2WaveletInSize + 1) * WaveletInSize };

#endif
