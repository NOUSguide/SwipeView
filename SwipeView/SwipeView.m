//
//  SwipeView.m
//
//  Version 1.3.2
//
//  Created by Nick Lockwood on 03/09/2010.
//  Copyright 2010 Charcoal Design
//
//  Distributed under the permissive zlib License
//  Get the latest version of SwipeView from here:
//
//  https://github.com/nicklockwood/SwipeView
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//


#import "SwipeView.h"
#import <objc/message.h>
#import <iOSHelper.h>

#pragma GCC diagnostic ignored "-Wdirect-ivar-access"
#pragma GCC diagnostic ignored "-Warc-repeated-use-of-weak"
#pragma GCC diagnostic ignored "-Wreceiver-is-weak"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wselector"
#pragma GCC diagnostic ignored "-Wgnu"


#import <Availability.h>
#if !__has_feature(objc_arc)
#error This class requires automatic reference counting
#endif


@implementation NSObject (SwipeView)

- (CGSize)swipeViewItemSize:(__unused SwipeView *)swipeView { return CGSizeZero; }
- (void)swipeViewDidScroll:(__unused SwipeView *)swipeView {}
- (void)swipeViewCurrentItemIndexDidChange:(__unused SwipeView *)swipeView {}
- (void)swipeViewWillBeginDragging:(__unused SwipeView *)swipeView {}
- (void)swipeViewDidEndDragging:(__unused SwipeView *)swipeView willDecelerate:(__unused BOOL)decelerate {}
- (void)swipeViewWillBeginDecelerating:(__unused SwipeView *)swipeView {}
- (void)swipeViewDidEndDecelerating:(__unused SwipeView *)swipeView {}
- (void)swipeViewDidEndScrollingAnimation:(__unused SwipeView *)swipeView {}
- (BOOL)swipeView:(__unused SwipeView *)swipeView shouldSelectItemAtIndex:(__unused NSInteger)index { return YES; }
- (void)swipeView:(__unused SwipeView *)swipeView didSelectItemAtIndex:(__unused NSInteger)index {}

@end


@interface SwipeView () <UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) CAGradientLayer *leftRightFadeOutGradientLayer;
@property (nonatomic, strong) NSMutableDictionary *itemViews;
@property (nonatomic, strong) NSMutableSet *itemViewPool;
@property (nonatomic, assign) NSInteger previousItemIndex;
@property (nonatomic, assign) CGPoint previousContentOffset;
@property (nonatomic, assign) CGSize itemSize;
@property (nonatomic, assign) BOOL suppressScrollEvent;
@property (nonatomic, assign) NSTimeInterval scrollDuration;
@property (nonatomic, assign, getter = isScrolling) BOOL scrolling;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval lastTime;
@property (nonatomic, assign) CGFloat startOffset;
@property (nonatomic, assign) CGFloat endOffset;
@property (nonatomic, assign) CGFloat lastUpdateOffset;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) CGFloat currentNewItemSlotFrameCenter;
@property (nonatomic, strong) CAScrollLayer *scrollLayer;
@property (nonatomic, strong) NSMutableArray *itemInsertionItems;
@property (nonatomic, strong) NSMutableArray *currentCenterXSlots;
@property (nonatomic, assign) NSInteger indexOfCurrentNewItemSlot;

@end


@implementation SwipeView

#pragma mark -
#pragma mark Initialisation

- (void)setUp
{
    _scrollEnabled = YES;
    _pagingEnabled = YES;
    _delaysContentTouches = YES;
    _bounces = YES;
    _wrapEnabled = NO;
    _itemsPerPage = 1;
    _truncateFinalPage = NO;
    _defersItemViewLoading = NO;
    _vertical = NO;
    _itemInsertionState = SwipeViewItemInsertionStateInactive;
    _itemInsertionItems = [NSMutableArray array];
    _currentCenterXSlots = [NSMutableArray array];
    _indexOfCurrentNewItemSlot = NSNotFound;
    
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _scrollView.autoresizesSubviews = YES;
    _scrollView.delegate = self;
    _scrollView.delaysContentTouches = _delaysContentTouches;
    _scrollView.bounces = _bounces && !_wrapEnabled;
    _scrollView.alwaysBounceHorizontal = !_vertical && _bounces;
    _scrollView.alwaysBounceVertical = _vertical && _bounces;
    _scrollView.pagingEnabled = _pagingEnabled;
    _scrollView.scrollEnabled = _scrollEnabled;
    _scrollView.decelerationRate = _decelerationRate;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.scrollsToTop = NO;
    _scrollView.clipsToBounds = NO;
    
    _decelerationRate = _scrollView.decelerationRate;
    _itemViews = [[NSMutableDictionary alloc] init];
    _previousItemIndex = 0;
    _previousContentOffset = _scrollView.contentOffset;
    _scrollOffset = 0.0f;
    _currentItemIndex = 0;
    _numberOfItems = 0;
    _currentNewItemSlotFrameCenter = -1.f;
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTap:)];
    tapGesture.delegate = self;
    [_scrollView addGestureRecognizer:tapGesture];
    
    self.clipsToBounds = YES;
    
    //place scrollview at bottom of hierarchy
    [self insertSubview:_scrollView atIndex:0];
    
    if (_dataSource)
    {
        [self reloadData];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder:aDecoder]))
    {
        [self setUp];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        [self setUp];
    }
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
}

- (void)setDataSource:(id<SwipeViewDataSource>)dataSource
{
    if (_dataSource != dataSource)
    {
        _dataSource = dataSource;
        if (_dataSource)
        {
            [self reloadData];
        }
    }
}

- (void)setDelegate:(id<SwipeViewDelegate>)delegate
{
    if (_delegate != delegate)
    {
        _delegate = delegate;
        [self setNeedsLayout];
    }
}

