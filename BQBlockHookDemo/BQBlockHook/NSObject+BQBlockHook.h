//
//  NSObject+BQBlockHook.h
//  BQBlockHookDemo
//
//  Created by wangbingquan on 2020/9/14.
//  Copyright © 2020 wangbingquan. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, BQBlockHookMode) {
    BQBlockHookModeBefore = 1 << 0,
    BQBlockHookModeInstead = 1 << 1,
    BQBlockHookModeAfter = 1 << 2,
    BQBlockHookAutomaticRemoval = 1 <<3
};

@interface NSObject (BQBlockHook)

@property(nonatomic, assign) BQBlockHookMode mode;

@property(nonatomic, copy) id aspectBlock;

-(void)hookWithMode:(BQBlockHookMode)mode
              usingBlock:(id)aspectBlock;


@end

NS_ASSUME_NONNULL_END
