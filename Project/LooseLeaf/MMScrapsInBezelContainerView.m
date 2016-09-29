//
//  MMScapBubbleContainerView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/31/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import "MMScrapsInBezelContainerView.h"
#import "MMScrapBubbleButton.h"
#import "NSThread+BlockAdditions.h"
#import "MMScrapSidebarContentView.h"
#import "MMScrapsInSidebarState.h"
#import "MMImmutableScrapsOnPaperState.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "NSFileManager+DirectoryOptimizations.h"
#import "MMRotationManager.h"
#import "UIView+Debug.h"
#import "MMImmutableScrapsInSidebarState.h"
#import "MMTrashManager.h"
#import "MMSidebarButtonTapGestureRecognizer.h"


@implementation MMScrapsInBezelContainerView {
    CGFloat lastRotationReading;
    NSMutableDictionary* bubbleForScrap;
    MMScrapsInSidebarState* sidebarScrapState;
    NSString* scrapIDsPath;

    NSMutableDictionary* rotationAdjustments;
}

@synthesize bubbleDelegate;
@synthesize sidebarScrapState;

- (id)initWithFrame:(CGRect)frame andCountButton:(MMCountBubbleButton*)_countButton {
    if (self = [super initWithFrame:frame andCountButton:_countButton]) {
        bubbleForScrap = [NSMutableDictionary dictionary];

        contentView = [[MMScrapSidebarContentView alloc] initWithFrame:[slidingSidebarView contentBounds]];
        contentView.delegate = self;
        [slidingSidebarView addSubview:contentView];

        NSDictionary* loadedRotationValues = [NSDictionary dictionaryWithContentsOfFile:[MMScrapsInBezelContainerView pathToPlist]];
        rotationAdjustments = [NSMutableDictionary dictionary];
        if (loadedRotationValues) {
            [rotationAdjustments addEntriesFromDictionary:loadedRotationValues];
        }

        sidebarScrapState = [[MMScrapsInSidebarState alloc] initWithDelegate:self];
    }
    return self;
}

#pragma mark - Helper Methods

- (NSString*)scrapIDsPath {
    if (!scrapIDsPath) {
        NSString* documentsPath = [NSFileManager documentsPath];
        NSString* bezelStateDirectory = [documentsPath stringByAppendingPathComponent:@"Bezel"];
        [NSFileManager ensureDirectoryExistsAtPath:bezelStateDirectory];
        scrapIDsPath = [[bezelStateDirectory stringByAppendingPathComponent:@"scrapIDs"] stringByAppendingPathExtension:@"plist"];
    }
    return scrapIDsPath;
}


#pragma mark - Actions

- (void)bubbleTapped:(UITapGestureRecognizer*)gesture {
    MMScrapBubbleButton* bubble = (MMScrapBubbleButton*)gesture.view;
    MMScrapView* scrap = bubble.view;

    if ([[self viewsInSidebar] containsObject:bubble.view]) {
        scrap.rotation += (bubble.rotation - bubble.rotationAdjustment);
        [rotationAdjustments removeObjectForKey:scrap.uuid];
    }

    [super bubbleTapped:gesture];
}

#pragma mark - MMCountableSidebarContainerView