- (void)setAlignment:(SwipeViewAlignment)alignment
{
    if (_alignment != alignment)
    {
        _alignment = alignment;
        [self setNeedsLayout];
    }
}

- (void)setItemsPerPage:(NSInteger)itemsPerPage
{
    if (_itemsPerPage != itemsPerPage)
    {
        _itemsPerPage = itemsPerPage;
        [self setNeedsLayout];
    }
}

- (void)setTruncateFinalPage:(BOOL)truncateFinalPage
{
    if (_truncateFinalPage != truncateFinalPage)
    {
        _truncateFinalPage = truncateFinalPage;
        [self setNeedsLayout];
    }
}

- (void)setScrollEnabled:(BOOL)scrollEnabled
{
    if (_scrollEnabled != scrollEnabled)
    {
        _scrollEnabled = scrollEnabled;
        _scrollView.scrollEnabled = _scrollEnabled;
    }
}

- (void)setPagingEnabled:(BOOL)pagingEnabled
{
    if (_pagingEnabled != pagingEnabled)
    {
        _pagingEnabled = pagingEnabled;
        _scrollView.pagingEnabled = pagingEnabled;
        [self setNeedsLayout];
    }
}

- (void)setWrapEnabled:(BOOL)wrapEnabled
{
    if (_wrapEnabled != wrapEnabled)
    {
        CGFloat previousOffset = [self clampedOffset:_scrollOffset];
        _wrapEnabled = wrapEnabled;
        _scrollView.bounces = _bounces && !_wrapEnabled;
        [self setNeedsLayout];
        [self layoutIfNeeded];
        self.scrollOffset = previousOffset;
    }
}

- (void)setDelaysContentTouches:(BOOL)delaysContentTouches
{
    _delaysContentTouches = delaysContentTouches;
    _scrollView.delaysContentTouches = delaysContentTouches;
}

- (void)setBounces:(BOOL)bounces
{
    if (_bounces != bounces)
    {
        _bounces = bounces;
        _scrollView.alwaysBounceHorizontal = !_vertical && _bounces;
        _scrollView.alwaysBounceVertical = _vertical && _bounces;
        _scrollView.bounces = _bounces && !_wrapEnabled;
    }
}

- (void)setDecelerationRate:(float)decelerationRate
{
    if (fabsf(_decelerationRate - decelerationRate) > 0.0001f)
    {
        _decelerationRate = decelerationRate;
        _scrollView.decelerationRate = _decelerationRate;
    }
}

- (void)setAutoscroll:(CGFloat)autoscroll
{
    if (fabsf(_autoscroll - autoscroll) > 0.0001f)
    {
        _autoscroll = autoscroll;
        if (autoscroll) [self startAnimation];
    }
}

- (void)setVertical:(BOOL)vertical
{
    if (_vertical != vertical)
    {
        _vertical = vertical;
        _scrollView.alwaysBounceHorizontal = !_vertical && _bounces;
        _scrollView.alwaysBounceVertical = _vertical && _bounces;
        [self setNeedsLayout];
    }
}

- (BOOL)isDragging
{
    return _scrollView.dragging;
}

- (BOOL)isDecelerating
{
    return _scrollView.decelerating;
}

- (void)setBackgroundView:(UIView *)backgroundView {
    if (_backgroundView != nil) [_backgroundView removeFromSuperview];

    _backgroundView = backgroundView;
    
    [self insertSubview:_backgroundView atIndex:0];
}

- (void)setScrollableBackgroundImage:(UIImage *)scrollableBackgroundImage {
    _scrollableBackgroundImage = scrollableBackgroundImage;
    
    if (_backgroundView == nil) {
        self.backgroundView = [UIView new];
        _backgroundView.frameSize = self.frameSize;
        [self setBackgroundView:_backgroundView];
    }
    
    if (_scrollLayer == nil) {
        self.scrollLayer = [CAScrollLayer layer];
        _scrollLayer.transform = CATransform3DMakeScale(1.0, -1.0, 1.0);
        _scrollLayer.scrollMode = kCAScrollVertically;
        _scrollLayer.position = CGPointMake(_backgroundView.center.x, _backgroundView.center.y);
        [_backgroundView.layer addSublayer:_scrollLayer];
    }
    
    _scrollLayer.backgroundColor = [UIColor colorWithPatternImage:scrollableBackgroundImage].CGColor;
}

- (void)setFadeOutLeftAndRight:(BOOL)fadeOutLeftAndRight {
    _fadeOutLeftAndRight = fadeOutLeftAndRight;
    
    if (_fadeOutLeftAndRight) {
        self.leftRightFadeOutGradientLayer = [CAGradientLayer layer];
        _leftRightFadeOutGradientLayer.locations = @[[NSNumber numberWithFloat:0.0],
                                                     [NSNumber numberWithFloat:0.03],
                                                     [NSNumber numberWithFloat:0.97],
                                                     [NSNumber numberWithFloat:1.0]];
        _leftRightFadeOutGradientLayer.colors = [NSArray arrayWithObjects:(id)[UIColor clearColor].CGColor, (id)[UIColor whiteColor].CGColor, (id)[UIColor whiteColor].CGColor, (id)[UIColor clearColor].CGColor, nil];
        _leftRightFadeOutGradientLayer.anchorPoint = CGPointZero;
        _leftRightFadeOutGradientLayer.startPoint = CGPointMake(0.0f, 0.5f);
        _leftRightFadeOutGradientLayer.endPoint = CGPointMake(1.0f, 0.5f);
        self.layer.mask = _leftRightFadeOutGradientLayer;
    }
}

