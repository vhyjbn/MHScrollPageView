//
//  ZJContentView.m
//  ZJScrollPageView
//
//  Created by jasnig on 16/5/6.
//  Copyright © 2016年 ZeroJ. All rights reserved.
//

#import "ZJContentView.h"

@interface ZJContentView ()<UIScrollViewDelegate, UICollectionViewDelegate, UICollectionViewDataSource> {
    CGFloat   _oldOffSetX;
    BOOL _isLoadFirstView;
    NSInteger _sysVersion;
}
@property (weak, nonatomic) ZJScrollSegmentView *segmentView;

// 用于处理重用和内容的显示
@property (strong, nonatomic) ZJCollectionView *collectionView;
// collectionView的布局
@property (strong, nonatomic) UICollectionViewFlowLayout *collectionViewLayout;
// 父类 用于处理添加子控制器  使用weak避免循环引用
@property (weak, nonatomic) UIViewController *parentViewController;
// 当这个属性设置为YES的时候 就不用处理 scrollView滚动的计算
@property (assign, nonatomic) BOOL forbidTouchToAdjustPosition;
@property (assign, nonatomic) NSInteger itemsCount;
// 所有的子控制器
@property (strong, nonatomic) NSMutableDictionary<NSString *, UIViewController<ZJScrollPageViewChildVcDelegate> *> *childVcsDic;
// 当前控制器
@property (strong, nonatomic) UIViewController<ZJScrollPageViewChildVcDelegate> *currentChildVc;

/// 如果类似cell缓存一样, 虽然创建的控制器少了, 但是每个页面每次都要重新加载数据, 否则显示的内容就会出错, 貌似还不如每个页面创建一个控制器好
//@property (strong, nonatomic) NSCache *cacheChildVcs;

@property (assign, nonatomic) NSInteger oldIndex;
@property (assign, nonatomic) BOOL needManageLifeCycle;
@property (assign, nonatomic) BOOL changeAnimated;


@end

@implementation ZJContentView
#define cellID @"cellID"

static NSString *const kContentOffsetOffKey = @"contentOffset";
#pragma mark - life cycle

- (instancetype)initWithFrame:(CGRect)frame segmentView:(ZJScrollSegmentView *)segmentView parentViewController:(UIViewController *)parentViewController delegate:(id<ZJScrollPageViewDelegate>) delegate {
    
    if (self = [super initWithFrame:frame]) {
        self.segmentView = segmentView;
        self.delegate = delegate;
        self.parentViewController = parentViewController;
        _needManageLifeCycle = ![parentViewController shouldAutomaticallyForwardAppearanceMethods];
        if (!_needManageLifeCycle) {
#if DEBUG
            // NSLog(@"\n请注意: 如果你希望所有的子控制器的view的系统生命周期方法被正确的调用\n请重写%@的'shouldAutomaticallyForwardAppearanceMethods'方法 并且返回NO\n当然如果你不做这个操作, 子控制器的生命周期方法将不会被正确的调用\n如果你仍然想利用子控制器的生命周期方法, 请使用'ZJScrollPageViewChildVcDelegate'提供的代理方法\n或者'ZJScrollPageViewDelegate'提供的代理方法", [parentViewController class]);
#endif
        }
        [self commonInit];
        [self addNotification];
    }
    return self;
}

- (void)commonInit {
    
    _oldIndex = -1;
    _currentIndex = 0;
    _oldOffSetX = 0.0f;
    _forbidTouchToAdjustPosition = NO;
    _isLoadFirstView = YES;
    _sysVersion = [[[UIDevice currentDevice] systemVersion] integerValue];
    
    if ([_delegate respondsToSelector:@selector(numberOfChildViewControllers)]) {
        self.itemsCount = [_delegate numberOfChildViewControllers];
    }
    self.collectionView.backgroundColor = [UIColor grayColor];
    [self addSubview:self.collectionView];
    
    UINavigationController *navi = (UINavigationController *)self.parentViewController.parentViewController;

    if ([navi isKindOfClass:[UINavigationController class]]) {
        if (navi.viewControllers.count == 1) return;
        
        if (navi.interactivePopGestureRecognizer) {
            
            __weak typeof(self) weakSelf = self;
            [_collectionView setupScrollViewShouldBeginPanGestureHandler:^BOOL(ZJCollectionView *collectionView, UIPanGestureRecognizer *panGesture) {
                if (!weakSelf.disablePopGesture) {
                    CGFloat transionX = [panGesture translationInView:panGesture.view].x;
                    if (collectionView.contentOffset.x == 0 && transionX > 0) {
                        navi.interactivePopGestureRecognizer.enabled = YES;
                    }
                    else {
                        navi.interactivePopGestureRecognizer.enabled = NO;
                        
                    }
                }

                if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(scrollPageController:contentScrollView:shouldBeginPanGesture:)]) {
                    return [weakSelf.delegate scrollPageController:weakSelf.parentViewController contentScrollView:collectionView shouldBeginPanGesture:panGesture];
                }
                else return YES;
            }];
        }
    }
}

