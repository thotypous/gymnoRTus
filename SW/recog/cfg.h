#ifndef GYMNORTUS_CFG_H
#define GYMNORTUS_CFG_H

#include "generated_cfg.h"


// If the window size is above this, SVM will not be applied,
// as we will consider the window as almost certainly containing
// spikes from both individuals. In this case, only the
// DistMinimizer result will be used.
enum { MaxWinSizeForSVM = 124 };


// If max(abs(signal)) is above this, SVM will not be applied
// for the corresponding channel, as we will consider the signal
// as being saturated in the corresponding channel.
static const float SaturationThreshold = 2028.f;


// If max(abs(signal)) is below this, SVM will not be applied
// for the corresponding channel, as we will consider the
// channel has poor signal-to-noise ratio (SNR).
static const float OnlyAbove = 32.f;


// Refractory period in number of samples.
// After a spike from a certain individual is detected, no spikes
// from the same individual will be detected before this time
// interval is over.
enum { RefractoryPeriod = 400 };


// Below are settings for choosing high specificity SVM results,
// which are used to initialize the DistMinimizer module.
//
// Maximum window size: if the window size is below this
// number of samples, it means the window may only contain
// spikes from both individuals if their spikes are very
// overlapped. This should cause SVM results from different
// channels to more probably diverge, therefore causing an
// overlap to be more easily detected.
// You may set this value to mean size + standard deviation.
enum { HighSpecMaxWinSize = 76 };
//
// Minimum number of channels: at least this amount of channels
// should be suitable for SVM.
enum { HighSpecMinCh = 1 };
//
// Probability threshold: every channel suitable for SVM must
// produce a probability estimation above this threshold.
static const double HighSpecProbThreshold = 0.995;


// If SVM disagrees with DistMinimizer for more than this number
// of subsequent windows, we put DistMinimizer into out-of-sync
// mode, so that its state is reset when high specificity SVM
// results are available. This is meant to prevent continuity
// constraint errors from propagating indefinitely.
enum { ContinuityHysteresis = 3 };


// Assertions
#define IS_POWER_OF_TWO(N) ((N) && !((N) & ((N) - 1)))
_Static_assert(IS_POWER_OF_TWO(WaveletInSize), "Window size must be a power of 2");
_Static_assert((int)MaxWinSizeForSVM <= (int)WaveletInSize, "A single spike window must fit in wavelet transform");
_Static_assert((int)HighSpecMaxWinSize <= (int)MaxWinSizeForSVM, "High specificity requires a single spike");
_Static_assert(HighSpecMinCh > 0, "At least one channel is required for high specificity");
_Static_assert(ContinuityHysteresis > 0, "That would continuously trigger unsync");


#endif
