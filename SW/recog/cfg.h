#ifndef GYMNORTUS_CFG_H
#define GYMNORTUS_CFG_H

#include "generated_cfg.h"


// If the window size is above this, SVM will not be applied,
// as we will consider the window as probably containing
// spikes from both individuals. Only the DistMinimizer result
// will be considered.
enum { MaxWinSizeForSVM = 124 };


// If max(abs(signal)) is above this, SVM will not be applied
// for the corresponding channel, as we will consider the signal
// as being saturated in this channel.
static const float SaturationThreshold = 2028.f;


// If max(abs(signal)) is below this, SVM will not be applied
// for the corresponding channel, as we will consider the
// channel has poor signal-to-noise ratio (SNR).
static const float OnlyAbove = 20.f;


// Below are settings for choosing high specificity SVM results.
// SVM results which match these constraints are trusted above
// the DistMinimizer module, also controlling directly its
// feedback channel.
//
// Maximum window size: the window size should be below this
// number of samples, so the window may contain spikes from
// both individuals only if it is well overlapped (which
// should cause SVM results from different channels to
// more probably diverge, therefore being detected).
enum { HighSpecMaxWinSize = 76 };
//
// Minimum channels: at least this number of channels should be
// suitable for SVM classification.
enum { HighSpecMinCh = 4 };
//
// Probability threshold: every channel suitable for SVM must
// produce a probability estimation above this threshold.
static const double HighSpecProbThreshold = 0.999;
//
// Distance from last detection: used to construct spike pairs
// which are close to each one, and are detected as different
// individuals. Should be a time interval (expressed in number
// of samples) within the refractory period.
enum { HighSpecInterval = 400 };


// If SVM disagrees with DistMinimizer for more than this
// number of subsequent windows, reset DistMinimizer state
// to current SVM output. This is meant to prevent
// continuity constraint errors from propagating indefinitely.
enum { ContinuityHysteresis = 3 };


#endif
