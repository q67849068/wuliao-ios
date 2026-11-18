#import "AppDelegate.h"
#import <UserNotifications/UserNotifications.h>
#import <AVFoundation/AVFoundation.h>

static NSString *gApnsToken = nil;

@interface AppDelegate () <UNUserNotificationCenterDelegate>
@end

@implementation AppDelegate

static AVAudioPlayer *gKeepAlivePlayer = nil;

- (void)startKeepAliveAudio {
    if (gKeepAlivePlayer) {
        if (!gKeepAlivePlayer.isPlaying) [gKeepAlivePlayer play];
        return;
    }
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback
             withOptions:AVAudioSessionCategoryOptionMixWithOthers
                   error:&err];
    if (err) NSLog(@"[KeepAlive] 音频会话设置失败: %@", err.localizedDescription);
    [session setActive:YES error:&err];
    if (err) NSLog(@"[KeepAlive] 激活失败: %@", err.localizedDescription);

    // 生成 1 秒静音 WAV
    const int sampleRate = 8000;
    const int numSamples = sampleRate;
    const int dataSize = numSamples * 2;
    NSMutableData *wav = [NSMutableData data];
    void (^w16)(NSMutableData *, uint16_t) = ^(NSMutableData *d, uint16_t v) { [d appendBytes:&v length:2]; };
    void (^w32)(NSMutableData *, uint32_t) = ^(NSMutableData *d, uint32_t v) { [d appendBytes:&v length:4]; };
    [wav appendData:[@"RIFF" dataUsingEncoding:NSASCIIStringEncoding]];
    w32(wav, 36 + dataSize);
    [wav appendData:[@"WAVEfmt " dataUsingEncoding:NSASCIIStringEncoding]];
    w32(wav, 16); w16(wav, 1); w16(wav, 1);
    w32(wav, sampleRate); w32(wav, sampleRate * 2);
    w16(wav, 2); w16(wav, 16);
    [wav appendData:[@"data" dataUsingEncoding:NSASCIIStringEncoding]];
    w32(wav, dataSize);
    [wav appendData:[NSMutableData dataWithLength:dataSize]];

    gKeepAlivePlayer = [[AVAudioPlayer alloc] initWithData:wav error:&err];
    if (err) {
        NSLog(@"[KeepAlive] 播放器创建失败: %@", err.localizedDescription);
        return;
    }
    gKeepAlivePlayer.numberOfLoops = -1;
    gKeepAlivePlayer.volume = 0.0;
    BOOL ok = [gKeepAlivePlayer play];
    NSLog(@"[KeepAlive] 静音保活启动: %d", ok);
}

- (void)stopKeepAliveAudio {
    if (gKeepAlivePlayer) {
        [gKeepAlivePlayer stop];
        gKeepAlivePlayer = nil;
    }
}


+ (NSString *)apnsToken {
    if (gApnsToken.length > 0) return gApnsToken;
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"apnsToken"];
}

+ (void)setApnsToken:(NSString *)token {
    gApnsToken = [token copy];
    [[NSUserDefaults standardUserDefaults] setObject:token forKey:@"apnsToken"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"[APNs] token 已保存: %@", token);
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionBadge | UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted, NSError *error) {
        NSLog(@"[APNs] 授权结果: %d", granted);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        });
    }];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];
    WebViewController *vc = [[WebViewController alloc] init];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    [self startKeepAliveAudio];

    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [self startKeepAliveAudio];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [self startKeepAliveAudio];
}

- (void)application:(UIApplication *)application
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    const unsigned char *bytes = (const unsigned char *)deviceToken.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:deviceToken.length * 2];
    for (NSUInteger i = 0; i < deviceToken.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    [AppDelegate setApnsToken:hex];

    // 通知 WebView 注入
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WuliaoApnsTokenReady" object:nil];
}

- (void)application:(UIApplication *)application
    didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"[APNs] 注册失败: %@", error.localizedDescription);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
    completionHandler();
}

@end


@implementation WebViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.retryCount = 0;
    self.didLoad = NO;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"wuliaoBridge"];
    config.userContentController = ucc;

    self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 0, 0) configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.opaque = YES;
    self.webView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.webView];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = [UIColor grayColor];
    [self.view addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
    [self.spinner startAnimating];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onTokenReady)
                                                 name:@"WuliaoApnsTokenReady"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onTokenReady {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self injectToken];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.didLoad) {
        self.didLoad = YES;
        [self loadApp];
    }
}

- (void)loadApp {
    NSURL *url = [NSURL URLWithString:@"https://chat.lingguangsh.com/h5/"];
    NSURLRequest *req = [NSURLRequest requestWithURL:url
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:30.0];
    [self.webView loadRequest:req];
}

// 把 APNs token 注入到 H5
- (void)injectToken {
    NSString *token = [AppDelegate apnsToken];
    if (token.length == 0) {
        NSLog(@"[APNs] 暂无 token，跳过注入");
        return;
    }
    NSString *js = [NSString stringWithFormat:
        @"(function(){try{if(window.__apnsToken){window.__apnsToken('%@');console.log('[APNs] 注入成功');return 'ok';}return 'no-hook';}catch(e){return 'err:'+e;}})()",
        token];
    [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        NSLog(@"[APNs] 注入结果: %@ err=%@", result, error.localizedDescription);
        if (error || ![@"ok" isEqual:result]) {
            // 页面还没准备好，2 秒后重试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self injectToken];
            });
        }
    }];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"wuliaoBridge"]) {
        NSDictionary *body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
        NSString *action = body[@"action"];
        NSLog(@"[Bridge] 收到: %@", action);
        if ([action isEqualToString:@"getToken"]) {
            [self injectToken];
        }
    }
}

#pragma mark - Navigation

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.spinner startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"[Web] 加载完成: %@", webView.title);
    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:@"document.body ? document.body.innerText.trim().length : -1"
              completionHandler:^(id result, NSError *error) {
        NSInteger len = [result respondsToSelector:@selector(integerValue)] ? [result integerValue] : -1;
        if (len <= 0 && weakSelf.retryCount < 3) {
            weakSelf.retryCount++;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf.webView reload];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.spinner stopAnimating];
                weakSelf.spinner.hidden = YES;
            });
            // 页面就绪后注入 token
            [weakSelf injectToken];
        }
    }];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[Web] 导航失败: %@", error.localizedDescription);
    [self retryIfNeeded];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[Web] 连接失败: %ld %@", (long)error.code, error.localizedDescription);
    [self retryIfNeeded];
}

- (void)retryIfNeeded {
    if (self.retryCount < 3) {
        self.retryCount++;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf.webView reload];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
        });
    }
}

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString;
    if ([url.host isEqualToString:@"chat.lingguangsh.com"] ||
        [scheme isEqualToString:@"about"] ||
        [scheme isEqualToString:@"blob"] ||
        [scheme isEqualToString:@"data"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
    requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
                          initiatedByFrame:(WKFrameInfo *)frame
                                      type:(WKMediaCaptureType)type
                           decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    decisionHandler(WKPermissionDecisionGrant);
}

- (void)webView:(WKWebView *)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                     completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        completionHandler();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

@end
