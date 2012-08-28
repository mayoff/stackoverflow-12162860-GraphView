#import "GraphView.h"

#define kLayerWidth 32
#define kPointsPerSample 1
#define kSamplesPerTile (kLayerWidth / kPointsPerSample)
#define kPaddingSamples 2
#define kMaxVisibleSamples ((320 / kPointsPerSample) + 2 * kPaddingSamples)

static inline NSInteger tileForSampleIndex(NSInteger sampleIndex) {
    // I need this to round toward -∞ even if sampleIndex is negative.
    return (NSInteger)floorf((float)sampleIndex / kSamplesPerTile);
}

@implementation GraphView {

    // Each key in _tileLayers is an NSNumber whose value is a tile number.
    // The corresponding value is the CALayer that displays the tile's samples.
    // There will be tiles that don't have a corresponding layer.
    NSMutableDictionary *_tileLayers;

    // Samples are stored in _samples as instances of NSNumber.
    NSMutableArray *_samples;

    // I discard old samples from _samples when I have more than
    // kMaxTiles' worth of samples.  This is the total number of samples
    // ever collected, including discarded samples.
    NSInteger _totalSampleCount;

    // Each member of _tilesToRedraw is an NSNumber whose value
    // is a tile number to be redrawn.
    NSMutableSet *_tilesToRedraw;

    // Methods prefixed with rq_ run on redrawQueue.
    // All other methods run on the main queue.
    dispatch_queue_t _redrawQueue;
}


- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self commonInit];
    }
    return self;
}

- (void)awakeFromNib {
    [self commonInit];
}

- (void)commonInit {
    _tileLayers = [[NSMutableDictionary alloc] init];
    _samples = [[NSMutableArray alloc] init];
    _tilesToRedraw = [[NSMutableSet alloc] init];
    _redrawQueue = dispatch_queue_create("MyView tile redraw", 0);
}

- (void)dealloc {
    if (_redrawQueue != NULL) {
        dispatch_release(_redrawQueue);
    }
}

- (void)addRandomSample {
    [_samples addObject:[NSNumber numberWithFloat:120.f * ((double)arc4random() / UINT32_MAX)]];
    ++_totalSampleCount;
    [self discardSamplesIfNeeded];

    if (_totalSampleCount % kSamplesPerTile == 1) {
        [self reuseOldestTileLayerForNewestTile];
    }
    [self layoutTileLayers];
    [self queueTilesForRedrawIfAffectedByLastSample];
}

- (void)discardSamplesIfNeeded {
    if (_samples.count >= 2 * kMaxVisibleSamples) {
        [_samples removeObjectsInRange:NSMakeRange(0, _samples.count - kMaxVisibleSamples)];
    }
}

- (void)reuseOldestTileLayerForNewestTile {
    // The oldest tile's layer should no longer be visible, so I can reuse it as the new tile's layer.
    NSInteger newestTile = tileForSampleIndex(_totalSampleCount - 1);
    NSInteger reusableTile = newestTile - _tileLayers.count;
    NSNumber *reusableTileObject = [NSNumber numberWithInteger:reusableTile];
    CALayer *layer = [_tileLayers objectForKey:reusableTileObject];
    [_tileLayers removeObjectForKey:reusableTileObject];
    [_tileLayers setObject:layer forKey:[NSNumber numberWithInteger:newestTile]];

    // The reused layer needs to move instantly to its new position,
    // lest it be seen animating on top of the other layers.
    [CATransaction begin]; {
        [CATransaction setDisableActions:YES];
        layer.frame = [self frameForTile:newestTile];
    } [CATransaction commit];
}

- (void)queueTilesForRedrawIfAffectedByLastSample {
    [self queueTileForRedraw:tileForSampleIndex(_totalSampleCount - 1)];

    // This redraws the second-newest tile if the new sample is in its padding range.
    [self queueTileForRedraw:tileForSampleIndex(_totalSampleCount - 1 - kPaddingSamples)];
}

- (void)queueTileForRedraw:(NSInteger)tile {
    [_tilesToRedraw addObject:[NSNumber numberWithInteger:tile]];
    dispatch_async(_redrawQueue, ^{
        [self rq_redrawOneTile];
    });
}

- (void)layoutSubviews {
    [self adjustTileDictionary];
    [CATransaction begin]; {
        // layoutSubviews only gets called on a resize, when I will be
        // shuffling layers all over the place.  I don't want to animate
        // the layers to their new positions.
        [CATransaction setDisableActions:YES];
        [self layoutTileLayers];
    } [CATransaction commit];
    for (NSNumber *key in _tileLayers) {
        [self queueTileForRedraw:key.integerValue];
    }
}