- (MMScrapBubbleButton*)newBubbleForView:(MMScrapView*)scrap {
    MMScrapBubbleButton* bubble = [[MMScrapBubbleButton alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
    bubble.rotation = lastRotationReading;
    bubble.originalViewScale = scrap.scale;
    bubble.delegate = self;
    [rotationAdjustments setObject:@(bubble.rotationAdjustment) forKey:scrap.uuid];
    return bubble;
}

- (void)addViewToCountableSidebar:(MMScrapView*)scrap animated:(BOOL)animated {
    // make sure we've saved its current state
    if (animated) {
        // only save when it's animated. non-animated is loading
        // from disk at start up
        [scrap saveScrapToDisk:nil];
    }

    [sidebarScrapState scrapIsAddedToSidebar:scrap];

    // unload the scrap state, so that it shows the
    // image preview instead of an editable state
    [scrap unloadState];

    [super addViewToCountableSidebar:scrap animated:animated];

    // exit the scrap to the bezel!
    CGPoint center = [self centerForBubbleAtIndex:0];

    // prep the animation by creating the new bubble for the scrap
    // and initializing it's probable location (may change if count > 6)
    // and set it's alpha/rotation/scale to prepare for the animation
    UIView<MMBubbleButton>* bubble = [self newBubbleForView:scrap];
    bubble.center = center;

    //
    // iOS7 changes how buttons can be tapped during a gesture (i think).
    // so adding our gesture recognizer explicitly, and disallowing it to
    // be prevented ensures that buttons can be tapped while other gestures
    // are in flight.
    //    [bubble addTarget:self action:@selector(bubbleTapped:) forControlEvents:UIControlEventTouchUpInside];
    UITapGestureRecognizer* tappy = [[MMSidebarButtonTapGestureRecognizer alloc] initWithTarget:self action:@selector(bubbleTapped:)];
    [bubble addGestureRecognizer:tappy];
    [self insertSubview:bubble atIndex:0];
    [self insertSubview:scrap aboveSubview:bubble];
    // keep the scrap in the bezel container during the animation, then
    // push it into the bubble
    bubble.alpha = 0;
    bubble.scale = .9;
    [bubbleForScrap setObject:bubble forKey:scrap.uuid];

    if (animated) {
        CGFloat animationDuration = 0.5;

        if ([sidebarScrapState.allLoadedScraps count] <= kMaxButtonsInBezelSidebar) {
            // allow adding to 6 in the sidebar, otherwise
            // we need to pull them all into 1 button w/
            // a menu
            [self loadCachedPreviewForView:scrap];

            [self.bubbleDelegate willAddView:scrap toCountableSidebar:self];

            [UIView animateWithDuration:animationDuration * .51 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                // animate the scrap into position
                bubble.alpha = 1;
                scrap.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
                scrap.center = bubble.center;
                for (UIView<MMBubbleButton>* otherBubble in self.subviews) {
                    if (otherBubble != bubble) {
                        if ([otherBubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                            int index = (int)[sidebarScrapState.allLoadedScraps indexOfObject:otherBubble.view];
                            otherBubble.center = [self centerForBubbleAtIndex:index];
                        }
                    }
                }

            } completion:^(BOOL finished) {
                // add it to the bubble and bounce
                bubble.view = scrap;
                [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    // scrap "hits" the bubble and pushes it down a bit
                    bubble.scale = .8;
                    bubble.alpha = self.alpha;
                } completion:^(BOOL finished) {
                    [self.countButton setCount:[sidebarScrapState.allLoadedScraps count]];
                    [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                        // bounce back
                        bubble.scale = 1.1;
                    } completion:^(BOOL finished) {
                        [UIView animateWithDuration:animationDuration * .16 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                            // and done
                            bubble.scale = 1.0;
                        } completion:^(BOOL finished) {
                            [self.bubbleDelegate didAddView:scrap toCountableSidebar:self];
                        }];
                    }];
                }];
            }];
        } else if ([sidebarScrapState.allLoadedScraps count] > kMaxButtonsInBezelSidebar) {
            // we need to merge all the bubbles together into
            // a single button during the bezel animation
            [self.bubbleDelegate willAddView:scrap toCountableSidebar:self];
            [self.countButton setCount:[sidebarScrapState.allLoadedScraps count]];
            bubble.center = self.countButton.center;
            bubble.scale = 1;
            [UIView animateWithDuration:animationDuration * .51 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                // animate the scrap into position
                self.countButton.alpha = 1;
                for (UIView<MMBubbleButton>* bubble in self.subviews) {
                    if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                        bubble.alpha = 0;
                        bubble.center = self.countButton.center;
                        [self unloadCachedPreviewForView:bubble.view];
                    }
                }
                scrap.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
                scrap.center = bubble.center;
            } completion:^(BOOL finished) {
                // add it to the bubble and bounce
                bubble.view = scrap;
                [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    // scrap "hits" the bubble and pushes it down a bit
                    self.countButton.scale = .8;
                } completion:^(BOOL finished) {
                    [self.countButton setCount:[sidebarScrapState.allLoadedScraps count]];
                    [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                        // bounce back
                        self.countButton.scale = 1.1;
                    } completion:^(BOOL finished) {
                        [UIView animateWithDuration:animationDuration * .16 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                            // and done
                            self.countButton.scale = 1.0;
                        } completion:^(BOOL finished) {
                            [self.bubbleDelegate didAddView:scrap toCountableSidebar:self];
                        }];
                    }];
                }];
            }];
        }
    } else {
        [self.bubbleDelegate willAddView:scrap toCountableSidebar:self];
        if ([sidebarScrapState.allLoadedScraps count] <= kMaxButtonsInBezelSidebar) {
            [self loadCachedPreviewForView:scrap];
            bubble.alpha = 1;
            scrap.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
            scrap.center = bubble.center;
            bubble.view = scrap;
            for (UIView<MMBubbleButton>* anyBubble in self.subviews) {
                if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                    int index = (int)[sidebarScrapState.allLoadedScraps indexOfObject:anyBubble.view];
                    anyBubble.center = [self centerForBubbleAtIndex:index];
                }
            }
        } else {
            [self.countButton setCount:[sidebarScrapState.allLoadedScraps count]];
            self.countButton.alpha = 1;
            for (UIView<MMBubbleButton>* bubble in self.subviews) {
                if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                    bubble.alpha = 0;
                    bubble.center = self.countButton.center;
                    [self unloadCachedPreviewForView:bubble.view];
                }
            }
            scrap.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
            scrap.center = bubble.center;
            bubble.view = scrap;
        }
        [self.bubbleDelegate didAddView:scrap toCountableSidebar:self];
    }
}