- (void)setItemInsertionState:(SwipeViewItemInsertionState)itemInsertionState {
    _itemInsertionState = itemInsertionState;
    
    switch (_itemInsertionState) {
        case SwipeViewItemInsertionStateInactive:
            break;
        case SwipeViewItemInsertionStateStarted: {
            //stop scrolling
            [_scrollView setContentOffset:_scrollView.contentOffset animated:NO];
            //add all really visible items to the array
            for (UIView *v in [self visibleItemViews]) {
                CGRect convertedRect = [_scrollView convertRect:v.frame toView:self];
                if (CGRectIntersectsRect(convertedRect, _scrollView.frame)) {
                    [_itemInsertionItems addObject:v];
                    [_currentCenterXSlots addObject:@(v.center.x)];
                }
//                if (CGRectContainsRect(_scrollView.frame, convertedRect)) {
//                    [_itemInsertionItems addObject:v];
//                }
            }
//            NSLog(@"items: %@", _itemInsertionItems);
//            NSLog(@"slots: %@", _currentCenterXSlots);

        } break;
        case SwipeViewItemInsertionStateEnded: {
            
            [_itemInsertionItems removeAllObjects];
            [_currentCenterXSlots removeAllObjects];
        } break;
        default:
            break;
    }
}

#pragma mark -
#pragma mark View management

- (NSArray *)indexesForVisibleItems
{
    return [[_itemViews allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray *)visibleItemViews
{
    NSArray *indexes = [self indexesForVisibleItems];
    return [_itemViews objectsForKeys:indexes notFoundMarker:[NSNull null]];
}

- (NSArray *)visibleItemViewsSortedByFrameOriginXAscending {
    NSArray *views = [self visibleItemViews];
    NSComparator comparatorBlock = ^(UIView *obj1, UIView *obj2) {
        if (obj1.frame.origin.x > obj2.frame.origin.x) {
            return (NSComparisonResult)NSOrderedDescending;
        }
        
        if (obj1.frame.origin.x < obj2.frame.origin.x) {
            return (NSComparisonResult)NSOrderedAscending;
        }
        return (NSComparisonResult)NSOrderedSame;
    };
    
    return [views sortedArrayUsingComparator:comparatorBlock];
}

- (void)movedInsertionView:(UIView *)insertionView {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(animateViewsAwayFromView:) object:insertionView];
    if (_itemInsertionState == SwipeViewItemInsertionStateStarted) {
        //find new slot to insert item right now
        CGRect convertedRect = [insertionView.superview convertRect:insertionView.frame toView:_scrollView];
        CGFloat centerX = convertedRect.origin.x + convertedRect.size.width/2.f;
        
        //find nearest slotindex
        CGFloat distance = MAXFLOAT;
        int counter = 0;
        for (NSNumber *n in _currentCenterXSlots) {
            CGFloat dist = fabsf(n.floatValue - centerX);
            if (dist < distance) {
                _indexOfCurrentNewItemSlot = counter;
            }
            distance = dist;
            
            counter++;
        }
        
//        KGLogRect(convertedRect);
//        NSLog(@"centerx: %f", convertedRect.origin.x + convertedRect.size.width/2.f);
        
        //move away the other items
        [self performSelector:@selector(animateViewsAwayFromView:) withObject:insertionView afterDelay:0.25];
    }
}

- (void)animateViewsAwayFromView:(UIView *)view {
    
    
    
    
    
    
    
    
    
    
    
    return;
    CGRect rectConvertedToScrollView = [view.superview convertRect:view.frame toView:_scrollView];
    CGPoint centerOfConvertedView = KGRectCenter(rectConvertedToScrollView);
    //if there already is a slot for the new item
    if (_currentNewItemSlotFrameCenter > -1) {
        //do nothing if new item moves arounds somewhere next to the slot
        if (centerOfConvertedView.x > _currentNewItemSlotFrameCenter - _itemSize.width && centerOfConvertedView.x < _currentNewItemSlotFrameCenter + _itemSize.width) {
            NSLog(@"is in area of new slot, returning with no animation");
            return;
        }
    }
    
    //find new slot
    CGFloat distance = CGFLOAT_MAX;
    UIView *minDistanceView = nil;
    NSArray *items = [self visibleItemViewsSortedByFrameOriginXAscending];
    for (UIView *v in items) {
        CGFloat dist = KGDistanceBetweenCGPoints(v.center, centerOfConvertedView);
        if (dist < distance) minDistanceView = v;
        distance = MIN(dist, distance);
    }
    _currentNewItemSlotFrameCenter = minDistanceView.center.x;
    
    //animate views lef/right depending on current position of this view
    
    NSMutableArray *intersectingViews = [NSMutableArray array];
    
    for (UIView *v in items) {
        if (v.frameLeft - _itemSize.width/4.f >= _scrollView.contentOffset.x && v.frameRight + _itemSize.width/4.f <= _scrollView.contentOffset.x + _scrollView.frameWidth) {
            NSLog(@"view with index %i is inside", v.tag);
            [intersectingViews addObject:v];
        }
//        CGRect rect = [self convertRect:v.frame fromView:_scrollView];
//        NSLog(@"x: %f, offset: %f", v.frameLeft, _scrollView.contentOffset.x);
//        if (CGRectIntersectsRect(v.frame, rectConvertedToScrollView)) {
//            [intersectingViews addObject:v];
//        }
    }

    //now we have views that could be moved left/right to give space for the new item
    //decide if we move those left or right
    
    
    //two views intersect. decide which one to move  (left/right)
    if (intersectingViews.count == 2) {
        UIView *theView = nil;
        UIView *v1 = intersectingViews[0];
        UIView *v2 = intersectingViews[1];
        
        CGFloat dist1 = KGDistanceBetweenCGPoints(v1.center, KGRectCenter(rectConvertedToScrollView));
        CGFloat dist2 = KGDistanceBetweenCGPoints(v2.center, KGRectCenter(rectConvertedToScrollView));
        NSLog(@"d1: %f, d2: %f", dist1, dist2);
        //view 1 is nearer
        BOOL useFirst = (dist1 < dist2);
        theView = useFirst ? v1 : v2;
        
        int moveLeftIndex = [items indexOfObject:theView] + (useFirst ? 0 : 1);
//        CGRect rect = [self convertRect:theView.frame fromView:_scrollView];
        CGFloat posX = theView.frame.origin.x;
        _currentNewItemSlotFrameCenter = theView.center.x;
        
        [UIView animateWithDuration:.25f delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            for (int i = 0; i < items.count; i++) {
                UIView *v = items[i];
                
                if (i <= moveLeftIndex) {
                    v.frameLeft = posX + ((i - moveLeftIndex - 1) * _itemSize.width);
                }
                else {
                    v.frameLeft = posX + ((i - moveLeftIndex) * _itemSize.width);
                }
            }
        } completion:^ (BOOL completed) {
            
        }];
    }
    
    
    
    
    
    
}