- (void)addNotification {

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveMemoryWarningHander:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

- (void)receiveMemoryWarningHander:(NSNotificationCenter *)noti {
    
    __weak typeof(self) weakSelf = self;
    [_childVcsDic enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, UIViewController<ZJScrollPageViewChildVcDelegate> * _Nonnull childVc, BOOL * _Nonnull stop) {
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            if (childVc != strongSelf.currentChildVc) {
                [self->_childVcsDic removeObjectForKey:key];
                [ZJContentView removeChildVc:childVc];
            }
        }

    }];

}


- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.currentChildVc) {
        self.currentChildVc.view.frame = self.bounds;
    }
}

- (void)dealloc {
    self.parentViewController = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if DEBUG
//    NSLog(@"ZJContentView---销毁");
#endif
}

#pragma mark - public helper

/** 给外界可以设置ContentOffSet的方法 */
- (void)setContentOffSet:(CGPoint)offset animated:(BOOL)animated {
    self.forbidTouchToAdjustPosition = YES;
    
    NSInteger currentIndex = offset.x/self.collectionView.bounds.size.width;
    _oldIndex = _currentIndex;
    self.currentIndex = currentIndex;
    _changeAnimated = YES;

    if (animated) {
        CGFloat delta = offset.x - self.collectionView.contentOffset.x;
        NSInteger page = fabs(delta)/self.collectionView.bounds.size.width;
        if (page>=2) {// 需要滚动两页以上的时候, 跳过中间页的动画
            _changeAnimated = NO;
            __weak typeof(self) weakself = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakself) strongSelf = weakself;
                if (strongSelf) {
                    [strongSelf.collectionView setContentOffset:offset animated:NO];
                }
            });
        }
        else {
            [self.collectionView setContentOffset:offset animated:animated];
        }
    }
    else {

        [self.collectionView setContentOffset:offset animated:animated];
 
    }
    
}

/** 给外界刷新视图的方法 */
- (void)reload {
    
    [self.childVcsDic enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, UIViewController<ZJScrollPageViewChildVcDelegate> * _Nonnull childVc, BOOL * _Nonnull stop) {
        [ZJContentView removeChildVc:childVc];
        childVc = nil;

    }];
    self.childVcsDic = nil;
    [self.collectionView reloadData];
    [self commonInit];
}

/** 给外界 重新加载内容的方法 -当frame改变时调用*/
- (void)reloadForFrameChange {
    self.collectionViewLayout.itemSize = self.bounds.size;
    self.collectionView.frame = self.bounds;
    [self reload];
}

+ (void)removeChildVc:(UIViewController *)childVc {
    [childVc willMoveToParentViewController:nil];
    [childVc.view removeFromSuperview];
    [childVc removeFromParentViewController];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.forbidTouchToAdjustPosition || // 点击标题滚动
        scrollView.contentOffset.x <= 0 || // first or last
        scrollView.contentOffset.x >= scrollView.contentSize.width - scrollView.bounds.size.width) {
        return;
    }
    CGFloat tempProgress = scrollView.contentOffset.x / self.bounds.size.width;
    NSInteger tempIndex = tempProgress;
    
    CGFloat progress = tempProgress - floor(tempProgress);
    CGFloat deltaX = scrollView.contentOffset.x - _oldOffSetX;
    
    if (deltaX > 0) {// 向右
        if (progress == 0.0) {
            return;
        }
        self.currentIndex = tempIndex+1;
        self.oldIndex = tempIndex;
    }
    else if (deltaX < 0) {
        progress = 1.0 - progress;
        self.oldIndex = tempIndex+1;
        self.currentIndex = tempIndex;
//        UICollectionViewCell *currentCell = [_collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForRow:tempIndex inSection:0]];
//        if (currentCell == nil) {
//            _isOldCellDisappear = NO;
//            _isNewCellAppear = NO;
//        }
        
    }
    else {
         return;
    }
