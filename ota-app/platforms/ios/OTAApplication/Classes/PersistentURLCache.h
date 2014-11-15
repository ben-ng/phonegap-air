//
//  PersistentURLCache.h
//  Getable
//
//  Created by Ben on 7/18/14.
//
//

#import <Foundation/Foundation.h>

@interface PersistentURLCache : NSURLCache

-(id)initWithMemoryCapacity:(NSUInteger)memoryCapacity
               diskCapacity:(NSUInteger)diskCapacity
                   diskPath:(NSString *)diskPath
             cachePrimerURL:(NSURL *)cachePrimerURL
         OTAUpdatedCacheURL:(NSURL *)OTAUpdatedCacheURL;

-(NSURL *)persistedDataURLForURL:(NSURL *) url;
-(NSURL *)OTAUpdatedPersistedDataURLForURL: (NSURL *) url;
-(NSString *)cacheKeyForURL:(NSURL *) url;
-(NSURL *)OTAUpdatedCacheURL;

@end
