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
	double ALIGN(32) dotp[svm_l + 4];
	for (int i = 0; i < svm_l; i++)
		dotp[i] = dot_double4_arr(&svm_SV[i][0], features, NumFeatures);

	__m256d* dotp4 = (__m256d*)dotp;
	__m256d* sv_coef4 = (__m256d*)svm_sv_coef;
	__m256d sum4={};
	for (int i = 0; i < (svm_l + 4)/4; i++)
		sum4 += sv_coef4[i] * exp_double4(-svm_gamma * dotp4[i]);

	return sum4[0] + sum4[1] + sum4[2] + sum4[3] - svm_rho;
}

#endif