- (UIView *)itemViewAtIndex:(NSInteger)index
{
    return _itemViews[@(index)];
}

- (UIView *)currentItemView
{
    return [self itemViewAtIndex:_currentItemIndex];
}

- (NSInteger)indexOfItemView:(UIView *)view
{
    NSUInteger index = [[_itemViews allValues] indexOfObject:view];
    if (index != NSNotFound)
    {
        return [[_itemViews allKeys][index] integerValue];
    }
    return NSNotFound;
}

- (NSInteger)indexOfItemViewOrSubview:(UIView *)view
{
    NSInteger index = [self indexOfItemView:view];
    if (index == NSNotFound && view != nil && view != _scrollView)
    {
        return [self indexOfItemViewOrSubview:view.superview];
    }
    return index;
}

- (void)setItemView:(UIView *)view forIndex:(NSInteger)index
{
    ((NSMutableDictionary *)_itemViews)[@(index)] = view;
}


#pragma mark -
#pragma mark View layout

- (void)updateScrollOffset
{
    if (_wrapEnabled)
    {
        CGFloat itemsWide = (_numberOfItems == 1)? 1.0f: 3.0f;
        if (_vertical)
        {
            CGFloat scrollHeight = _scrollView.contentSize.height / itemsWide;
            if (_scrollView.contentOffset.y < scrollHeight)
            {
                _previousContentOffset.y += scrollHeight;
                [self setContentOffsetWithoutEvent:CGPointMake(0.0f, _scrollView.contentOffset.y + scrollHeight)];
            }
            else if (_scrollView.contentOffset.y >= scrollHeight * 2.0f)
            {
                _previousContentOffset.y -= scrollHeight;
                [self setContentOffsetWithoutEvent:CGPointMake(0.0f, _scrollView.contentOffset.y - scrollHeight)];
            }
            _scrollOffset = [self clampedOffset:_scrollOffset];
        }
        else
        {
            CGFloat scrollWidth = _scrollView.contentSize.width / itemsWide;
            if (_scrollView.contentOffset.x < scrollWidth)
            {
                _previousContentOffset.x += scrollWidth;
                [self setContentOffsetWithoutEvent:CGPointMake(_scrollView.contentOffset.x + scrollWidth, 0.0f)];
            }
            else if (_scrollView.contentOffset.x >= scrollWidth * 2.0f)
            {
                _previousContentOffset.x -= scrollWidth;
                [self setContentOffsetWithoutEvent:CGPointMake(_scrollView.contentOffset.x - scrollWidth, 0.0f)];
            }
            _scrollOffset = [self clampedOffset:_scrollOffset];
        }
    }
    if (_vertical && fabsf(_scrollView.contentOffset.x) > 0.0001f)
    {
        [self setContentOffsetWithoutEvent:CGPointMake(0.0f, _scrollView.contentOffset.y)];
    }
    else if (!_vertical && fabsf(_scrollView.contentOffset.y) > 0.0001f)
    {
        [self setContentOffsetWithoutEvent:CGPointMake(_scrollView.contentOffset.x, 0.0f)];
    }
}

- (void)updateScrollViewDimensions
{
    CGRect frame = self.bounds;
    CGSize contentSize = frame.size;
    
    if (_vertical)
    {
        contentSize.width -= (_scrollView.contentInset.left + _scrollView.contentInset.right);
    }
    else
    {
        contentSize.height -= (_scrollView.contentInset.top + _scrollView.contentInset.bottom);
    }
    
    switch (_alignment)
    {
        case SwipeViewAlignmentCenter:
        {
            if (_vertical)
            {
                frame = CGRectMake(0.0f, (self.bounds.size.height - _itemSize.height * _itemsPerPage)/2.0f,
                                   self.bounds.size.width, _itemSize.height * _itemsPerPage);
                contentSize.height = _itemSize.height * _numberOfItems;
            }
            else
            {
                frame = CGRectMake((self.bounds.size.width - _itemSize.width * _itemsPerPage)/2.0f,
                                   0.0f, _itemSize.width * _itemsPerPage, self.bounds.size.height);
                contentSize.width = _itemSize.width * _numberOfItems;
            }
            break;
        }
        case SwipeViewAlignmentEdge:
        {
            if (_vertical)
            {
                frame = CGRectMake(0.0f, 0.0f, self.bounds.size.width, _itemSize.height * _itemsPerPage);
                contentSize.height = _itemSize.height * _numberOfItems - (self.bounds.size.height - frame.size.height);
            }
            else
            {
                frame = CGRectMake(0.0f, 0.0f, _itemSize.width * _itemsPerPage, self.bounds.size.height);
                contentSize.width = _itemSize.width * _numberOfItems - (self.bounds.size.width - frame.size.width);
            }
            break;
        }
    }
    
    if (_wrapEnabled)
    {
        CGFloat itemsWide = (_numberOfItems == 1)? 1.0f: _numberOfItems * 3.0f;
        if (_vertical)
        {
            contentSize.height = _itemSize.height * itemsWide;
        }
        else
        {
            contentSize.width = _itemSize.width * itemsWide;
        }
    }
    else if (_pagingEnabled && !_truncateFinalPage)
    {
        if (_vertical)
        {
            contentSize.height = ceilf(contentSize.height / frame.size.height) * frame.size.height;
        }
        else
        {
            contentSize.width = ceilf(contentSize.width / frame.size.width) * frame.size.width;
        }
    }
    
    if (!CGRectEqualToRect(_scrollView.frame, frame))
    {
        _scrollView.frame = frame;
    }
    
    if (!CGSizeEqualToSize(_scrollView.contentSize, contentSize))
    {
        _scrollView.contentSize = contentSize;
    }
}

