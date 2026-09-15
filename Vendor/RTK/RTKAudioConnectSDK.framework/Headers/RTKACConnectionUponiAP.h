//
//  RTKACConnectionUponiAP.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2020/3/4.
//  Copyright (c) 2020, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <RTKLEFoundation/RTKLEFoundation.h>
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACRoutineContainer.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACRoutineContainer.h>
#else
#import <RTKAudioConnectSDK/RTKACRoutineContainer.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// A iAP connection with an Audio Connect feature implemented device.
///
/// An ``RTKACConnectionManager`` creates an instance of this class if it discovers a connection with *Audio Connect* device using iAP.
@interface RTKACConnectionUponiAP : RTKConnectionUponiAP <RTKACRoutineContainer, RTKPacketTransportClient>

@end

NS_ASSUME_NONNULL_END
