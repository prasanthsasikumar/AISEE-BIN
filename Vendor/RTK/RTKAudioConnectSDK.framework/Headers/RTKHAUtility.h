//
//  RTKHAUtility.h
//  RTKAudioConnectSDK
//
//  Created by Jerome Gu on 2023/6/6.
//  Copyright (c) 2023, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#ifndef RTKHAUtility_h
#define RTKHAUtility_h

#include <MacTypes.h>

struct HAOutputSPLRef {
    UInt16 count;
    UInt16 rsv;
    struct SPLRefItem {
        UInt16 freq;
        UInt8 ref;
    } __attribute__((__packed__)) refs[0];
} __attribute__((__packed__));

#endif /* RTKHAUtility_h */
