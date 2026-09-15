//
//  RTKACMessageTransport.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2019/1/11.
//  Copyright (c) 2019, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <RTKLEFoundation/RTKLEFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTKACMessageTransport : RTKPacketACKTransport

/// Specify a opcode for a received message to which this transport does not send ack.
- (void)omitAckForMessageWithOpcode: (NSInteger)opcode;

/// Send a message without waitting for the ack.
- (void)sendIgnoringACK:(NSData *)data withCompletionHandler:(nullable RTKTransportSendResult)handler;

@end

DEPRECATED_MSG_ATTRIBUTE("Use RTKACMessageTransport instead")
@interface RTKBBproMessageTransport : RTKACMessageTransport
@end



NS_ASSUME_NONNULL_END
