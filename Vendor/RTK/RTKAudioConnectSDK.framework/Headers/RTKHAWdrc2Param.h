//
//  RTKHAWdrc2Param.h
//  RTKAudioConnectSDK
//
//  Created by irene_wang on 2025/12/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Channel Info

/// Data structure representing configuration for a single frequency channel.
@interface RTKHAWdrc2ChannelInfo : NSObject

/// The center frequency of the channel (e.g., 500, 1000, 2000 Hz).
@property (nonatomic, assign) NSInteger centerFreq;

/// The number of compression segments active in this channel.
@property (nonatomic, assign) NSInteger segmentNum;

/// The makeup gain applied specifically to this channel .
@property (nonatomic, assign) double channelMakeupGain;

/// An array of slopes for each segment. The reciprocal of the compression ratio of each SPL segment.
/// Stores `NSNumber` containing double values.
@property (nonatomic, strong) NSArray<NSNumber *> *slopes;

/// An array of threshold values for each segment.
/// Stores `NSNumber` containing integer or double values.
@property (nonatomic, strong) NSArray<NSNumber *> *thresholds;

/// Attack time for the compression stage (when ratio is greater than 1).
@property (nonatomic, assign) NSInteger compressAttackTime;

/// Release time for the compression stage (when ratio is greater than 1).
@property (nonatomic, assign) NSInteger compressReleaseTime;

/// Attack time for the expansion stage (when ratio is less than 1).
@property (nonatomic, assign) NSInteger expandAttackTime;

/// Release time for the expansion stage (when ratio is less than 1).
@property (nonatomic, assign) NSInteger expandReleaseTime;

/// Maximum Power Output limit for this channel.
@property (nonatomic, assign) NSInteger mpo;

@end


#pragma mark - Main Param

/// Main configuration structure for the WDRC algorithm.
@interface RTKHAWdrc2Param : NSObject

/// RTK internal algorithm version (default is usually 2).
@property (nonatomic, assign) NSInteger version;

/// Total number of channels utilized in this configuration.
@property (nonatomic, assign) NSInteger channelNum;

/// Width of the soft knee region, smoothing the transition at the threshold.
@property (nonatomic, assign) NSInteger softKneeWidth;

/// Global pre-gain applied before processing. (Invalid. It can be omitted)
@property (nonatomic, assign) double preGain;

/// Global makeup gain applied after processing. (Invalid. It can be omitted)
@property (nonatomic, assign) double makeupGain;

/// List of detailed configurations for each channel. The count must be consistent with `channelNum`
/// Contains `RTKWdrc2ChannelInfo` objects.
@property (nonatomic, strong) NSArray<RTKHAWdrc2ChannelInfo *> *channelInfos;


- (BOOL)saveToJSONPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
