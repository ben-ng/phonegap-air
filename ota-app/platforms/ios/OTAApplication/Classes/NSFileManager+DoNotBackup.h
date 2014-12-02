//
//  NSFileManager+DoNotBackup.h
//  OTAApplication
//
//  Created by Ben on 10/7/14.
//
//

#import <Foundation/Foundation.h>

@interface NSFileManager (DoNotBackup)

- (BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)URL;

@end
