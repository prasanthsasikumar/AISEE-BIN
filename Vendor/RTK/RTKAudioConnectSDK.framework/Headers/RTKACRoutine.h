//
//  RTKACRoutine.h
//  RTKBTFoundation
//
//  Created by jerome_gu on 2020/3/13.
//  Copyright (c) 2020, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <RTKLEFoundation/RTKLEFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// An abstract class that provides correlative functionality related to a feature.
@interface RTKACRoutine : NSObject <RTKPacketTransportClient>

/// The profile connection this routine belongs to.
///
/// Only have a value if the routien is created using ``initWithConnection:``.
@property (assign, nonnull, readonly) RTKProfileConnection *connection;

/// Initialize the routine with the profile connection.
- (instancetype)initWithConnection:(RTKProfileConnection *)connection;

/// Initializes a new routine using a transport for message packet exchanging.
- (instancetype)initWithMessageTransport:(nullable RTKPacketTransport*)transport;

/// The transport this routine uses for message packet exchanging.
@property (nonatomic, nullable) RTKPacketTransport *messageTransport;

/// The transport this routine uses for request packets exchanging.
@property (nonatomic, nullable, readonly) RTKPacketRequestTransport *requestTransport;


/// Clear all cached state that is inconstancy.
- (void)clearCachedInconstantState;

/// Encode its state into an archiver.
- (void)encodeStateWithArchiver:(NSCoder *)archiver;

/// Decode and restore its state from an unarchiver.
- (void)decodeStateWithUnarchiver:(NSCoder *)unarchiver;

@end


NS_ASSUME_NONNULL_END
