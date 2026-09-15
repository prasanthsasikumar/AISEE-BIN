//
//  RTKACConnectionUponGATT.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2021/10/18.
//  Copyright (c) 2021, Realtek Semiconductor Corporation
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

/// A GATT connection with an Audio Connect feature implemented device.
///
/// An ``RTKACConnectionManager`` creates an instance of this class if it discovers a connection with *Audio Connect* device using GATT.
@interface RTKACConnectionUponGATT : RTKConnectionUponGATT <RTKACRoutineContainer, RTKPacketTransportClient>

/// Any process just before the connection is assumed active.
///
/// Don't call this method directly as this method is expected to be overrided in the subclass to add extended operations.
- (void)setupPreActive: (nullable RTKLECompletionBlock)completionHandler;

/// Peform any process just after the connection is active.
///
/// Don't call this method directly, it is expected to be overrided in the subclass to add extended operations.
- (void)setupPostActive;

@end

NS_ASSUME_NONNULL_END