- (void)didTapOnViewFromMenu:(MMScrapView*)scrap withPreferredScrapProperties:(NSDictionary*)properties below:(BOOL)below {
    [sidebarScrapState scrapIsRemovedFromSidebar:scrap];

    [super didTapOnViewFromMenu:scrap withPreferredScrapProperties:properties below:below];

    [self animateAndAddScrapBackToPage:scrap withPreferredScrapProperties:properties];

    [bubbleForScrap removeObjectForKey:scrap.uuid];
}

- (void)animateAndAddScrapBackToPage:(MMScrapView*)scrap withPreferredScrapProperties:(NSDictionary*)properties {
    CheckMainThread;
    UIView<MMBubbleButton>* bubbleToAddToPage = [bubbleForScrap objectForKey:scrap.uuid];

    [scrap loadScrapStateAsynchronously:YES];

    scrap.scale = scrap.scale * [[bubbleToAddToPage class] idealScaleForView:scrap];

    BOOL hadProperties = properties != nil;

    if (!properties) {
        CGPoint positionOnScreenToScaleTo = [self.bubbleDelegate positionOnScreenToScaleScrapTo:scrap];
        CGFloat scaleOnScreenToScaleTo = [self.bubbleDelegate scaleOnScreenToScaleScrapTo:scrap givenOriginalScale:bubbleToAddToPage.originalViewScale];
        NSMutableDictionary* mproperties = [NSMutableDictionary dictionary];
        [mproperties setObject:[NSNumber numberWithFloat:positionOnScreenToScaleTo.x] forKey:@"center.x"];
        [mproperties setObject:[NSNumber numberWithFloat:positionOnScreenToScaleTo.y] forKey:@"center.y"];
        [mproperties setObject:[NSNumber numberWithFloat:scrap.rotation] forKey:@"rotation"];
        [mproperties setObject:[NSNumber numberWithFloat:scaleOnScreenToScaleTo] forKey:@"scale"];
        properties = mproperties;
    }

    [self.bubbleDelegate willAddScrapBackToPage:scrap];
    [UIView animateWithDuration:.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [scrap setPropertiesDictionary:properties];
    } completion:^(BOOL finished) {
        NSUInteger index = NSNotFound;
        if ([properties objectForKey:@"subviewIndex"]) {
            index = [[properties objectForKey:@"subviewIndex"] unsignedIntegerValue];
        }
        MMUndoablePaperView* page = [self.bubbleDelegate didAddScrapBackToPage:scrap atIndex:index];
        [scrap blockToFireWhenStateLoads:^{
            if (!hadProperties) {
                DebugLog(@"tapped on scrap from sidebar. should add undo item to page %@", page.uuid);
                [page addUndoItemForMostRecentAddedScrapFromBezelFromScrap:scrap];
            } else {
                DebugLog(@"scrap added from undo item, don't add new undo item");
            }
        }];
    }];
    [UIView animateWithDuration:.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        bubbleToAddToPage.alpha = 0;
        for (UIView<MMBubbleButton>* otherBubble in self.subviews) {
            if ([otherBubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                if (otherBubble.view && otherBubble != bubbleToAddToPage) {
                    int index = (int)[sidebarScrapState.allLoadedScraps indexOfObject:otherBubble.view];
                    otherBubble.center = [self centerForBubbleAtIndex:index];
                    if ([sidebarScrapState.allLoadedScraps count] <= kMaxButtonsInBezelSidebar) {
                        // we need to reset the view here, because it could have been stolen
                        // by the actual sidebar content view. If that's the case, then we
                        // need to steal the view back so it can display in the bubble button
                        otherBubble.view = otherBubble.view;
                        otherBubble.alpha = 1;
                        [self loadCachedPreviewForView:otherBubble.view];
                    }
                }
            }
        }
        if ([sidebarScrapState.allLoadedScraps count] <= kMaxButtonsInBezelSidebar) {
            self.countButton.alpha = 0;
        }
    } completion:^(BOOL finished) {
        [bubbleToAddToPage removeFromSuperview];
    }];
}