- (CGFloat)offsetForItemAtIndex:(NSInteger)index
{
    //calculate relative position
    CGFloat offset = index - _scrollOffset;
    if (_wrapEnabled)
    {
        if (_alignment == SwipeViewAlignmentCenter)
        {
            if (offset > _numberOfItems/2)
            {
                offset -= _numberOfItems;
            }
            else if (offset < -_numberOfItems/2)
            {
                offset += _numberOfItems;
            }
        }
        else
        {
            CGFloat width = _vertical? self.bounds.size.height: self.bounds.size.width;
            CGFloat x = _vertical? _scrollView.frame.origin.y: _scrollView.frame.origin.x;
            CGFloat itemWidth = _vertical? _itemSize.height: _itemSize.width;
            if (offset * itemWidth + x > width)
            {
                offset -= _numberOfItems;
            }
            else if (offset * itemWidth + x < -itemWidth)
            {
                offset += _numberOfItems;
            }
        }
    }
    return offset;
}

- (void)setFrameForView:(UIView *)view atIndex:(NSInteger)index
{
    if (self.window)
    {
        CGPoint center = view.center;
        if (_vertical)
        {
            center.y = ([self offsetForItemAtIndex:index] + 0.5f) * _itemSize.height + _scrollView.contentOffset.y;
        }
        else
        {
            center.x = ([self offsetForItemAtIndex:index] + 0.5f) * _itemSize.width + _scrollView.contentOffset.x;
        }
        
        BOOL disableAnimation = !CGPointEqualToPoint(center, view.center);
        BOOL animationEnabled = [UIView areAnimationsEnabled];
        if (disableAnimation && animationEnabled) [UIView setAnimationsEnabled:NO];
        
        if (_vertical)
        {
            view.center = CGPointMake(_scrollView.frame.size.width/2.0f, center.y);
        }
        else
        {
            view.center = CGPointMake(center.x, _scrollView.frame.size.height/2.0f);
        }
        
        view.bounds = CGRectMake(0.0f, 0.0f, _itemSize.width, _itemSize.height);
        
        if (disableAnimation && animationEnabled) [UIView setAnimationsEnabled:YES];
    }
}

- (void)layOutItemViews
{
    for (UIView *view in self.visibleItemViews)
    {
        [self setFrameForView:view atIndex:[self indexOfItemView:view]];
    }
}

- (void)updateLayout
{
    [self updateScrollOffset];
    [self loadUnloadViews];
    [self layOutItemViews];
    
    if (_backgroundView != nil) {
        _backgroundView.frame = _scrollView.frame;
        
        if (_scrollLayer != nil) {
            _scrollLayer.bounds = CGRectMake(0, 0, _backgroundView.bounds.size.width, _backgroundView.bounds.size.height);
        }
    }
    
    if (_leftRightFadeOutGradientLayer) {
        _leftRightFadeOutGradientLayer.bounds = CGRectMake(0.f, 0.f, self.frameWidth, self.frameHeight);
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self updateItemSizeAndCount];
    [self updateScrollViewDimensions];
    [self updateLayout];
    if (_pagingEnabled && !_scrolling)
    {
        [self scrollToItemAtIndex:self.currentItemIndex duration:0.25];
    }
}

#pragma mark -
#pragma mark View queing

- (void)queueItemView:(UIView *)view
{
    if (view)
    {
        [_itemViewPool addObject:view];
    }
}

- (UIView *)dequeueItemView
{
    UIView *view = [_itemViewPool anyObject];
    if (view)
    {
        [_itemViewPool removeObject:view];
    }
    return view;
}


#pragma mark -
#pragma mark Scrolling

- (void)didScroll
{
    //handle wrap
    [self updateScrollOffset];
    
    //update view
    [self layOutItemViews];
    
    if (_scrollLayer != nil) {
        [CATransaction begin];
        [CATransaction setValue:[NSNumber numberWithFloat:0.0f] forKey:kCATransactionAnimationDuration];
        [_scrollLayer scrollToPoint:CGPointMake(0.f, -_scrollView.contentOffset.y)]; //invert the offset because the CAScrollLayer is scaled to flip the background image
        [CATransaction commit];
    }
    
    [_delegate swipeViewDidScroll:self];
    
    if (!_defersItemViewLoading || fabsf([self minScrollDistanceFromOffset:_lastUpdateOffset toOffset:_scrollOffset]) >= 1.0f)
    {
        //update item index
        _currentItemIndex = [self clampedIndex:roundf(_scrollOffset)];
        
        //load views
        _lastUpdateOffset = _currentItemIndex;
        [self loadUnloadViews];
        
        //send index update event
        if (_previousItemIndex != _currentItemIndex)
        {
            _previousItemIndex = _currentItemIndex;
            [_delegate swipeViewCurrentItemIndexDidChange:self];
        }
    }
}

