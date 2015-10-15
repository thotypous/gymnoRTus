#ifndef GYMNORTUS_WAVELET_H
#define GYMNORTUS_WAVELET_H

#include "cfg.h"
#include "vecmath.h"

static const float daub7_h[] ALIGN(32) = {
     0.077852054085062,  0.396539319482306,  0.729132090846555,  0.469782287405359, -0.143906003929106,
    -0.224036184994166,  0.071309219267050,  0.080612609151066, -0.038029936935035, -0.016574541631016,
     0.012550998556014,  0.000429577973005, -0.001801640704000,  0.000353713800001,
};
static const float daub7_g[] ALIGN(32) = {
     0.000353713800001,  0.001801640704000,  0.000429577973005, -0.012550998556014, -0.016574541631016,
     0.038029936935035,  0.080612609151066, -0.071309219267050, -0.224036184994166,  0.143906003929106,
     0.469782287405359, -0.729132090846555,  0.396539319482306, -0.077852054085062,
};
static const float qshf1_h[] ALIGN(32) = {
     0.002609700261841,  0.000162258390311,  0.001119301593802, -0.009664912468810,  0.005899523559559,
     0.045354650419414, -0.054114477755699, -0.112198503754835,  0.280910663006716,  0.753010936948491,
     0.565293214806365,  0.025430612869708, -0.121306068933115,  0.016053537034447,  0.032097264389903,
    -0.010668398638807, -0.005492754446412,  0.001081141079834,  0.000090433585293, -0.001454525937692,
};
static const float qshf1_g[] ALIGN(32) = {
    -0.001454525937692, -0.000090433585293,  0.001081141079834,  0.005492754446412, -0.010668398638807,
    -0.032097264389903,  0.016053537034447,  0.121306068933115,  0.025430612869708, -0.565293214806365,
     0.753010936948491, -0.280910663006716, -0.112198503754835,  0.054114477755699,  0.045354650419414,
    -0.005899523559559, -0.009664912468810, -0.001119301593802,  0.000162258390311, -0.002609700261841,
};
static const float qshf2_h[] ALIGN(32) = {
    -0.001454525937692,  0.000090433585293,  0.001081141079834, -0.005492754446412, -0.010668398638807,
     0.032097264389903,  0.016053537034447, -0.121306068933115,  0.025430612869708,  0.565293214806365,
     0.753010936948491,  0.280910663006716, -0.112198503754835, -0.054114477755699,  0.045354650419414,
     0.005899523559559, -0.009664912468810,  0.001119301593802,  0.000162258390311,  0.002609700261841,
};
static const float qshf2_g[] ALIGN(32) = {
    -0.002609700261841,  0.000162258390311, -0.001119301593802, -0.009664912468810, -0.005899523559559,
     0.045354650419414,  0.054114477755699, -0.112198503754835, -0.280910663006716,  0.753010936948491,
    -0.565293214806365,  0.025430612869708,  0.121306068933115,  0.016053537034447, -0.032097264389903,
    -0.010668398638807,  0.005492754446412,  0.001081141079834, -0.000090433585293, -0.001454525937692,
};

typedef struct {
    int n, off;
    const afloat *h, *g;
} wavelet_filt;

static const wavelet_filt daub7  = { 14,  7, daub7_h, daub7_g };
static const wavelet_filt daub7s = { 14,  8, daub7_h, daub7_g };
static const wavelet_filt qshf1  = { 20, 10, qshf1_h, qshf1_g };
static const wavelet_filt qshf2  = { 20, 10, qshf2_h, qshf2_g };

typedef struct {
    const wavelet_filt *first;  // First stage filters
    const wavelet_filt *cwt;    // CWT-specific filters (e.g. q-shift filters)
    const wavelet_filt *f;      // Filters for branches already satisfying Hilbert conditions
} cwpt_filt;

static const cwpt_filt tree1_filt = { &daub7,  &qshf1, &daub7 };
static const cwpt_filt tree2_filt = { &daub7s, &qshf2, &daub7 };

static inline void afb(const wavelet_filt *filt, const float *restrict in, unsigned int n, float *restrict hout, float *restrict gout) {
    const int ncoef = filt->n;
    const afloat *h = filt->h, *g = filt->g;
    const int off = filt->off;

    const int n1 = n - 1;  // n = 2^i => x%n == x&(n-1)
    float ALIGN(32) extin[256];
    //BUG_ON(off + n + ncoef > ARRAY_SIZE(extin));
    for (int i = 0; i < off + n + ncoef; i++)
        extin[i] = in[i & n1];

    float ALIGN(32) _hout[n/2];
    float ALIGN(32) _gout[n/2];

    __builtin_memset(_hout, 0, sizeof(_hout));
    __builtin_memset(_gout, 0, sizeof(_gout));

    for (int ii=0,i=0; i<n; i+=2,ii++) {
        const int ni = off + i;
        for(int k = 0; k < ncoef; k++) {
            const float ai = extin[ni + k];
            _hout[ii] += h[k]*ai;
            _gout[ii] += g[k]*ai;
        }
    }

    __builtin_memcpy(hout, _hout, sizeof(_hout));
    __builtin_memcpy(gout, _gout, sizeof(_gout));
}

static void cwpt_fulltree(const cwpt_filt *filt, afloat *restrict arr, unsigned int n) {
    const unsigned int n2 = n>>1;
    unsigned int m = n2, off = n<<1;

    // First stage
    afb(filt->first, &arr[0], n, &arr[n], &arr[n+m]);

    // Second stage
    afb(filt->cwt, &arr[n  ], m, &arr[off         ], &arr[off+(m>>1)]);
    afb(filt->cwt, &arr[n+m], m, &arr[off+m+(m>>1)], &arr[off+ m    ]);

    // Next stages
    for (m >>= 1; m > 1; m >>= 1) {
        // Process each node
        for (int i=0,j=0; i<n; i+=m,off+=m,j++) {
            // Choose the adequate filter pair
            const wavelet_filt *wf = (i==0 || i==n2) ? filt->cwt : filt->f;
            // Swap the outputs if the parent node was the result of a
            // high-pass filtering.
            const int m2 = m>>1;
            float *hout = (j&1)==0 ? &arr[off+n ] : &arr[off+n+m2];
            float *gout = (j&1)==0 ? &arr[off+n+m2] : &arr[off+n ];
            // Filter and store in two children nodes
            afb(wf, &arr[off], m, hout, gout);
        }
    }
}

static inline void dtcwpt_normed_fulltree(float tree1[static WaveletOutSize]) {
    float ALIGN(32) tree2[WaveletOutSize];
    __builtin_memcpy(tree2, tree1, WaveletInSize*sizeof(tree1[0]));

    cwpt_fulltree(&tree1_filt, tree1, WaveletInSize);
    cwpt_fulltree(&tree2_filt, tree2, WaveletInSize);

    __m256 *a = (__m256*)tree1, *b = (__m256*)tree2;
    __m256 max8={};

    for (int i = 0; i < WaveletOutSize/8; i++) {
        a[i] = _mm256_sqrt_ps(a[i]*a[i] + b[i]*b[i]);
        max8 = _mm256_max_ps(max8, a[i]);
    }

    for (int i = 0; i < Log2WaveletInSize + 1; i++)
        norm_float8_arr(&tree1[WaveletInSize*i], WaveletInSize);
}

#endif