- (void)deleteAllViewsFromSidebar {
    for (MMScrapView* scrap in [[self viewsInSidebar] copy]) {
        [[MMTrashManager sharedInstance] deleteScrap:scrap.uuid inScrapCollectionState:scrap.state.scrapsOnPaperState];
        [sidebarScrapState scrapIsRemovedFromSidebar:scrap];
    }

    [super deleteAllViewsFromSidebar];

    [self saveScrapContainerToDisk];
}

- (void)loadCachedPreviewForView:(MMScrapView*)view {
    [view.state loadCachedScrapPreview];
}

- (void)unloadCachedPreviewForView:(MMScrapView*)view {
    [view.state unloadCachedScrapPreview];
}

#pragma mark - Rotation

- (CGFloat)sidebarButtonRotation {
    return -([[[MMRotationManager sharedInstance] currentRotationReading] angle] + M_PI / 2);
}

- (CGFloat)sidebarButtonRotationForReading:(MMVector*)currentReading {
    return -([currentReading angle] + M_PI / 2);
}

- (void)didUpdateAccelerometerWithReading:(MMVector*)currentRawReading {
    lastRotationReading = [self sidebarButtonRotationForReading:currentRawReading];
    CGFloat rotReading = [self sidebarButtonRotationForReading:currentRawReading];
    self.countButton.rotation = rotReading;
    for (MMScrapBubbleButton* bubble in self.subviews) {
        if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
            // during an animation, the scrap will also be a subview,
            // so we need to make sure that we're rotating only the
            // bubble button
            bubble.rotation = rotReading;
        }
    }
    [contentView setRotation:rotReading];
}

- (void)didRotateToIdealOrientation:(UIInterfaceOrientation)orientation {
    [contentView didRotateToIdealOrientation:orientation];
}

#pragma mark - Save and Load


static NSString* bezelStatePath;


+ (NSString*)pathToPlist {
    if (!bezelStatePath) {
        NSString* documentsPath = [NSFileManager documentsPath];
        NSString* bezelStateDirectory = [documentsPath stringByAppendingPathComponent:@"Bezel"];
        [NSFileManager ensureDirectoryExistsAtPath:bezelStateDirectory];
        bezelStatePath = [[bezelStateDirectory stringByAppendingPathComponent:@"rotations"] stringByAppendingPathExtension:@"plist"];
    }
    return bezelStatePath;
}

- (void)saveScrapContainerToDisk {
    if ([sidebarScrapState hasEditsToSave]) {
        NSMutableDictionary* writeableAdjustments = [rotationAdjustments copy];
        dispatch_async([MMScrapCollectionState importExportStateQueue], ^(void) {
            @autoreleasepool {
                [[sidebarScrapState immutableStateForPath:self.scrapIDsPath] saveStateToDiskBlocking];
                [writeableAdjustments writeToFile:[MMScrapsInBezelContainerView pathToPlist] atomically:YES];
            }
        });
    }
}

- (void)loadFromDisk {
    [sidebarScrapState loadStateAsynchronously:YES atPath:self.scrapIDsPath andMakeEditable:NO andAdjustForScale:NO];
}


#pragma mark - MMScrapsInSidebarStateDelegate / MMScrapCollectionStateDelegate

- (NSString*)uuidOfScrapCollectionStateOwner {
    return nil;
}

- (MMScrapView*)scrapForUUIDIfAlreadyExistsInOtherContainer:(NSString*)scrapUUID {
    // page's scraps might exist inside the bezel (us),
    // but our scraps will never exist on another page.
    // if our scraps are ever added to a page, they are
    // permanently gifted to that page's ownership, and
    // we lose our rights to it
    return nil;
}

- (void)didLoadScrapInContainer:(MMScrapView*)scrap {
    // add to the bezel
    NSNumber* rotationAdjustment = [rotationAdjustments objectForKey:scrap.uuid];
    scrap.rotation += [rotationAdjustment floatValue];
    [self addViewToCountableSidebar:scrap animated:NO];
    [scrap setShouldShowShadow:NO];
}

- (void)didLoadScrapOutOfContainer:(MMScrapView*)scrap {
    // noop
}

- (void)didLoadAllScrapsFor:(MMScrapCollectionState*)scrapState {
    // noop
}

- (void)didUnloadAllScrapsFor:(MMScrapCollectionState*)scrapState {
    // noop
}

- (MMScrapsOnPaperState*)paperStateForPageUUID:(NSString*)uuidOfPage {
    return [bubbleDelegate pageForUUID:uuidOfPage].scrapsOnPaperState;
}

@end