- (CGFloat)easeInOut:(CGFloat)time
{
    return (time < 0.5f)? 0.5f * powf(time * 2.0f, 3.0f): 0.5f * powf(time * 2.0f - 2.0f, 3.0f) + 1.0f;
}

- (void)step
{
    NSTimeInterval currentTime = CFAbsoluteTimeGetCurrent();
    double delta = _lastTime - currentTime;
    _lastTime = currentTime;
    
    if (_scrolling)
    {
        NSTimeInterval time = fminf(1.0f, (currentTime - _startTime) / _scrollDuration);
        delta = [self easeInOut:time];
        _scrollOffset = [self clampedOffset:_startOffset + (_endOffset - _startOffset) * delta];
        if (_vertical)
        {
            [self setContentOffsetWithoutEvent:CGPointMake(0.0f, _scrollOffset * _itemSize.height)];
        }
        else
        {
            [self setContentOffsetWithoutEvent:CGPointMake(_scrollOffset * _itemSize.width, 0.0f)];
        }
        [self didScroll];
        if (time == 1.0f)
        {
            _scrolling = NO;
            [self didScroll];
            [_delegate swipeViewDidEndScrollingAnimation:self];
        }
    }
    else if (_autoscroll)
    {
        if (!_scrollView.dragging) self.scrollOffset = [self clampedOffset:_scrollOffset + delta * _autoscroll];
    }
    else
    {
        [self stopAnimation];
    }
}

- (void)startAnimation
{
    if (!_timer)
    {
        self.timer = [NSTimer timerWithTimeInterval:1.0/60.0
                                             target:self
                                           selector:@selector(step)
                                           userInfo:nil
                                            repeats:YES];
        
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:UITrackingRunLoopMode];
    }
}

- (void)stopAnimation
{
    [_timer invalidate];
    self.timer = nil;
}

- (NSInteger)clampedIndex:(NSInteger)index
{
    if (_wrapEnabled)
    {
        return _numberOfItems? (index - floorf((CGFloat)index / (CGFloat)_numberOfItems) * _numberOfItems): 0;
    }
    else
    {
        return MIN(MAX(0, index), MAX(0, _numberOfItems - 1));
    }
}

- (CGFloat)clampedOffset:(CGFloat)offset
{
    CGFloat returnValue = 0;
    if (_wrapEnabled)
    {
        returnValue = _numberOfItems? (offset - floorf(offset / (CGFloat)_numberOfItems) * _numberOfItems): 0.0f;
    }
    else
    {
        returnValue = fminf(fmaxf(0.0f, offset), fmaxf(0.0f, (CGFloat)_numberOfItems - 1.0f));
    }
    return returnValue;
}

- (void)setContentOffsetWithoutEvent:(CGPoint)contentOffset
{
    if (!CGPointEqualToPoint(_scrollView.contentOffset, contentOffset))
    {
        BOOL animationEnabled = [UIView areAnimationsEnabled];
        if (animationEnabled) [UIView setAnimationsEnabled:NO];
        _suppressScrollEvent = YES;
        _scrollView.contentOffset = contentOffset;
        _suppressScrollEvent = NO;
        if (animationEnabled) [UIView setAnimationsEnabled:YES];
    }
}

- (NSInteger)currentPage
{
    if (_itemsPerPage > 1 && _truncateFinalPage && !_wrapEnabled &&
        _currentItemIndex > (_numberOfItems / _itemsPerPage - 1) * _itemsPerPage)
    {
        return self.numberOfPages - 1;
    }
    return roundf((float)_currentItemIndex / (float)_itemsPerPage);
}

- (NSInteger)numberOfPages
{
    return ceilf((float)self.numberOfItems / (float)_itemsPerPage);
}

- (NSInteger)minScrollDistanceFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex
{
    NSInteger directDistance = toIndex - fromIndex;
    if (_wrapEnabled)
    {
        NSInteger wrappedDistance = MIN(toIndex, fromIndex) + _numberOfItems - MAX(toIndex, fromIndex);
        if (fromIndex < toIndex)
        {
            wrappedDistance = -wrappedDistance;
        }
        return (ABS(directDistance) <= ABS(wrappedDistance))? directDistance: wrappedDistance;
    }
    return directDistance;
}

- (CGFloat)minScrollDistanceFromOffset:(CGFloat)fromOffset toOffset:(CGFloat)toOffset
{
    CGFloat directDistance = toOffset - fromOffset;
    if (_wrapEnabled)
    {
        CGFloat wrappedDistance = fminf(toOffset, fromOffset) + _numberOfItems - fmaxf(toOffset, fromOffset);
        if (fromOffset < toOffset)
        {
            wrappedDistance = -wrappedDistance;
        }
        return (fabsf(directDistance) <= fabsf(wrappedDistance))? directDistance: wrappedDistance;
    }
    return directDistance;
}

- (void)setCurrentItemIndex:(NSInteger)currentItemIndex
{
    _currentItemIndex = currentItemIndex;
    self.scrollOffset = currentItemIndex;
}

- (void)setCurrentPage:(NSInteger)currentPage
{
    if (currentPage * _itemsPerPage != _currentItemIndex)
    {
        [self scrollToPage:currentPage duration:0.0];
    }
}

