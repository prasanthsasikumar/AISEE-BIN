//
//  RTKACRoutineContainer.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2020/3/31.
//  Copyright (c) 2020, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <Foundation/Foundation.h>
#import <RTKLEFoundation/RTKLEFoundation.h>
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACBasicRoutine.h>
#import <ATAudioConnectSDK/RTKACEQRoutine.h>
#import <ATAudioConnectSDK/RTKACAudioRoutine.h>
#import <ATAudioConnectSDK/RTKACMMIRoutine.h>
#import <ATAudioConnectSDK/RTKACTTSRoutine.h>
#import <ATAudioConnectSDK/RTKACRHARoutine.h>
#import <ATAudioConnectSDK/ATBBproRoutine.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACBasicRoutine.h>
#import <RTKWaveLiteSDK/RTKACEQRoutine.h>
#import <RTKWaveLiteSDK/RTKACAudioRoutine.h>
#import <RTKWaveLiteSDK/RTKACMMIRoutine.h>
#import <RTKWaveLiteSDK/RTKACRHARoutine.h>
#else
#import <RTKAudioConnectSDK/RTKACBasicRoutine.h>
#import <RTKAudioConnectSDK/RTKACEQRoutine.h>
#import <RTKAudioConnectSDK/RTKACAudioRoutine.h>
#import <RTKAudioConnectSDK/RTKACMMIRoutine.h>
#import <RTKAudioConnectSDK/RTKACTTSRoutine.h>
#import <RTKAudioConnectSDK/RTKACRHARoutine.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// Common properties and methods for an Audio Connect device connection.
///
/// This class is expected to only be subclass internal in this framwork. Code outside this framework should use concreate subclass directly.
@protocol RTKACRoutineContainer <NSObject>

/// The transport used for exchanging message packets.
@property (readonly) RTKPacketTransport *messageTransport;

/// Return a basic routine the conforming class instance has.
///
/// - Returns `nil` if the conforming instance does not have a basic routine.
///
/// Use the returned routine to make interaction with the corresponding device.
@property (nonatomic, readonly, nullable) RTKACBasicRoutine *basicRoutine;

/// Return a EQ routine the conforming class instance has.
///
/// - Returns `nil` if the conforming instance does not have a EQ routine.
///
/// Use the returned routine to make interaction with the corresponding device.
@property (nonatomic, readonly, nullable) RTKACEQRoutine *EQRoutine;

/// Return an audio routine the conforming class instance has.
///
/// - Returns `nil` if the conforming instance does not have an audio routine.
///
/// Use the returned routine to make interaction with the corresponding device.
@property (nonatomic, readonly, nullable) RTKACAudioRoutine *audioRoutine;

/// Return a MMI routine the conforming class instance has.
///
/// - Returns `nil` if the conforming instance does not have a MMI routine.
///
/// Use the returned routine to make interaction with the corresponding device.
@property (nonatomic, readonly, nullable) RTKACMMIRoutine *MMIRoutine;

#ifndef RTKWaveLiteSDK
/// Return a TTS routine the conforming class instance has.
///
/// - Returns `nil` if the conforming instance does not have a TTS routine.
///
/// Use the returned routine to make interaction with the corresponding device.
@property (nonatomic, readonly, nullable) RTKACTTSRoutine *TTSRoutine;

#endif

/// Return a hearing aid routine the conforming class instance has.
///
/// - Returns `nil` if the conforming instance does not have a hearing aid routine.
///
/// Use the returned routine to make interaction with the corresponding device.
@property (nonatomic, readonly, nullable) RTKACRHARoutine *HARoutine;

#ifdef ATAudioConnectSDK

@property (nonatomic, readonly, nullable) ATBBproRoutine *ATRoutine;

#endif

#pragma mark - State Snapshot

/// Return a data object which is encoded from the state of a conforming object.
- (nullable NSData *)stateSnapshot;

/// Restore the state of a conforming object with the encoded state data.
///
/// - Parameter snapshot: The data returned by ``stateSnapshot``.
- (void)restoreStateWithSnapshot:(NSData *)snapshot;

@end


NS_ASSUME_NONNULL_END
