//
//  ProxySettingTool.m
//  com.west2online.ClashX.ProxyConfigHelper
//
//  Created by yichengchen on 2019/8/17.
//  Copyright © 2019 west2online. All rights reserved.
//

#import "ProxySettingTool.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <AppKit/AppKit.h>

#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>

@interface ProxySettingTool()
@property (nonatomic, assign) AuthorizationRef authRef;

@end

@implementation ProxySettingTool

// MARK: - Public

- (void)enableProxyWithport:(int)port socksPort:(int)socksPort {
    [self applySCNetworkSettingWithRef:^(SCPreferencesRef ref) {
        [ProxySettingTool getDiviceListWithPrefRef:ref devices:^(NSString *key, NSDictionary *dict) {
            [self enableProxySettings:ref interface:key port:port socksPort:socksPort];
        }];
    }];
}

- (void)disableProxy {
    [self applySCNetworkSettingWithRef:^(SCPreferencesRef ref) {
        [ProxySettingTool getDiviceListWithPrefRef:ref devices:^(NSString *key, NSDictionary *dict) {
            [self disableProxySetting:ref interface:key];
        }];
    }];
}

- (void)restoreProxySettint:(NSDictionary *)savedInfo currentPort:(int)port currentSocksPort:(int)socksPort {
    [self applySCNetworkSettingWithRef:^(SCPreferencesRef ref) {
        [ProxySettingTool getDiviceListWithPrefRef:ref devices:^(NSString *key, NSDictionary *dict) {
            NSDictionary *proxySetting = savedInfo[key];
            if (![proxySetting isKindOfClass:[NSDictionary class]]) {
                proxySetting = nil;
            }
            
            if (!proxySetting) {
                [self disableProxySetting:ref interface:key];
                return;
            }
            BOOL isClashSetting =
            [proxySetting[(__bridge NSString *)kCFNetworkProxiesHTTPProxy] isEqualToString:@"127.0.0.1"] &&
            [proxySetting[(__bridge NSString *)kCFNetworkProxiesSOCKSProxy] isEqualToString:@"127.0.0.1"] &&
            ((NSNumber *)(proxySetting[(__bridge NSString *)kCFNetworkProxiesHTTPEnable])).boolValue &&
            ((NSNumber *)(proxySetting[(__bridge NSString *)kCFNetworkProxiesHTTPSEnable])).boolValue&&
            ((NSNumber *)(proxySetting[(__bridge NSString *)kCFNetworkProxiesHTTPPort])).intValue == port&&
            ((NSNumber *)(proxySetting[(__bridge NSString *)kCFNetworkProxiesHTTPSPort])).intValue == port&&
            ((NSNumber *)(proxySetting[(__bridge NSString *)kCFNetworkProxiesSOCKSPort])).intValue == socksPort;

            if (isClashSetting) {
                [self disableProxySetting:ref interface:key];
                return;
            }
            
            [self setProxyConfig:ref interface:key proxySetting:proxySetting];
            
        }];
    }];
}

+ (NSMutableDictionary<NSString *,NSDictionary *> *)currentProxySettings {
    __block NSMutableDictionary<NSString *,NSDictionary *> *info = [NSMutableDictionary dictionary];
    SCPreferencesRef ref = SCPreferencesCreate(nil, CFSTR("ClashX"), nil);
    [ProxySettingTool getDiviceListWithPrefRef:ref devices:^(NSString *key, NSDictionary *dev) {
        NSDictionary *proxySettings = dev[(__bridge NSString *)kSCEntNetProxies];
        info[key] = [proxySettings copy];
    }];
    CFRelease(ref);
    
    return info;
}


+ (NSMutableDictionary<NSString *,NSDictionary *> *)currentDnsSettings {
    __block NSMutableDictionary<NSString *,NSDictionary *> *info = [NSMutableDictionary dictionary];
    SCPreferencesRef ref = SCPreferencesCreate(nil, CFSTR("ClashX"), nil);
    [ProxySettingTool getDiviceListWithPrefRef:ref devices:^(NSString *key, NSDictionary *dev) {
        NSDictionary *dnsSettings = dev[(__bridge NSString *)kSCEntNetDNS];
        info[key] = [dnsSettings copy];
    }];
    
    return info;
}

- (void)setLocalDns {
    [self applySCNetworkSettingWithRef:^(SCPreferencesRef ref) {
        [ProxySettingTool getDiviceListWithPrefRef:ref devices:^(NSString *key, NSDictionary *dev) {
            NSString *path = [self dnsSettingPathWithInterface:key];
            
            NSMutableDictionary *dnsSetting = [NSMutableDictionary dictionary];
            dnsSetting[(__bridge NSString *)kSCPropNetDNSServerAddresses] = @[@"127.0.0.1"];
            SCPreferencesPathSetValue(ref,
                                      (__bridge CFStringRef)path,
                                      (__bridge CFDictionaryRef)dnsSetting);
        }];
    }];
}

