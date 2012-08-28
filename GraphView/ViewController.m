#import "ViewController.h"
#import "GraphView.h"

@interface ViewController ()

@end

@implementation ViewController {
    IBOutlet GraphView *_myView;
    NSTimer *_timer;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _timer = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(timerDidFire:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)timerDidFire:(NSTimer *)timer {
    [_myView addRandomSample];
}

@end
