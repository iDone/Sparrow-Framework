//
//  SPDisplayObjectContainer.m
//  Sparrow
//
//  Created by Daniel Sperl on 15.03.09.
//  Copyright 2009 Incognitek. All rights reserved.
//

#import "SPDisplayObjectContainer.h"
#import "SPEnterFrameEvent.h"
#import "SPDisplayObject_Internal.h"
#import "SPMacros.h"

// --- c functions ---

static void dispatchEventOnChildren(SPDisplayObject *object, SPEvent *event)
{
    // This function is mainly used for ADDED_TO_STAGE- and REMOVED_FROM_STAGE-events.
    // Those events are dispatched often, yet used very rarely.
    // Thus we handle them in a C function, so that the overhead that they create is minimal.
    
    [object dispatchEvent:event];    
    if ([object isKindOfClass:[SPDisplayObjectContainer class]])
    {
        SPDisplayObjectContainer *container = (SPDisplayObjectContainer *)object;
        for (SPDisplayObject *child in container)
            dispatchEventOnChildren(child, event);
    }
}

// --- class implementation ------------------------------------------------------------------------

@implementation SPDisplayObjectContainer

- (id)init
{    
    if ([[self class] isEqual:[SPDisplayObjectContainer class]]) 
    { 
        [NSException raise:SP_EXC_ABSTRACT_CLASS 
                    format:@"Attempting to instantiate SPDisplayObjectContainer directly."];
        [self release]; 
        return nil; 
    }
    
    if (self = [super init]) 
    {
        mChildren = [[NSMutableArray alloc] init];
    }
    
    return self;
}


#pragma mark -

- (void)addChild:(SPDisplayObject *)child
{
    [self addChild:child atIndex:[mChildren count]];
}

- (void)addChild:(SPDisplayObject *)child atIndex:(int)index
{
    [child retain];
    [child removeFromParent];
    [mChildren insertObject:child atIndex:index];    
    child.parent = self;
    
    SPEvent *addedEvent = [[SPEvent alloc] initWithType:SP_EVENT_TYPE_ADDED];    
    [child dispatchEvent:addedEvent];
    [addedEvent release];    
    
    if (self.stage)
    {
        SPEvent *addedToStageEvent = [[SPEvent alloc] initWithType:SP_EVENT_TYPE_ADDED_TO_STAGE];
        dispatchEventOnChildren(child, addedToStageEvent);
        [addedToStageEvent release];
    }
    
    [child release];
}

- (BOOL)containsChild:(SPDisplayObject *)child
{
    if ([self isEqual:child]) return YES; 
    
    for (SPDisplayObject *currentChild in mChildren)
    {
        if ([currentChild isKindOfClass:[SPDisplayObjectContainer class]])
        {
            if ([(SPDisplayObjectContainer *)currentChild containsChild:child]) return YES;
        }
        else
        {
            if ([currentChild isEqual: child]) return YES;
        }
    }
    
    return NO;
}

- (SPDisplayObject *)childAtIndex:(int)index
{
    return [mChildren objectAtIndex:index];
}

- (int)childIndex:(SPDisplayObject *)child
{
    int index = [mChildren indexOfObject:child];
    if (index == NSNotFound) return SP_NOT_FOUND;
    else                     return index;
}

- (void)removeChild:(SPDisplayObject *)child
{
    int childIndex = [self childIndex:child];
    if (childIndex == SP_NOT_FOUND)
        [NSException raise:SP_EXC_NOT_RELATED format:@"Object is not a child of this container"];
    else 
        [self removeChildAtIndex:childIndex];
}

- (void)removeChildAtIndex:(int)index
{
    if (index >= 0 && index < [mChildren count])
    {
        SPDisplayObject *child = [[mChildren objectAtIndex:index] retain];
        [mChildren removeObjectAtIndex:index];
        child.parent = nil;        
        
        SPEvent *remEvent = [[SPEvent alloc] initWithType:SP_EVENT_TYPE_REMOVED];    
        [child dispatchEvent:remEvent];
        [remEvent release];    
        
        if (self.stage)
        {
            SPEvent *remFromStageEvent = [[SPEvent alloc] initWithType:SP_EVENT_TYPE_REMOVED_FROM_STAGE];
            dispatchEventOnChildren(child, remFromStageEvent);
            [remFromStageEvent release];
        }        
        
        [child release];
    }
    else [NSException raise:SP_EXC_INDEX_OUT_OF_BOUNDS format:@"Invalid child index"];        
}

- (void)swapChild:(SPDisplayObject*)child1 withChild:(SPDisplayObject*)child2
{
    int index1 = [self childIndex:child1];
    int index2 = [self childIndex:child2];
    [self swapChildAtIndex:index1 withChildAtIndex:index2];
}

- (void)swapChildAtIndex:(int)index1 withChildAtIndex:(int)index2
{    
    int numChildren = [mChildren count];    
    if (index1 < 0 || index1 >= numChildren || index2 < 0 || index2 >= numChildren)
        [NSException raise:SP_EXC_INVALID_OPERATION format:@"invalid child indices"];
    [mChildren exchangeObjectAtIndex:index1 withObjectAtIndex:index2];
}

- (int)numChildren
{
    return [mChildren count];
}

#pragma mark -

- (SPRectangle*)boundsInSpace:(SPDisplayObject*)targetCoordinateSpace
{    
    int numChildren = [mChildren count];

    if (numChildren == 0) 
        return [SPRectangle rectangleWithX:0 y:0 width:0 height:0];
    else if (numChildren == 1) 
        return [[mChildren objectAtIndex:0] boundsInSpace:targetCoordinateSpace];
    else
    {
        float minX = FLT_MAX, maxX = -FLT_MAX, minY = FLT_MAX, maxY = -FLT_MAX;    
        for (SPDisplayObject *child in mChildren)
        {
            SPRectangle *childBounds = [child boundsInSpace:targetCoordinateSpace];        
            minX = MIN(minX, childBounds.x);
            maxX = MAX(maxX, childBounds.x + childBounds.width);
            minY = MIN(minY, childBounds.y);
            maxY = MAX(maxY, childBounds.y + childBounds.height);        
        }    
        return [SPRectangle rectangleWithX:minX y:minY width:maxX-minX height:maxY-minY];
    }
}

- (SPDisplayObject*)hitTestPoint:(SPPoint*)localPoint forTouch:(BOOL)isTouch;
{
    if (isTouch && (!self.visible || !self.touchable)) 
        return nil;
    
    for (int i=[mChildren count]-1; i>=0; --i) // front to back!
    {
        SPDisplayObject *child = [mChildren objectAtIndex:i];
        SPMatrix *transformationMatrix = [self transformationMatrixToSpace:child];
        SPPoint  *transformedPoint = [transformationMatrix transformPoint:localPoint];
        SPDisplayObject *target = [child hitTestPoint:transformedPoint forTouch:isTouch];
        if (target) return target;
    }
    
    return nil;
}

#pragma mark -

- (void)dealloc 
{    
    [mChildren release];
    [super dealloc];
}

#pragma mark NSFastEnumeration

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf 
                                    count:(NSUInteger)len
{
    return [mChildren countByEnumeratingWithState:state objects:stackbuf count:len];
}

@end