- (void)restoreDnsSetting:(NSDictionary *)savedInfo {
    [self applySCNetworkSettingWithRef:^(SCPreferencesRef ref) {
        [ProxySettingTool getDiviceListWithPrefRef:ref devices:^(NSString *key, NSDictionary *info) {
            NSString *path = [self dnsSettingPathWithInterface:key];
            NSDictionary *dnsSetting = savedInfo[key];
            BOOL vaild = NO;
            if (dnsSetting && [dnsSetting isKindOfClass:[NSDictionary class]]) {
                NSArray<NSString *> *dnsArr = dnsSetting[(__bridge NSString *)kSCPropNetDNSServerAddresses];
                if ( [dnsSetting isKindOfClass:[NSArray<NSString *> class]] ){
                    if (![dnsArr.firstObject isEqualToString:@"127.0.0.1"]) {
                        vaild = YES;
                    }
                }
            }
            
            if (!vaild) {
                dnsSetting = [NSDictionary dictionary];
            }
            
            SCPreferencesPathSetValue(ref,
                                      (__bridge CFStringRef)path,
                                      (__bridge CFDictionaryRef)dnsSetting);
        }];
    }];
}

+ (NSString *)clearDnsCache {
    // killall -HUP mDNSResponder
    return [self runCommand:@"/usr/bin/killall" args:@[@"-HUP", @"mDNSResponder"]];
}

+ (NSString *)updateForwardingOptions {
    // sysctl -w net.inet.ip.forwarding=1
    return [self runCommand:@"/usr/sbin/sysctl" args:@[@"-w", @"net.inet.ip.forwarding=1"]];
}

// MARK: - Private

- (void)dealloc {
    [self freeAuth];
}

+ (NSString *)runCommand:(NSString *)path args:(NSArray *)args {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:path];
    [task setArguments:args];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];

    NSFileHandle *file = [pipe fileHandleForReading];

    [task launch];

    NSData *data = [file readDataToEndOfFile];

    return [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
}


+ (NSString *)getUserHomePath {
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("com.west2online.ClashX.ProxyConfigHelper"), NULL, NULL);
    CFStringRef CopyCurrentConsoleUsername(SCDynamicStoreRef store);
    CFStringRef result;
    uid_t uid;
    result = SCDynamicStoreCopyConsoleUser(store, &uid, NULL);
    if ((result != NULL) && CFEqual(result, CFSTR("loginwindow"))) {
        CFRelease(result);
        result = NULL;
        CFRelease(store);
        return nil;
    }
    CFRelease(result);
    result = NULL;
    CFRelease(store);
    char *dir = getpwuid(uid)->pw_dir;
    NSString *path = [NSString stringWithUTF8String:dir];
    return path;
}


- (NSArray<NSString *> *)getIgnoreList {
    NSString *homePath = [ProxySettingTool getUserHomePath];
    if (homePath.length > 0) {
        NSString *configPath = [homePath stringByAppendingString:@"/.config/clash/proxyIgnoreList.plist"];
        if ([NSFileManager.defaultManager fileExistsAtPath:configPath]) {
            NSArray *arr = [[NSArray alloc] initWithContentsOfFile:configPath];
            if (arr != nil && arr.count > 0 && [arr containsObject:@"127.0.0.1"]) {
                return arr;
            }
        }
    }
    NSArray *ignoreList = @[
                            @"192.168.0.0/16",
                            @"10.0.0.0/8",
                            @"172.16.0.0/12",
                            @"127.0.0.1",
                            @"localhost",
                            @"*.local",
                            ];
    return ignoreList;
}

- (NSDictionary *)getProxySetting:(BOOL)enable port:(int) port socksPort: (int)socksPort {
    NSMutableDictionary *proxySettings = [NSMutableDictionary dictionary];
    
    NSString *ip = enable ? @"127.0.0.1" : @"";
    NSInteger enableInt = enable ? 1 : 0;
    
    proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPProxy] = ip;
    proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @(enableInt);
    proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPSProxy] = ip;
    proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPSEnable] = @(enableInt);
    
    proxySettings[(__bridge NSString *)kCFNetworkProxiesSOCKSProxy] = ip;
    proxySettings[(__bridge NSString *)kCFNetworkProxiesSOCKSEnable] = @(enableInt);
    
    if (enable) {
        proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPPort] = @(port);
        proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPSPort] = @(port);
        proxySettings[(__bridge NSString *)kCFNetworkProxiesSOCKSPort] = @(socksPort);
    } else {
        proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPPort] = nil;
        proxySettings[(__bridge NSString *)kCFNetworkProxiesHTTPSPort] = nil;
        proxySettings[(__bridge NSString *)kCFNetworkProxiesSOCKSPort] = nil;
    }
    
    
    proxySettings[(__bridge NSString *)kCFNetworkProxiesExceptionsList] = [self getIgnoreList];
    
    return proxySettings;
}

