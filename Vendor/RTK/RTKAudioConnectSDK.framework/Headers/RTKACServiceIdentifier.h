//
//  RTKACServiceIdentifier.h
//  RTKAudioConnectSDK
//
//  Created by jerome_gu on 2019/4/10.
//  Copyright (c) 2019, Realtek Semiconductor Corporation
//
//  SPDX-License-Identifier: LicenseRef-Realtek-5-Clause
//

#ifndef RTKACServiceIdentifier_h
#define RTKACServiceIdentifier_h

#define RTKAC_SERVICE_ID    @"000002FD-3C17-D293-8E48-14FE2E4DA212"
#define RTKAC_CHAR_ID_TX    @"FD03"
#define RTKAC_CHAR_ID_RX    @"FD04"

#define ADV_SERVICE_ID_PRIMARY      @"010002FD-3C17-D293-8E48-14FE2E4DA212"
#define ADV_SERVICE_ID_SECONDARY    @"020002FD-3C17-D293-8E48-14FE2E4DA212"


// Deprecated
#define SERVICE_ID_BBPRO \
    _Pragma("GCC warning \"'SERVICE_ID_BBPRO' is deprecated, please use 'RTKAC_SERVICE_ID' instead.\"") \
    RTKAC_SERVICE_ID

#define CHAR_ID_BBPRO_TX \
    _Pragma("GCC warning \"'CHAR_ID_BBPRO_TX' is deprecated, please use 'RTKAC_CHAR_ID_TX' instead.\"") \
    RTKAC_CHAR_ID_TX

#define CHAR_ID_BBPRO_RX \
    _Pragma("GCC warning \"'CHAR_ID_BBPRO_RX' is deprecated, please use 'RTKAC_CHAR_ID_RX' instead.\"") \
    RTKAC_CHAR_ID_RX

#endif /* RTKACServiceIdentifier_h */
