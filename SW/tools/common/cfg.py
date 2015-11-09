# general config
SamplesPerWord = 4         # samples
WordBytes = 8              # bytes
WordsNeedForAllCh = 3      # words
SamplingRate = 50.e3       # Hz
ADBits = 12                # bits
PaddedBits = 16            # bits
TotalCh = 16               # channels
EnabledCh = 11             # channels
VoltageScale = 10          # V

ContinuousAcqDev = '/dev/rtf0'
RecogDev = '/dev/rtf0'

# scope config
ScopeViewWords = 1280      # words
ScopeRenderInterval = 10   # ms

# calibrate config
CalibrateTime = 2.0        # s

# spikes config
SpikesWinSize = 128        # samples
SpikesAfterRef = 35        # samples, set to WindowMaker's forceSamplesAfterMax

# translateModel config
DtcwptOffset = 64          # gymnotools's NumFFTFeatures

# plotipi config
PlotIpiViewTime = 60        # s
PlotIpiViewIpiScale = 50    # ms
PlotIpiRenderInterval = 200 # ms