- (void)setScrollOffset:(CGFloat)scrollOffset
{
    if (fabsf(_scrollOffset - scrollOffset) > 0.0001f)
    {
        _scrollOffset = scrollOffset;
        _lastUpdateOffset = _scrollOffset - 1.0f; //force refresh
        _scrolling = NO; //stop scrolling
        [self updateItemSizeAndCount];
        [self updateScrollViewDimensions];
        [self updateLayout];
        CGPoint contentOffset = _vertical? CGPointMake(0.0f, [self clampedOffset:scrollOffset] * _itemSize.height): CGPointMake([self clampedOffset:scrollOffset] * _itemSize.width, 0.0f);
        [self setContentOffsetWithoutEvent:contentOffset];
        [self didScroll];
    }
}

- (void)scrollByOffset:(CGFloat)offset duration:(NSTimeInterval)duration
{
    if (duration > 0.0)
    {
        _scrolling = YES;
        _startTime = [[NSDate date] timeIntervalSinceReferenceDate];
        _startOffset = _scrollOffset;
        _scrollDuration = duration;
        _endOffset = _startOffset + offset;
        if (!_wrapEnabled)
        {
            _endOffset = [self clampedOffset:_endOffset];
        }
        [self startAnimation];
    }
    else
    {
        self.scrollOffset += offset;
    }
}

- (void)scrollToOffset:(CGFloat)offset duration:(NSTimeInterval)duration
{
    [self scrollByOffset:[self minScrollDistanceFromOffset:_scrollOffset toOffset:offset] duration:duration];
}

- (void)scrollByNumberOfItems:(NSInteger)itemCount duration:(NSTimeInterval)duration
{
    if (duration > 0.0)
    {
        CGFloat offset = 0.0f;
        if (itemCount > 0)
        {
            offset = (floorf(_scrollOffset) + itemCount) - _scrollOffset;
        }
        else if (itemCount < 0)
        {
            offset = (ceilf(_scrollOffset) + itemCount) - _scrollOffset;
        }
        else
        {
            offset = roundf(_scrollOffset) - _scrollOffset;
        }
        [self scrollByOffset:offset duration:duration];
    }
    else
    {
        self.scrollOffset = [self clampedIndex:_previousItemIndex + itemCount];
    }
}

- (void)scrollToItemAtIndex:(NSInteger)index duration:(NSTimeInterval)duration
{
    [self scrollToOffset:index duration:duration];
}

- (void)scrollToPage:(NSInteger)page duration:(NSTimeInterval)duration
{
    NSInteger index = page * _itemsPerPage;
    if (_truncateFinalPage)
    {
        index = MIN(index, _numberOfItems - _itemsPerPage);
    }
    [self scrollToItemAtIndex:index duration:duration];
}


#pragma mark -
#pragma mark View loading

- (UIView *)loadViewAtIndex:(NSInteger)index
{
    UIView *view = [_dataSource swipeView:self viewForItemAtIndex:index reusingView:[self dequeueItemView]];
    if (view == nil)
    {
        view = [[UIView alloc] init];
    }
    
    UIView *oldView = [self itemViewAtIndex:index];
    if (oldView)
    {
        [self queueItemView:oldView];
        [oldView removeFromSuperview];
    }
    
    [self setItemView:view forIndex:index];
    [self setFrameForView:view atIndex:index];
    view.userInteractionEnabled = YES;
    [_scrollView addSubview:view];
    
    return view;
}

- (void)updateItemSizeAndCount
{
    //get number of items
    _numberOfItems = [_dataSource numberOfItemsInSwipeView:self];
    
    //get item size
    CGSize size = [_delegate swipeViewItemSize:self];
    if (!CGSizeEqualToSize(size, CGSizeZero))
    {
        _itemSize = size;
    }
    else if (_numberOfItems > 0)
    {
        UIView *view = [[self visibleItemViews] lastObject] ?: [_dataSource swipeView:self viewForItemAtIndex:0 reusingView:[self dequeueItemView]];
        _itemSize = view.frame.size;
    }
    
    //prevent crashes
    if (_itemSize.width < 0.0001) _itemSize.width = 1;
    if (_itemSize.height < 0.0001) _itemSize.height = 1;
}

- (void)loadUnloadViews
{
    //check that item size is known
    CGFloat itemWidth = _vertical? _itemSize.height: _itemSize.width;
    if (itemWidth)
    {
        //calculate offset and bounds
        CGFloat width = _vertical? self.bounds.size.height: self.bounds.size.width;
        CGFloat x = _vertical? _scrollView.frame.origin.y: _scrollView.frame.origin.x;
        
        //calculate range
        CGFloat startOffset = [self clampedOffset:_scrollOffset - x / itemWidth];
        NSInteger startIndex = floorf(startOffset);
        NSInteger numberOfVisibleItems = ceilf(width / itemWidth + (startOffset - startIndex));
        if (_defersItemViewLoading)
        {
            startIndex = _currentItemIndex - ceilf(x / itemWidth) - 1;
            numberOfVisibleItems = ceilf(width / itemWidth) + 3;
        }
        
        //create indices
        numberOfVisibleItems = MIN(numberOfVisibleItems, _numberOfItems);
        NSMutableSet *visibleIndices = [NSMutableSet setWithCapacity:numberOfVisibleItems];
        for (NSInteger i = 0; i < numberOfVisibleItems; i++)
        {
            NSInteger index = [self clampedIndex:i + startIndex];
            [visibleIndices addObject:@(index)];
        }
        
        //remove offscreen views
        for (NSNumber *number in [_itemViews allKeys])
        {
            if (![visibleIndices containsObject:number])
            {
                UIView *view = _itemViews[number];
                [self queueItemView:view];
                [view removeFromSuperview];
                [_itemViews removeObjectForKey:number];
            }
        }
        
        //add onscreen views
        for (NSNumber *number in visibleIndices)
        {
            UIView *view = _itemViews[number];
            if (view == nil)
            {
                [self loadViewAtIndex:[number integerValue]];
            }
        }
    }
}

