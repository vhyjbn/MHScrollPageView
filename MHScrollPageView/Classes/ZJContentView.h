//
//  ZJContentView.h
//  ZJScrollPageView
//
//  Created by jasnig on 16/5/6.
//  Copyright © 2016年 ZeroJ. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ZJScrollPageViewDelegate.h"
#import "ZJCollectionView.h"
#import "ZJScrollSegmentView.h"
#import "UIViewController+ZJScrollPageController.h"

@interface ZJContentView : UIView

/** 必须设置代理和实现相关的方法*/
@property(weak, nonatomic)id<ZJScrollPageViewDelegate> delegate;
@property (strong, nonatomic, readonly) ZJCollectionView *collectionView;
@property (assign, nonatomic) BOOL disablePopGesture; // 禁用右划返回
@property (assign, nonatomic) NSInteger currentIndex;

- (NSInteger)getCurrentShowIndex;

/**初始化方法
 *
 */
- (instancetype)initWithFrame:(CGRect)frame segmentView:(ZJScrollSegmentView *)segmentView parentViewController:(UIViewController *)parentViewController delegate:(id<ZJScrollPageViewDelegate>) delegate;

/** 给外界可以设置ContentOffSet的方法 */
- (void)setContentOffSet:(CGPoint)offset animated:(BOOL)animated;
/** 给外界 重新加载内容的方法 */
- (void)reload;
/** 给外界 重新加载内容的方法 -当frame改变时调用*/
- (void)reloadForFrameChange;

@end
