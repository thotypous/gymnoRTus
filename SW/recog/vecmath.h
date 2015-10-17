#ifndef GYMNORTUS_VECMATH_H
#define GYMNORTUS_VECMATH_H

#include <immintrin.h>
#include <stdint.h>

#define ALIGN(N) __attribute__((aligned(N)))

typedef float   ALIGN(32) afloat;
typedef double  ALIGN(32) adouble;
typedef int16_t ALIGN(32) aint16;

#define VEC4(x) { (x), (x), (x), (x) }
#define VEC8(x) { (x), (x), (x), (x), (x), (x), (x), (x) }

static inline __m256 max_float8_arr(afloat *arr, const int sz) {
    __m256 *a = (__m256*)arr;
    __m256 max8={};
    for (int i = 0; i < sz/8; i++)
        max8 = _mm256_max_ps(max8, a[i]);
    // reduce max
    __m128 max4 = _mm_max_ps(_mm256_extractf128_ps(max8, 1), _mm256_castps256_ps128(max8));
    __m128 max2 = _mm_max_ps(max4, _mm_permute_ps(max4, 0xb1)); //'b10_11_00_01
    __m128 max1 = _mm_max_ps(max2, _mm_permute_ps(max2, 0x4e)); //'b01_00_11_10
    // replicate max
    return _mm256_insertf128_ps(_mm256_castps128_ps256(max1), max1, 1);
}

static inline void norm_float8_arr(afloat *arr, const int sz) {
    __m256 *a = (__m256*)arr;
    __m256 max  = max_float8_arr(arr, sz);
    for (int i = 0; i < sz/8; i++)
       a[i] /= max;
}

// a *= b
static inline void mult_double4_arr(adouble *a, const adouble *b, const int sz) {
    __m256d* a4 = (__m256d*)a;
    const __m256d* b4 = (__m256d*)b;
    int i;
    for (i=0; i<sz/4; i++)
        a4[i] *= b4[i];
    for (i*=4; i<sz; i++)
        a[i] *= b[i];
}

// a += b
static inline void add_double4_arr(adouble *a, const adouble *b, const int sz) {
    __m256d* a4 = (__m256d*)a;
    const __m256d* b4 = (__m256d*)b;
    int i;
    for (i=0; i<sz/4; i++)
        a4[i] += b4[i];
    for (i*=4; i<sz; i++)
        a[i] += b[i];
}

// |a-b|^2
static inline double normsq_double4_arr(const adouble *a, const adouble *b, const int sz) {
    const __m256d* a4 = (__m256d*)a;
    const __m256d* b4 = (__m256d*)b;
    int i;
    __m256d sum4={};
    for (i=0; i<sz/4; i++) {
        const __m256d dist = a4[i] - b4[i];
        sum4 += dist*dist;
    }
    double sum = sum4[0] + sum4[1] + sum4[2] + sum4[3];
    for (i*=4; i<sz; i++) {
        const double dist = a[i] - b[i];
        sum += dist*dist;
    }
    return sum;
}

// based on https://root.cern.ch
static inline __m256d ldexp_double4(__m256d v, __m256i _e) {
#if defined(__AVX2__)
    const __m256i exponentBits = _mm256_slli_epi64(_e, 52);
    return _mm256_castsi256_pd(_mm256_add_epi64(_mm256_castpd_si256(v), exponentBits));
#else // only __AVX__
    const __m128i eLo = _mm_slli_epi64(_mm256_castsi256_si128(_e), 52);
    const __m128i eHi = _mm_slli_epi64(_mm_castpd_si128(_mm256_extractf128_pd(_mm256_castsi256_pd(_e), 1)), 52);
    const __m128d vLo = _mm256_castpd256_pd128(v);
    const __m128d vHi = _mm256_extractf128_pd(v, 1);
    const __m128d rLo = _mm_castsi128_pd(_mm_add_epi64(_mm_castpd_si128(vLo), eLo));
    const __m128d rHi = _mm_castsi128_pd(_mm_add_epi64(_mm_castpd_si128(vHi), eHi));
    return _mm256_insertf128_pd(_mm256_castpd128_pd256(rLo), rHi, 1);
#endif
}

// based on https://root.cern.ch
// and http://software-lisc.fbk.eu/avx_mathfun
static inline __m256d exp_double4(__m256d x) {
    static const __m256d log2_e = VEC4(1.44269504088896341);
    static const __m256d ln2_large = VEC4(6.9314575195312500e-01);
    static const __m256d ln2_small = VEC4(1.4286068203094173e-06);
    static const __m256d exp_hi = VEC4( 7.0839641853226408e+02);
    static const __m256d exp_lo = VEC4(-7.0839641853226408e+02);
    x = _mm256_min_pd(x, exp_hi);
    x = _mm256_max_pd(x, exp_lo);
    __m256d px = _mm256_floor_pd(log2_e * x + 0.5);
    __m128i tmp = _mm256_cvttpd_epi32(px);
    __m256i n = _mm256_castps_si256(_mm256_insertf128_ps(
            _mm256_castps128_ps256(_mm_castsi128_ps(_mm_unpacklo_epi32(tmp, tmp))),
            _mm_castsi128_ps(_mm_unpackhi_epi32(tmp, tmp)), 1));
    x -= px * ln2_large;
    x -= px * ln2_small;
    static const double P[] = {
        1.2617719307481058e-04,
        3.0299440770744195e-02,
        1.0000000000000000e+00,
    };
    static const double Q[] = {
        3.0019850513866446e-06,
        2.5244834034968411e-03,
        2.2726554820815503e-01,
        2.0000000000000000e+00,
    };
    const __m256d x2 = x * x;
    px = x * ((P[0] * x2 + P[1]) * x2 + P[2]);
    x =  px / ((((Q[0] * x2 + Q[1]) * x2 + Q[2]) * x2 + Q[3]) - px);
    x = 1.0 + 2.0 * x;
    return ldexp_double4(x, n);
}

// avoids the need for rtai_math just because of a single scalar math func
static inline double scalar_exp(const double x) {
    const __m256d x4 = VEC4(x);
    return exp_double4(x4)[0];
}

#endif
