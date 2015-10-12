Base = 0x0

WContinuousAcqStart = Base + 0x00
WContinuousAcqStop  = Base + 0x01
WMockADFire         = Base + 0x02
WMockADSetMocked    = Base + 0x03
WWinDMAStart        = Base + 0x04
WWinDMAStop         = Base + 0x05
WDMinFeedback       = Base + 0x08
WSetOffset          = Base + 0x10

RContinuousAcqAck   = Base + 0x00
RMockADBusy         = Base + 0x02
RWinDMAAck          = Base + 0x04
RWinDMAPeekRefSize  = Base + 0x06
RWinDMAGetTimeStamp = Base + 0x07
RDMinResultReady    = Base + 0x08
RDMinPeekSum        = Base + 0x09
RDMinGetRotSpk      = Base + 0x10