- (void)reloadItemAtIndex:(NSInteger)index
{
    //if view is visible
    if ([self itemViewAtIndex:index])
    {
        //reload view
        [self loadViewAtIndex:index];
    }
}

- (void)reloadData
{
    //remove old views
    for (UIView *view in self.visibleItemViews)
    {
        [view removeFromSuperview];
    }
    
    //reset view pools
    self.itemViews = [NSMutableDictionary dictionary];
    self.itemViewPool = [NSMutableSet set];
    
    //get number of items
    [self updateItemSizeAndCount];

    //layout views
    [self setNeedsLayout];
    
    //fix scroll offset
    if (_numberOfItems > 0 && _scrollOffset < 0.0f)
    {
        self.scrollOffset = 0;
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *view = [super hitTest:point withEvent:event];
    if ([view isEqual:self])
    {
        for (UIView *subview in _scrollView.subviews)
        {
            CGPoint offset = CGPointMake(point.x - _scrollView.frame.origin.x + _scrollView.contentOffset.x - subview.frame.origin.x,
                                         point.y - _scrollView.frame.origin.y + _scrollView.contentOffset.y - subview.frame.origin.y);
            
            if ((view = [subview hitTest:offset withEvent:event]))
            {
                return view;
            }
        }
        return _scrollView;
    }
    return view;
}

- (void)didMoveToSuperview
{
    if (self.superview)
    {
        [self setNeedsLayout];
        if (_scrolling)
        {
            [self startAnimation];
        }
    }
    else
    {
        [self stopAnimation];
    }
}

#pragma mark -
#pragma mark Gestures and taps

- (NSInteger)viewOrSuperviewIndex:(UIView *)view
{
    if (view == nil || view == _scrollView)
    {
        return NSNotFound;
    }
    NSInteger index = [self indexOfItemView:view];
    if (index == NSNotFound)
    {
        return [self viewOrSuperviewIndex:view.superview];
    }
    return index;
}

- (BOOL)viewOrSuperviewHandlesTouches:(UIView *)view
{
    //thanks to @mattjgalloway and @shaps for idea
    //https://gist.github.com/mattjgalloway/6279363
    //https://gist.github.com/shaps80/6279008
    
    Class class = [view class];
    while (class && class != [UIView class])
    {
        unsigned int numberOfMethods;
        Method *methods = class_copyMethodList(class, &numberOfMethods);
        for (unsigned int i = 0; i < numberOfMethods; i++)
        {
            if (method_getName(methods[i]) == @selector(touchesBegan:withEvent:))
            {
                free(methods);
                return YES;
            }
        }
        if (methods) free(methods);
        class = [class superclass];
    }
    
    if (view.superview && view.superview != _scrollView)
    {
        return [self viewOrSuperviewHandlesTouches:view.superview];
    }
    
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch
{
    if ([gesture isKindOfClass:[UITapGestureRecognizer class]])
    {
        //handle tap
        NSInteger index = [self viewOrSuperviewIndex:touch.view];
        if (index != NSNotFound)
        {
            if ((_delegate && ![_delegate swipeView:self shouldSelectItemAtIndex:index]) ||
                [self viewOrSuperviewHandlesTouches:touch.view])
            {
                return NO;
            }
            else
            {
                return YES;
            }
        }
    }
    return NO;
}

- (void)didTap:(UITapGestureRecognizer *)tapGesture
{
    CGPoint point = [tapGesture locationInView:_scrollView];
    NSInteger index = _vertical? (point.y / (_itemSize.height)): (point.x / (_itemSize.width));
    if (_wrapEnabled)
    {
        index = index % _numberOfItems;
    }
    if (index >= 0 && index < _numberOfItems)
    {
        [_delegate swipeView:self didSelectItemAtIndex:index];
    }
}


#pragma mark -
#pragma mark UIScrollViewDelegate methods

- (void)scrollViewDidScroll:(__unused UIScrollView *)scrollView
{
    if (!_suppressScrollEvent)
    {
        //stop scrolling animation
        _scrolling = NO;
        
        //update scrollOffset
        CGFloat delta = _vertical? (_scrollView.contentOffset.y - _previousContentOffset.y): (_scrollView.contentOffset.x - _previousContentOffset.x);
        _previousContentOffset = _scrollView.contentOffset;
        _scrollOffset += delta / (_vertical? _itemSize.height: _itemSize.width);
        
        //update view and call delegate
        [self didScroll];
    }
    else
    {
        _previousContentOffset = _scrollView.contentOffset;
    }
}

- (void)scrollViewWillBeginDragging:(__unused UIScrollView *)scrollView
{
    [_delegate swipeViewWillBeginDragging:self];
    
    //force refresh
    _lastUpdateOffset = self.scrollOffset - 1.0f;
    [self didScroll];
}

- (void)scrollViewDidEndDragging:(__unused UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate)
    {
        //force refresh
        _lastUpdateOffset = self.scrollOffset - 1.0f;
        [self didScroll];
    }
    [_delegate swipeViewDidEndDragging:self willDecelerate:decelerate];
}

- (void)scrollViewWillBeginDecelerating:(__unused UIScrollView *)scrollView
{
    [_delegate swipeViewWillBeginDecelerating:self];
}

- (void)scrollViewDidEndDecelerating:(__unused UIScrollView *)scrollView
{
    //prevent rounding errors from accumulating
    CGFloat integerOffset = roundf(_scrollOffset);
    if (fabsf(_scrollOffset - integerOffset) < 0.01f)
    {
        _scrollOffset = integerOffset;
    }
    
    //force refresh
    _lastUpdateOffset = self.scrollOffset - 1.0f;
    [self didScroll];
    
    [_delegate swipeViewDidEndDecelerating:self];
}

@end
