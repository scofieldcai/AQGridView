
#import <UIKit/UIKit.h>
#import "AQGridView.h"

@interface LazyLoadingDemoViewController : UIViewController <AQGridViewDelegate, AQGridViewDataSource>


@property (nonatomic, retain) IBOutlet AQGridView * gridView;

@property (nonatomic, strong) NSMutableArray *contentsArray;

@property (strong, nonatomic) IBOutlet UIView *lazyLoadingViewCell;


@end

