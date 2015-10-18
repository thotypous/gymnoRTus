#ifndef GYMNORTUS_SVM_H
#define GYMNORTUS_SVM_H

#include "vecmath.h"
#include "wavelet.h"
#include "feature_filter.h"
#include "rescaling_factors.h"
#include "svm_model.h"

static inline void svm_prepare_features(float dtcwpt[static WaveletOutSize], double features[static NumFeatures]) {
    filter_features(dtcwpt, features);
    add_double4_arr(features, rescaling_offset, NumFeatures);
    mult_double4_arr(features, rescaling_factor, NumFeatures);
}

static inline double svm_decision_value(double features[static NumFeatures]) {
    double ALIGNED(32) normsq[svm_l + 4];
    for (int i = 0; i < svm_l; i++)
        normsq[i] = normsq_double4_arr(&svm_SV[i][0], features, NumFeatures);

    __m256d* normsq4 = (__m256d*)normsq;
    __m256d* sv_coef4 = (__m256d*)svm_sv_coef;
    __m256d sum4={};
    for (int i = 0; i < (svm_l + 4)/4; i++)
        sum4 += sv_coef4[i] * exp_double4(-svm_gamma * normsq4[i]);

    return sum4[0] + sum4[1] + sum4[2] + sum4[3] - svm_rho;
}

// based on libsvm
static inline double sigmoid_predict(const double decision_value)
{
    const double fApB = svm_probA * decision_value + svm_probB;
    double prob;

    if (fApB >= 0) {
        const double exp_minus_fApB = scalar_exp(-fApB);
        prob = exp_minus_fApB/(1.0+exp_minus_fApB);
    }
    else {
        const double exp_fApB = scalar_exp(fApB);
        prob = 1.0/(1.0+exp_fApB) ;
    }

    const double min_prob = 1e-7;
    return __builtin_fmin(1-min_prob, __builtin_fmax(min_prob, prob));
}

#endif
