//
//  RTKACConnectionManager.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2021/10/18.
//  Copyright (c) 2021, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <RTKLEFoundation/RTKLEFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A connection manager which manages connections with Audio Connect devices.
///
/// You create an instance of this class, use it to discover connections with *Audio Connect* devices.
@interface RTKACConnectionManager : RTKProfileConnectionManager


/// Start scaning for the connection with a specific Charging Case.
///
/// - Parameters:
///     - addr: The address of the charing case .
///     - timeout: The interval for scaning before timeouts.
///     - handler: The block to be called when the task completes.
- (void)scanForChargingCaseWithAddress:(BDAddressType)addr
                               timeout:(NSTimeInterval)timeout
                     completionHandler:(void (^)(BOOL success, NSError *__nullable error, RTKProfileConnection *chargeCaseConnection))handler;

@end

NS_ASSUME_NONNULL_END
