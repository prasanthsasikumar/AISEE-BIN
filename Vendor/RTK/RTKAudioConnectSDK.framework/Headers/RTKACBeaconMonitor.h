//
//  RTKACBeaconMonitor.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2022/2/24.
//  Copyright (c) 2022, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKMacros.h>
#else
#import <RTKAudioConnectSDK/RTKMacros.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class RTKACBeaconMonitor;

/// Methods an ``RTKACBeaconMonitor`` calls to report that an *Audio Connect* device is detected by its beacon.
@protocol RTKACBeaconMonitorDelegate <NSObject>
@required

/// An *Audio Connect* beacon is detected.
- (void)beaconMonitorDidDetectACBeacon:(RTKACBeaconMonitor *)monitor;

@optional

- (void)beaconMonitorDidDetectBBproBeacon:(RTKACBeaconMonitor *)monitor RTK_REDIRECT(beaconMonitorDidDetectACBeacon:);

@end


/// An object that monitors *Audio Connect* beacons.
@interface RTKACBeaconMonitor : NSObject

/// An object that recevice monitoring events.
@property (weak, nullable) id <RTKACBeaconMonitorDelegate> delegate;


/// Start monitoring *Audio Connect* beacons.
- (void)startMonitoringACBeacon;

- (void)startMonitoringBBproBeacon RTK_REDIRECT(startMonitoringACBeacon);

/// Stop monitoring *Audio Connect* beacons.
- (void)stopMonitoringACBeacon;

- (void)stopMonitoringBBproBeacon RTK_REDIRECT(stopMonitoringACBeacon);

@end

NS_ASSUME_NONNULL_END
