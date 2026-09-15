//
//  RTKACRequestTransport.h
//  RTKAudioConnectSDK_new
//
//  Created by jerome_gu on 2022/1/14.
//  Copyright (c) 2022, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#import <RTKLEFoundation/RTKLEFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTKACRequestTransport : RTKPacketRequestTransport

/// Add additional command ids of an request message  and the relevant response message.
///
/// The transport uses command id information to ensure a message is really a request and match a received message as the response to the request.
- (void)registerRequestMsgCmdId:(uint16_t)reqCmd responseMsgCmdId:(uint16_t)respCmd;

@end

DEPRECATED_MSG_ATTRIBUTE("Use RTKACRequestTransport instead")
@interface RTKBBproRequestTransport : RTKACRequestTransport

@end

NS_ASSUME_NONNULL_END
