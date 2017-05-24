//
//  AppDelegate.m
//  UpdateNameFromGLPI
//
//  Created by Yoann Gini on 23/12/2016.
//  Copyright © 2016 Yoann Gini. All rights reserved.
//

#import "AppDelegate.h"
#include <sys/types.h>
#include <sys/sysctl.h>
#include <SystemConfiguration/SystemConfiguration.h>

@interface AppDelegate ()

#define kGLPIBaseURL @"baseAPIURL"
#define kGLPIAuthToken @"authToken"
#define kGLPIAppToken @"appToken"

@property (weak) IBOutlet NSWindow *window;
@property NSString *sessionToken;

@end

@implementation AppDelegate


-(NSString *) machineModel
{
    size_t len = 0;
    sysctlbyname("hw.model", NULL, &len, NULL, 0);
    
    if (len)
    {
        char *model = malloc(len*sizeof(char));
        sysctlbyname("hw.model", model, &len, NULL, 0);
        NSString *model_ns = [NSString stringWithUTF8String:model];
        free(model);
        return model_ns;
    }
    
    return nil; //incase model name can't be read
}

- (NSString *)getSerialNumber
{
    NSString *serial = nil;
    io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                              IOServiceMatching("IOPlatformExpertDevice"));
    if (platformExpert) {
        CFTypeRef serialNumberAsCFString =
        IORegistryEntryCreateCFProperty(platformExpert,
                                        CFSTR(kIOPlatformSerialNumberKey),
                                        kCFAllocatorDefault, 0);
        if (serialNumberAsCFString) {
            serial = CFBridgingRelease(serialNumberAsCFString);
        }
        
        IOObjectRelease(platformExpert);
    }
    return serial;
}

- (void)requestForAPI:(NSString*)api withJSONComptaibleObject:(NSDictionary *)content andCompletionHandler:(void (^)(id infos, NSError *error))completionHandler {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", [[NSUserDefaults standardUserDefaults] stringForKey:kGLPIBaseURL], api]]];
    
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[[NSUserDefaults standardUserDefaults] stringForKey:kGLPIAppToken] forHTTPHeaderField:@"app_token"];
    
    if (self.sessionToken) {
        [request setValue:self.sessionToken forHTTPHeaderField:@"Session-Token"];
    } else {
        [request setValue:[NSString stringWithFormat:@"user_token %@", [[NSUserDefaults standardUserDefaults] stringForKey:kGLPIAuthToken]] forHTTPHeaderField:@"Authorization"];
    }
    
    if (content) {
        NSError *error = nil;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:content
                                                           options:0
                                                             error:&error];
        
        if (error) {
            NSLog(@"Unable to create JSON body");
            NSLog(@"%@", error);
            completionHandler(nil, error);
        }
    }
    
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                     completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                         NSLog(@"API answer with status code %ld", (long)((NSHTTPURLResponse*)response).statusCode);
                                         if (error) {
                                             NSLog(@"Unable to exectue request");
                                             NSLog(@"%@", error);
                                             completionHandler(nil, error);
                                         } else {
                                             NSError *error = nil;
                                             
                                             id infos = [NSJSONSerialization JSONObjectWithData:data
                                                                                                   options:0
                                                                                                     error:&error];
                                             
                                             if (error) {
                                                 NSLog(@"Unable to parse JSON answer");
                                                 NSLog(@"%@", error);
                                                 completionHandler(nil, error);
                                             } else {
                                                 completionHandler(infos, nil);
                                             }
                                         }
                                     }] resume];
    
}

- (NSString*)stringFromAPIResult:(id)value {
    return [NSString stringWithFormat:@"%@", value];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self requestForAPI:@"initSession" withJSONComptaibleObject:nil andCompletionHandler:^(NSDictionary *infos, NSError *error) {
        self.sessionToken = [infos objectForKey:@"session_token"];
        [self requestForAPI:[NSString stringWithFormat:@"search/computer?&forcedisplay[0]=2&criteria[0][field]=5&criteria[0][searchtype]=contains&criteria[0][value]=%@", [self getSerialNumber]]
   withJSONComptaibleObject:nil
       andCompletionHandler:^(NSDictionary *searchResult, NSError *error) {
           
           if (searchResult) {
               NSNumber *recordID = [[[searchResult objectForKey:@"data"] lastObject] objectForKey:@"2"];
               [self requestForAPI:[NSString stringWithFormat:@"computer/%@", recordID]
          withJSONComptaibleObject:nil
              andCompletionHandler:^(NSDictionary *computerInfos, NSError *error) {
                  if (computerInfos) {
                      NSString *inventoryNumber = [self stringFromAPIResult:[computerInfos objectForKey:@"otherserial"]];
                      
                      if ([inventoryNumber length] == 0) {
                          inventoryNumber = [self stringFromAPIResult:[computerInfos objectForKey:@"contact_num"]];
                      }
                      
                      if ([inventoryNumber length] == 0) {
                          inventoryNumber = @"N/A";
                      }
                      
                      NSString *modelIdentifier = nil;
                      NSString *machineModel = [self machineModel];
                      if ([machineModel rangeOfString:@"MacBookPro"].location == 0) {
                          modelIdentifier = @"MBP";
                      } else if ([machineModel rangeOfString:@"MacBookAir"].location == 0) {
                          modelIdentifier = @"MBA";
                      } else if ([machineModel rangeOfString:@"MacBook"].location == 0) {
                          modelIdentifier = @"MB";
                      } else if ([machineModel rangeOfString:@"iMac"].location == 0) {
                          modelIdentifier = @"IM";
                      } else if ([machineModel rangeOfString:@"MacPro"].location == 0) {
                          modelIdentifier = @"MP";
                      } else {
                          modelIdentifier = @"Mac";
                      }
                      
                      NSString *computedComputerName = [NSString stringWithFormat:@"%@-%@", modelIdentifier, inventoryNumber];
                      
                      if (![[[NSProcessInfo processInfo] hostName] isEqualToString:computedComputerName]) {
                          
                          for (NSString *name in @[@"ComputerName", @"HostName", @"LocalHostName"]) {
                              NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/sbin/scutil"
                                                                      arguments:@[@"--set", name, computedComputerName]];
                              
                              [task waitUntilExit];
                              
                              NSLog(@"%@ update task exited with status %i", name, [task terminationStatus]);

                          }
                      }
                      
                  } else {
                      NSLog(@"Computer record with ID %@ not found on GLPI", recordID);
                  }
                  
                  [NSApp terminate:self];
              }];
           } else {
               NSLog(@"Computer with serial number %@ not found on GLPI", [self getSerialNumber]);
               [NSApp terminate:self];
           }
       }];
    }];
    
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