//    NSLog(@"old ---- %ld current --- %ld", _oldIndex, _currentIndex);
    
    
    [self contentViewDidMoveFromIndex:_oldIndex toIndex:_currentIndex progress:progress];

}

/** 滚动减速完成时再更新title的位置 */
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    NSInteger currentIndex = (scrollView.contentOffset.x / self.bounds.size.width);
    [self contentViewDidMoveFromIndex:currentIndex toIndex:currentIndex progress:1.0];

    // 调整title
    [self adjustSegmentTitleOffsetToCurrentIndex:currentIndex];
}


- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    _oldOffSetX = scrollView.contentOffset.x;
    self.forbidTouchToAdjustPosition = NO;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    UINavigationController *navi = (UINavigationController *)self.parentViewController.parentViewController;
    if ([navi isKindOfClass:[UINavigationController class]] && navi.interactivePopGestureRecognizer) {
        if (!self.disablePopGesture) {
            navi.interactivePopGestureRecognizer.enabled = YES;
        }
    }
}


#pragma mark - private helper
- (void)contentViewDidMoveFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex progress:(CGFloat)progress {
    if(self.segmentView) {
        [self.segmentView adjustUIWithProgress:progress oldIndex:fromIndex currentIndex:toIndex];
    }
}

- (void)adjustSegmentTitleOffsetToCurrentIndex:(NSInteger)index {
    if(self.segmentView) {
        [self.segmentView adjustTitleOffSetToCurrentIndex:index];
    }
}

- (void)willAppearWithIndex:(NSInteger)index {
    UIViewController<ZJScrollPageViewChildVcDelegate> *controller = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)index]];
    if (controller) {
        if ([controller respondsToSelector:@selector(zj_viewWillAppearForIndex:)]) {
            [controller zj_viewWillAppearForIndex:index];
        }
        if (_needManageLifeCycle) {
            [controller beginAppearanceTransition:YES animated:NO];

        }
        
        if (_delegate && [_delegate respondsToSelector:@selector(scrollPageController:childViewControllWillAppear:forIndex:)]) {
            [_delegate scrollPageController:self.parentViewController childViewControllWillAppear:controller forIndex:index];
        }
    }
    
    
}

- (void)didAppearWithIndex:(NSInteger)index {
    UIViewController<ZJScrollPageViewChildVcDelegate> *controller = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)index]];
    if (controller) {
        if ([controller respondsToSelector:@selector(zj_viewDidAppearForIndex:)]) {
            [controller zj_viewDidAppearForIndex:index];
        }
        if (_needManageLifeCycle) {
            [controller endAppearanceTransition];

        }

        if (_delegate && [_delegate respondsToSelector:@selector(scrollPageController:childViewControllDidAppear:forIndex:)]) {
            [_delegate scrollPageController:self.parentViewController childViewControllDidAppear:controller forIndex:index];
        }
    }
    
    
    
}

- (void)willDisappearWithIndex:(NSInteger)index {
    UIViewController<ZJScrollPageViewChildVcDelegate> *controller = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)index]];
    if (controller) {
        if ([controller respondsToSelector:@selector(zj_viewWillDisappearForIndex:)]) {
            [controller zj_viewWillDisappearForIndex:index];
        }
        if (_needManageLifeCycle) {
            [controller beginAppearanceTransition:NO animated:NO];

        }

        if (_delegate && [_delegate respondsToSelector:@selector(scrollPageController:childViewControllWillDisappear:forIndex:)]) {
            [_delegate scrollPageController:self.parentViewController childViewControllWillDisappear:controller forIndex:index];
        }
    }
    
}
- (void)didDisappearWithIndex:(NSInteger)index {
    UIViewController<ZJScrollPageViewChildVcDelegate> *controller = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)index]];
    if (controller) {
        if ([controller respondsToSelector:@selector(zj_viewDidDisappearForIndex:)]) {
            [controller zj_viewDidDisappearForIndex:index];
        }
        if (_needManageLifeCycle) {
            [controller endAppearanceTransition];

        }
        if (_delegate && [_delegate respondsToSelector:@selector(scrollPageController:childViewControllDidDisappear:forIndex:)]) {
            [_delegate scrollPageController:self.parentViewController childViewControllDidDisappear:controller forIndex:index];
        }
    }
}

