//
//  RTKACMMIRoutine.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2020/9/15.
//  Copyright (c) 2020, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//
#ifdef ATAudioConnectSDK
#import <ATAudioConnectSDK/RTKACRoutine.h>
#import <ATAudioConnectSDK/RTKACType.h>
#import <ATAudioConnectSDK/RTKMacros.h>
#import <ATAudioConnectSDK/RTKBBproType.h>
#elif defined(RTKWaveLiteSDK)
#import <RTKWaveLiteSDK/RTKACRoutine.h>
#import <RTKWaveLiteSDK/RTKACType.h>
#import <RTKWaveLiteSDK/RTKMacros.h>
#import <RTKWaveLiteSDK/RTKBBproType.h>
#else
#import <RTKAudioConnectSDK/RTKACRoutine.h>
#import <RTKAudioConnectSDK/RTKACType.h>
#import <RTKAudioConnectSDK/RTKMacros.h>
#import <RTKAudioConnectSDK/RTKBBproType.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class RTKACMMIRoutine;

/// Methods an ``RTKACMMIRoutine`` calls to report MMI events.
@protocol RTKACMMIRoutineStateReporting <NSObject>

/// Tells the delegate that remote device request to update button lock state.
///
/// - Parameter routine: The routine that did request update button lock state.
- (void)ACMMIRoutine:(RTKACMMIRoutine *)routine didReceiveUpdateOfButtonLockState:(BOOL)isLocked;

- (void)BBproMMIRoutine:(RTKACMMIRoutine *)routine didReceiveUpdateOfButtonLockState:(BOOL)isLocked RTK_REDIRECT(ACMMIRoutine:didReceiveUpdateOfButtonLockState:);

@end


/// An object that provides MMI related functionality.
@interface RTKACMMIRoutine : RTKACRoutine

/// The delegate object that receives MMI events.
@property (weak) id<RTKACMMIRoutineStateReporting> delegate;


/// Send a MMI action to the device.
- (void)sendMMIAction:(RTKACMMIAction)action withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Get the  MMI actions supported by this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``supportedMMIs`` property when succeed.
- (void)getSupportedMMIsWithCompletionHandler:(nullable void(^)(BOOL success, NSError *_Nullable err, NSArray<NSNumber*>* MMIs))handler;


/// Get the MMI click motions supported by this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``supportedClicks`` property when succeed.
- (void)getSupportedClicksWithCompletionHandler:(nullable void(^)(BOOL success, NSError *_Nullable err, NSArray<NSNumber*>* clicks))handler;


/// Get the call status for MMI supported by this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``supportedPhoneStatus`` property when succeed.
- (void)getSupportedPhoneStatusWithCompletionHandler:(nullable void(^)(BOOL success, NSError *_Nullable err, NSArray<NSNumber*>* statuses))handler;


/// Get the MMI mapping configuration of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update  ``mmiKeyMappings`` property when succeed.
- (void)getMMIKeyMappingWithCompletionHandler:(nullable void(^)(BOOL success, NSError *_Nullable err, NSArray<NSValue*>* mappings))handler;


/// Set a MMI mapping configuration to this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``mmiKeyMappings`` property when succeed.
- (void)setMMIKeyMapping:(RTKACMMIMapping)mapping withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Reset the MMI mapping to the default configuration.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``mmiKeyMappings`` property when succeed.
- (void)resetMMIKeyMappingWithCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Reset the MMI mapping to the default configuration.(can specify bud)
///
/// - Parameter budSide: The specified budSide.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``mmiKeyMappings`` property when succeed.
- (void)resetMMIKeyMappingOfBudSide:(RTKACMMIBudSide)budSide withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Get the button locked state of this peripheral.
/// 
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``buttonLocked`` property when succeed.
- (void)getMMIButtonLockStateWithCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Switch the button locked state of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``buttonLocked`` property when succeed.
- (void)switchMMIButtonLockStateWithCompletionHandler:(nullable RTKLECompletionBlock)handler;

/// Request the device to enter to Pairing mode.
- (void)requestEnterToPairingModeWithCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Request the device to exit from Pairing mode.
- (void)requestExitToPairingModeWithCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Send a power off MMI action to this peripheral.
- (void)powerOffWithCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Get the RWS MMI mapping configuration of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update  ``rwsmmiKeyMappings``  property when succeed.
- (void)getRWSKeyMMIMapWithCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Configure a RWS MMI mapping of this peripheral.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``rwsmmiKeyMappings`` property when succeed.
- (void)setRWSKeyMMIMap:(RTKACMMIMapping)mapping withCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Reset the RWS MMI mapping to the default configuration.
///
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``rwsmmiKeyMappings`` property when succeed.
- (void)resetRWSKeyMMIMapWithCompletionHandler:(nullable RTKLECompletionBlock)handler;