- (void)adjustTileDictionary {
    NSInteger newestTile = tileForSampleIndex(_totalSampleCount - 1);
    // Add 1 to account for layers hanging off the left and right edges.
    NSInteger tileLayersNeeded = 1 + ceilf(self.bounds.size.width / kLayerWidth);
    NSInteger oldestTile = newestTile - tileLayersNeeded + 1;

    NSMutableArray *spareLayers = [[_tileLayers allValues] mutableCopy];
    [_tileLayers removeAllObjects];
    for (NSInteger tile = oldestTile; tile <= newestTile; ++tile) {
        CALayer *layer = [spareLayers lastObject];
        if (layer) {
            [spareLayers removeLastObject];
        } else {
            layer = [self newTileLayer];
        }
        [_tileLayers setObject:layer forKey:[NSNumber numberWithInteger:tile]];
    }

    for (CALayer *layer in spareLayers) {
        [layer removeFromSuperlayer];
    }
}

- (CALayer *)newTileLayer {
    CALayer *layer = [CALayer layer];
    layer.backgroundColor = [UIColor greenColor].CGColor;
    layer.actions = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNull null], @"contents",
        [self newTileLayerPositionAnimation], @"position",
        nil];
    [self.layer addSublayer:layer];
    return layer;
}

- (CAAnimation *)newTileLayerPositionAnimation {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position"];
    animation.duration = 0.1;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    return animation;
}

- (void)layoutTileLayers {
    [_tileLayers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        CALayer *layer = obj;
        layer.frame = [self frameForTile:[key integerValue]];
    }];
}

- (CGRect)frameForTile:(NSInteger)tile {
    CGRect myBounds = self.bounds;
    CGFloat x = [self xForTile:tile myBounds:myBounds];
    return CGRectMake(x, myBounds.origin.y, kLayerWidth, myBounds.size.height);
}

- (CGFloat)xForTile:(NSInteger)tile myBounds:(CGRect)myBounds {
    return [self xForSampleAtIndex:tile * kSamplesPerTile myBounds:myBounds];
}

- (CGFloat)xForSampleAtIndex:(NSInteger)index myBounds:(CGRect)myBounds {
    return myBounds.origin.x + myBounds.size.width - kPointsPerSample * (_totalSampleCount - index);
}

- (void)rq_redrawOneTile {
    __block NSInteger tile;
    __block CGRect bounds;
    CGPoint pointStorage[kSamplesPerTile + kPaddingSamples * 2];
    CGPoint *points = pointStorage; // A block cannot reference a local variable of array type, so I need a pointer.
    __block NSUInteger pointCount;
    dispatch_sync(dispatch_get_main_queue(), ^{
        tile = [self dequeueTileToRedrawReturningBounds:&bounds points:points pointCount:&pointCount];
    });
    if (tile == NSNotFound)
        return;

    UIImage *image = [self rq_imageWithBounds:bounds points:points pointCount:pointCount];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self setImage:image forTile:tile];
    });
}

- (UIImage *)rq_imageWithBounds:(CGRect)bounds points:(CGPoint *)points pointCount:(NSUInteger)pointCount {
    UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0); {
        CGContextRef gc = UIGraphicsGetCurrentContext();
        CGContextTranslateCTM(gc, -bounds.origin.x, -bounds.origin.y);

        [[UIColor orangeColor] setFill];
        CGContextFillRect(gc, bounds);

        [[UIColor whiteColor] setStroke];
        CGContextSetLineWidth(gc, 1.0);
        CGContextSetLineJoin(gc, kCGLineCapRound);
        CGContextBeginPath(gc);
        CGContextAddLines(gc, points, pointCount);
        CGContextStrokePath(gc);
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// I return NSNotFound if I couldn't dequeue a tile.
// The `pointsOut` array must have room for at least
// kSamplesPerTile + 2*kPaddingSamples elements.
- (NSInteger)dequeueTileToRedrawReturningBounds:(CGRect *)boundsOut points:(CGPoint *)pointsOut pointCount:(NSUInteger *)pointCountOut {
    NSInteger tile = [self dequeueTileToRedraw];
    if (tile == NSNotFound)
        return NSNotFound;

    *boundsOut = [self frameForTile:tile];

    NSInteger sampleIndex = MAX(0, tile * kSamplesPerTile - kPaddingSamples);
    NSInteger endSampleIndex = MIN(_totalSampleCount, tile * kSamplesPerTile + kSamplesPerTile + kPaddingSamples);
    NSInteger discardedSampleCount = _totalSampleCount - _samples.count;

    CGFloat x = [self xForSampleAtIndex:sampleIndex myBounds:self.bounds];
    NSUInteger count = 0;
    for ( ; sampleIndex < endSampleIndex; ++sampleIndex, ++count, x += kPointsPerSample) {
        pointsOut[count] = CGPointMake(x, [[_samples objectAtIndex:sampleIndex - discardedSampleCount] floatValue]);
    }

    *pointCountOut = count;
    return tile;
}

- (NSInteger)dequeueTileToRedraw {
    NSNumber *number = [_tilesToRedraw anyObject];
    if (number) {
        [_tilesToRedraw removeObject:number];
        return number.integerValue;
    } else {
        return NSNotFound;
    }
}

- (void)setImage:(UIImage *)image forTile:(NSInteger)tile {
    CALayer *layer = [_tileLayers objectForKey:[NSNumber numberWithInteger:tile]];
    if (layer) {
        layer.contents = (__bridge id)image.CGImage;
    }
}

@end