#pragma mark - UICollectionViewDelegate --- UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    
    return _itemsCount;
}




- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellID forIndexPath:indexPath];
    // 移除subviews 避免重用内容显示错误
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    
    
    if (_sysVersion < 8) {
        [self setupChildVcForCell:cell atIndexPath:indexPath];
    }
    

    return cell;
}


- (void)setupChildVcForCell:(UICollectionViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    _currentChildVc = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)indexPath.row]];
    BOOL isFirstLoaded = _currentChildVc == nil;
    if (_delegate && [_delegate respondsToSelector:@selector(childViewController:forIndex:)]) {
        if (_currentChildVc == nil) {
            _currentChildVc = [_delegate childViewController:nil forIndex:indexPath.row];
            
            if (!_currentChildVc || ![_currentChildVc conformsToProtocol:@protocol(ZJScrollPageViewChildVcDelegate)]) {
                NSAssert(NO, @"子控制器必须遵守ZJScrollPageViewChildVcDelegate协议");
            }
            // 设置当前下标
            _currentChildVc.zj_currentIndex = indexPath.row;
            [self.childVcsDic setValue:_currentChildVc forKey:[NSString stringWithFormat:@"%ld", (long)indexPath.row]];
        } else {
            [_delegate childViewController:_currentChildVc forIndex:indexPath.row];
        }
    } else {
        NSAssert(NO, @"必须设置代理和实现代理方法");
    }
    // 这里建立子控制器和父控制器的关系
    if ([_currentChildVc isKindOfClass:[UINavigationController class]]) {
        NSAssert(NO, @"不要添加UINavigationController包装后的子控制器");
    }
    if (_currentChildVc.zj_scrollViewController != self.parentViewController) {
        [self.parentViewController addChildViewController:_currentChildVc];
    }
    _currentChildVc.view.frame = self.bounds;
    [cell.contentView addSubview:_currentChildVc.view];
    [_currentChildVc didMoveToParentViewController:self.parentViewController];
    
    //    NSLog(@"当前的index:%ld", indexPath.row);
    if (_isLoadFirstView) {
        
        if (self.forbidTouchToAdjustPosition && !_changeAnimated) {
            [self willAppearWithIndex:_currentIndex];
            if (isFirstLoaded) {
                // viewDidLoad
                if ([_currentChildVc respondsToSelector:@selector(zj_viewDidLoadForIndex:)]) {
                    [_currentChildVc zj_viewDidLoadForIndex:indexPath.row];
                }
            }
            [self didAppearWithIndex:_currentIndex];
            
        }
        else {
            [self willAppearWithIndex:indexPath.row];
            if (isFirstLoaded) {
                // viewDidLoad
                if ([_currentChildVc respondsToSelector:@selector(zj_viewDidLoadForIndex:)]) {
                    [_currentChildVc zj_viewDidLoadForIndex:indexPath.row];
                }
            }
            [self didAppearWithIndex:indexPath.row];
            
        }
        _isLoadFirstView = NO;
    }
    else {
        if (self.forbidTouchToAdjustPosition && !_changeAnimated) {
            [self willAppearWithIndex:_currentIndex];
            if (isFirstLoaded) {
                // viewDidLoad
                if ([_currentChildVc respondsToSelector:@selector(zj_viewDidLoadForIndex:)]) {
                    [_currentChildVc zj_viewDidLoadForIndex:indexPath.row];
                }
            }
            [self didAppearWithIndex:_currentIndex];
            
        }
        else {
            [self willAppearWithIndex:indexPath.row];
            if (isFirstLoaded) {
                // viewDidLoad
                if ([_currentChildVc respondsToSelector:@selector(zj_viewDidLoadForIndex:)]) {
                    [_currentChildVc zj_viewDidLoadForIndex:indexPath.row];
                }
            }
            [self willDisappearWithIndex:_oldIndex];
            
        }
    }
    

}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
//    NSLog(@"出现出现:current:---- %ld   old ----- %ld indexpathRow----%ld ", _currentIndex, _oldIndex, indexPath.row);
    if (_sysVersion >= 8) {
        [self setupChildVcForCell:cell atIndexPath:indexPath];
    }

}

