#ifndef GYMNORTUS_WINDOW_H
#define GYMNORTUS_WINDOW_H

#include "cfg.h"
#include "vecmath.h"
#include "wavelet.h"

static inline void prepare_window(const aint16 *in, int size, int ref, float out[restrict static NumChannels][WaveletOutSize]) {
    // cut end
    int in_start = 0, in_end = size - 1;
    if (ref > AfterRef) {
        in_end -= ref - AfterRef;
        ref = AfterRef;
    }
    // cut start
    if (in_end > WaveletInSize)
        in_start = in_end - WaveletInSize;
    // calculate new size and output offset
    size = in_end - in_start + 1;
    const int out_start = WaveletInSize - AfterRef + ref - size;
    // copy to fixed size window
    for (int i=0, j=PaddedChannels*in_start; i<size; i++, j+=PaddedChannels)
        for (int ch = 0; ch < NumChannels; ch++)
            out[ch][out_start+i] = in[j+ch];
    // fill any remaining amples with DC level
    const int out_end = out_start+size-1;
    for (int ch = 0; ch < NumChannels; ch++) {
        const float dc_start = out[ch][out_start];
        for (int i = 0; i < out_start; i++)
            out[ch][i] = dc_start;
        const float dc_end = out[ch][out_end];
        for (int i = out_end+1; i < WaveletInSize; i++)
            out[ch][i] = dc_end;
    }
}

#endif
