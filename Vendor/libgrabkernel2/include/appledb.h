//
//  appledb.h
//  libgrabkernel2
//
//  Created by Dhinak G on 3/4/24.
//

#ifndef appledb_h
#define appledb_h

#import <Foundation/Foundation.h>

NSString *getFirmwareURLFor(NSString *osStr, NSString *build, NSString *modelIdentifier, bool *isOTA);
NSString *getFirmwareURL(bool *isOTA);

// All usable firmware links (in preference order) as @{@"url", @"ota"} —
// lets callers fall through candidates when one CDN edge/network path fails.
NSArray<NSDictionary *> *getFirmwareURLCandidatesFor(NSString *osStr,
                                                      NSString *build,
                                                      NSString *modelIdentifier,
                                                      NSError **error);
NSArray<NSDictionary *> *getFirmwareURLCandidates(NSError **error);

#endif /* appledb_h */