- (NSInteger)getCurrentShowIndex {
    return (NSInteger)(_collectionView.contentOffset.x / self.bounds.size.width);
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
//    NSLog(@"消失消失:current:---- %ld   old ----- %ld indexpathRow----%ld ", _currentIndex, _oldIndex, indexPath.row);

    // Modified by wangyunpeng: 原来finishIndex的位置，写的是_currentIndex，但是currentIndex在左滑不放手后再右滑回来放手（即，回到了原位），这种情况下，currentIndex始终不变，导致回到原位后，还是调用后一个index对应VC的didappear
    NSInteger finishIndex = collectionView.contentOffset.x / self.bounds.size.width;
    if (finishIndex == indexPath.row) {// 没有滚动完成
        

        if (_needManageLifeCycle) {
            UIViewController<ZJScrollPageViewChildVcDelegate> *currentVc = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)_currentIndex]];
            // 开始出现
            [currentVc beginAppearanceTransition:YES animated:NO];
            
            UIViewController<ZJScrollPageViewChildVcDelegate> *oldVc = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)indexPath.row]];
            // 开始消失
            [oldVc beginAppearanceTransition:NO animated:NO];
            
        }

        [self didAppearWithIndex:finishIndex];
        [self didDisappearWithIndex:indexPath.row];
    }
    else {
        
       
        if (_oldIndex == indexPath.row) {
            // 滚动完成
            if (self.forbidTouchToAdjustPosition && !_changeAnimated) {
                [self willDisappearWithIndex:_oldIndex];
                [self didDisappearWithIndex:_oldIndex];
            }
            else {
                [self didAppearWithIndex:_currentIndex];
                [self didDisappearWithIndex:indexPath.row];

  
            }
        }
        else {
             // 滚动没有完成又快速的反向打开了另一页
            if (_needManageLifeCycle) {
                UIViewController<ZJScrollPageViewChildVcDelegate> *currentVc = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)_oldIndex]];
                // 开始出现
                [currentVc beginAppearanceTransition:YES animated:NO];
                
                UIViewController<ZJScrollPageViewChildVcDelegate> *oldVc = [self.childVcsDic valueForKey:[NSString stringWithFormat:@"%ld", (long)indexPath.row]];
                // 开始消失
                [oldVc beginAppearanceTransition:NO animated:NO];
                // 消失
            }
            [self didAppearWithIndex:_oldIndex];
            [self didDisappearWithIndex:indexPath.row];
        }
        


    }
}

#pragma mark - getter --- setter

- (void)setCurrentIndex:(NSInteger)currentIndex {
    if (_currentIndex != currentIndex) {
        _currentIndex = currentIndex;
        if (self.segmentView.segmentStyle.isAdjustTitleWhenBeginDrag) {
            [self adjustSegmentTitleOffsetToCurrentIndex:currentIndex];
        }

    }
}

- (ZJCollectionView *)collectionView {
    if (_collectionView == nil) {
        ZJCollectionView *collectionView = [[ZJCollectionView alloc] initWithFrame:self.bounds collectionViewLayout:self.collectionViewLayout];
        [collectionView setBackgroundColor:[UIColor whiteColor]];
        collectionView.pagingEnabled = YES;
        collectionView.scrollsToTop = NO;
        collectionView.showsHorizontalScrollIndicator = NO;
        collectionView.delegate = self;
        collectionView.dataSource = self;
        collectionView.bounces = YES;
        [collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:cellID];
        collectionView.bounces = self.segmentView.segmentStyle.isContentViewBounces;
        collectionView.scrollEnabled = self.segmentView.segmentStyle.isScrollContentView;
        [self addSubview:collectionView];
        _collectionView = collectionView;
    }
    return _collectionView;
}

- (UICollectionViewFlowLayout *)collectionViewLayout {
    if (_collectionViewLayout == nil) {
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.itemSize = self.bounds.size;
        layout.minimumLineSpacing = 0.0;
        layout.minimumInteritemSpacing = 0.0;
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        _collectionViewLayout = layout;
    }
    
    return _collectionViewLayout;
}


- (NSMutableDictionary<NSString *,UIViewController<ZJScrollPageViewChildVcDelegate> *> *)childVcsDic {
    if (!_childVcsDic) {
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        _childVcsDic = dic;
    }
    return _childVcsDic;
}

@end