- (NSString *)proxySettingPathWithInterface:(NSString *)interfaceKey {
    return [NSString stringWithFormat:@"/%@/%@/%@",
            (NSString *)kSCPrefNetworkServices,
            interfaceKey,
            (NSString *)kSCEntNetProxies];
}

- (NSString *)dnsSettingPathWithInterface:(NSString *)interfaceKey {
    return [NSString stringWithFormat:@"/%@/%@/%@",
            (NSString *)kSCPrefNetworkServices,
            interfaceKey,
            (NSString *)kSCEntNetDNS];
}

- (void)enableProxySettings:(SCPreferencesRef)prefs
                 interface:(NSString *)interfaceKey
                      port:(int) port
                 socksPort:(int) socksPort {
    
    NSDictionary *proxySettings = [self getProxySetting:YES port:port socksPort:socksPort];
    [self setProxyConfig:prefs interface:interfaceKey proxySetting:proxySettings];

}

- (void)disableProxySetting:(SCPreferencesRef)prefs
                  interface:(NSString *)interfaceKey {
    NSDictionary *proxySettings = [self getProxySetting:NO port:0 socksPort:0];
    [self setProxyConfig:prefs interface:interfaceKey proxySetting:proxySettings];
}

- (void)setProxyConfig:(SCPreferencesRef)prefs
                 interface:(NSString *)interfaceKey
              proxySetting:(NSDictionary *)proxySettings {
    NSString *path = [self proxySettingPathWithInterface:interfaceKey];
    SCPreferencesPathSetValue(prefs,
                              (__bridge CFStringRef)path,
                              (__bridge CFDictionaryRef)proxySettings);
}

+ (void)getDiviceListWithPrefRef:(SCPreferencesRef)ref devices:(void(^)(NSString *, NSDictionary *))callback {
    NSDictionary *sets = (__bridge NSDictionary *)SCPreferencesGetValue(ref, kSCPrefNetworkServices);
    for (NSString *key in [sets allKeys]) {
        NSMutableDictionary *dict = [sets objectForKey:key];
        NSString *hardware = [dict valueForKeyPath:@"Interface.Hardware"];
        if ([hardware isEqualToString:@"AirPort"]
            || [hardware isEqualToString:@"Wi-Fi"]
            || [hardware isEqualToString:@"Ethernet"]) {
            callback(key,dict);
        }
    }
}

- (void)applySCNetworkSettingWithRef:(void(^)(SCPreferencesRef))callback {
    SCPreferencesRef ref = SCPreferencesCreateWithAuthorization(nil, CFSTR("com.west2online.ClashX.ProxyConfigHelper.config"), nil, self.authRef);
    if (!ref) {
        return;
    }
    callback(ref);
    
    SCPreferencesCommitChanges(ref);
    SCPreferencesApplyChanges(ref);
    SCPreferencesSynchronize(ref);
    CFRelease(ref);
}

// MARK: - AUTH
- (AuthorizationFlags)authFlags {
    AuthorizationFlags authFlags = kAuthorizationFlagDefaults
    | kAuthorizationFlagExtendRights
    | kAuthorizationFlagInteractionAllowed
    | kAuthorizationFlagPreAuthorize;
    return authFlags;
}

- (NSString *)setupAuth:(NSData *)authData {
    if (authData.length == 0 || authData.length != kAuthorizationExternalFormLength) {
        return @"PrivilegedTaskRunnerHelper: Authorization data is malformed";
    }
    AuthorizationRef authRef;
    
    OSStatus status = AuthorizationCreateFromExternalForm([authData bytes],&authRef);
    if (status != errAuthorizationSuccess) {
        return @"AuthorizationCreateFromExternalForm fail";
    }
    
    NSString *authName = @"com.west2online.ClashX.ProxyConfigHelper.config";
    AuthorizationItem authItem = {authName.UTF8String, 0, NULL, 0};
    AuthorizationRights authRight = {1, &authItem};
    
    AuthorizationFlags authFlags = [self authFlags];
    
    status = AuthorizationCopyRights(authRef, &authRight, nil, authFlags, nil);
    if (status != errAuthorizationSuccess) {
        AuthorizationFree(authRef, authFlags);
        return @"AuthorizationCopyRights fail";
    }
    
    OSStatus authErr = AuthorizationCreate(nil, kAuthorizationEmptyEnvironment, authFlags, &authRef);
    
    if (authErr != noErr) {
        AuthorizationFree(authRef, authFlags);
        return @"AuthorizationCreate fail";
    }
    self.authRef = authRef;
    return nil;
}

- (void)freeAuth {
    if (self.authRef) {
        AuthorizationFree(self.authRef, [self authFlags]);
    }
}


@end