/// Reset the RWS MMI mapping to the default configuration.(can specify bud)
///
/// - Parameter budSide: The specified budSide.
/// - Parameter handler: A block to called when this task complete successfullly or unsuccessfully.
///
/// Will update ``rwsmmiKeyMappings`` property when succeed.
- (void)resetRWSKeyMMIMapOfBudSide:(RTKACMMIBudSide)budSide withCompletionHandler:(nullable RTKLECompletionBlock)handler;

@end



@interface RTKACMMIRoutine (Cache)

/// Return a list of MMI actions supported by this peripheral last cached.
///
/// For each item, scalar value is of ``RTKACMMIAction`` type. Affected ``RTKACMMIRoutine/getSupportedMMIsWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray <NSNumber*> *supportedMMIs;


/// Return a list of MMI motions supported by this peripheral last cached.
///
/// For each item, scalar value is of ``RTKACMMIClickType`` type.  Affected by ``RTKACMMIRoutine/getSupportedClicksWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray <NSNumber*> *supportedClicks;


/// Return a list of call status for MMI supported by this peripheral last cached.
///
/// For each item, scalar value is of ``RTKACMMIStatus`` type.  Affected by ``RTKACMMIRoutine/getSupportedPhoneStatusWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray <NSNumber*> *supportedPhoneStatus;


/// Return a list of MMI mapping of this peripheral last cached.
///
/// For each item, scalar value is of ``RTKACMMIMapping`` type.  Affected by ``RTKACMMIRoutine/getMMIKeyMappingWithCompletionHandler:``,  ``RTKACMMIRoutine/setMMIKeyMapping:withCompletionHandler:``,  ``RTKACMMIRoutine/resetMMIKeyMappingWithCompletionHandler:`` and ``RTKACMMIRoutine/resetMMIKeyMappingOfBudSide:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray <NSValue*> *MMIKeyMappings;


/// Return a list of RWS MMI mapping of this peripheral last cached.
///
/// For each item, scalar value is of ``RTKACMMIMapping`` type.  Affected by ``RTKACMMIRoutine/getRWSKeyMMIMapWithCompletionHandler:``,  ``RTKACMMIRoutine/setRWSKeyMMIMap:withCompletionHandler:``, ``RTKACMMIRoutine/resetRWSKeyMMIMapWithCompletionHandler:`` and ``RTKACMMIRoutine/resetRWSKeyMMIMapOfBudSide:withCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSArray <NSValue*> *RWSMMIKeyMappings;


/// Return whether the button locked state is on.
///
/// For each item, scalar value is of `BOOL` type. Affected by ``RTKACMMIRoutine/getMMIButtonLockStateWithCompletionHandler:`` and ``RTKACMMIRoutine/switchMMIButtonLockStateWithCompletionHandler:``.
@property (nonatomic, readonly, nullable) NSNumber *buttonLocked;

@end


@interface RTKACMMIRoutine (Deprecated)

- (void)sendMMIActionLegacy:(RTKBBproPeripheralMMI)action
      withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('sendMMIAction:withCompletionHandler:' with 'RTKACMMIAction')
   NS_SWIFT_NAME(sendMMIAction(_:withCompletionHandler:));

- (void)resetMMIKeyMappingOfBudSideLegacy:(RTKBBproMMIBudSide)budSide
                    withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('resetMMIKeyMappingOfBudSide:withCompletionHandler:' with 'RTKACMMIBudSide')
   NS_SWIFT_NAME(resetMMIKeyMapping(of:withCompletionHandler:));

- (void)resetRWSKeyMMIMapOfBudSideLegacy:(RTKBBproMMIBudSide)budSide
                   withCompletionHandler:(nullable RTKLECompletionBlock)handler
RTK_REDIRECT('resetRWSKeyMMIMapOfBudSide:withCompletionHandler:' with 'RTKACMMIBudSide')
   NS_SWIFT_NAME(resetRWSKeyMMIMap(of:withCompletionHandler:));

@end

NS_ASSUME_NONNULL_END
