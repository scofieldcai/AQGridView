
#import "LazyLoadingDemoViewController.h"
#import "AppRecord.h"
#import "IconDownloader.h"


#import "LazyLoadingDemoFooterView.h"



#import "ParseOperation.h"
#import "AppRecord.h"

// This framework was imported so we could use the kCFURLErrorNotConnectedToInternet error code.
#import <CFNetwork/CFNetwork.h>


static NSString *const TopPaidAppsFeed =
@"http://phobos.apple.com/WebObjects/MZStoreServices.woa/ws/RSS/toppaidapplications/limit=2/xml";


@interface LazyLoadingDemoViewController () <UIScrollViewDelegate>


// the queue to run our "ParseOperation"
@property (nonatomic, strong) NSOperationQueue *queue;
// RSS feed network connection to the App Store
@property (nonatomic, strong) NSURLConnection *appListFeedConnection;
@property (nonatomic, strong) NSMutableData *appListData;


@property (nonatomic, strong) NSMutableDictionary *imageDownloadsInProgress;
@property  BOOL isDragging_msg, isDecliring_msg;

@end



@implementation LazyLoadingDemoViewController



#pragma mark -
#pragma mark LyfeCyecle



// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void) viewDidLoad
{
    [super viewDidLoad];

//    self.gridView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
//	self.gridView.autoresizesSubviews = YES;
	self.gridView.delegate = self;
	self.gridView.dataSource = self;
    self.gridView.flexibleFooterView = YES;
    
    [self setupGridView:self.gridView];

   [self startIconRequest];
    
    self.imageDownloadsInProgress = [NSMutableDictionary dictionary];
    self.contentsArray = [NSMutableArray arrayWithCapacity:200];


}


// Override to allow orientations other than the default portrait orientation.
- (BOOL) shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation) interfaceOrientation
{
    return YES;
}



#pragma mark -
#pragma mark Icon Request

-(void)startIconRequest
{

    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:TopPaidAppsFeed]];
    self.appListFeedConnection = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self];
    
    // Test the validity of the connection object. The most likely reason for the connection object
    // to be nil is a malformed URL, which is a programmatic error easily detected during development
    // If the URL is more dynamic, then you should implement a more flexible validation technique, and
    // be able to both recover from errors and communicate problems to the user in an unobtrusive manner.
    //
    NSAssert(self.appListFeedConnection != nil, @"Failure to create URL connection.");
    
    // show in the status bar that network activity is starting
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

// -------------------------------------------------------------------------------
//	handleError:error
// -------------------------------------------------------------------------------
- (void)handleError:(NSError *)error
{
    NSString *errorMessage = [error localizedDescription];
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Cannot Show Top Paid Apps"
														message:errorMessage
													   delegate:nil
											  cancelButtonTitle:@"OK"
											  otherButtonTitles:nil];
    [alertView show];
}

// The following are delegate methods for NSURLConnection. Similar to callback functions, this is how
// the connection object,  which is working in the background, can asynchronously communicate back to
// its delegate on the thread from which it was started - in this case, the main thread.
//
#pragma mark - NSURLConnectionDelegate methods

// -------------------------------------------------------------------------------
//	connection:didReceiveResponse:response
// -------------------------------------------------------------------------------
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.appListData = [NSMutableData data];    // start off with new data
}

// -------------------------------------------------------------------------------
//	connection:didReceiveData:data
// -------------------------------------------------------------------------------
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.appListData appendData:data];  // append incoming data
}

// -------------------------------------------------------------------------------
//	connection:didFailWithError:error
// -------------------------------------------------------------------------------
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    if ([error code] == kCFURLErrorNotConnectedToInternet)
	{
        // if we can identify the error, we can present a more precise message to the user.
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"No Connection Error"
															 forKey:NSLocalizedDescriptionKey];
        NSError *noConnectionError = [NSError errorWithDomain:NSCocoaErrorDomain
														 code:kCFURLErrorNotConnectedToInternet
													 userInfo:userInfo];
        [self handleError:noConnectionError];
    }
	else
	{
        // otherwise handle the error generically
        [self handleError:error];
    }
    
    self.appListFeedConnection = nil;   // release our connection
}


// -------------------------------------------------------------------------------
//	connectionDidFinishLoading:connection
// -------------------------------------------------------------------------------
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    self.appListFeedConnection = nil;   // release our connection
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    // create the queue to run our ParseOperation
    self.queue = [[NSOperationQueue alloc] init];
    
    // create an ParseOperation (NSOperation subclass) to parse the RSS feed data
    // so that the UI is not blocked
    ParseOperation *parser = [[ParseOperation alloc] initWithData:self.appListData];
    
    parser.errorHandler = ^(NSError *parseError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleError:parseError];
        });
    };
    
    // Referencing parser from within its completionBlock would create a retain
    // cycle.
    __weak ParseOperation *weakParser = parser;
    __weak LazyLoadingDemoViewController *weakSelf = self;

    parser.completionBlock = ^(void) {
        if (weakParser.appRecordList) {
            // The completion block may execute on any thread.  Because operations
            // involving the UI are about to be performed, make sure they execute
            // on the main thread.
            dispatch_async(dispatch_get_main_queue(), ^{
                // The root rootViewController is the only child of the navigation
                // controller, which is the window's rootViewController.
                
                NSLog(@"connectionDidFinishLoading count = %d", weakParser.appRecordList.count );
        
                [weakSelf.contentsArray addObjectsFromArray:weakParser.appRecordList];
                
                /*
                CGRect rect = weakSelf.gridView.frame;
                rect.size.height = 140;
                [weakSelf.gridView setContentSize:rect.size];
                rect.size.height = 140+60;
                [weakSelf.gridView setFrame:rect];*/
                
                // tell our table view to reload its data, now that parsing has completed
                [weakSelf.gridView reloadData];
                

                
                // 永久に取得してみる
                [weakSelf performSelector:@selector(startIconRequest) withObject:nil afterDelay:1];
            });
        }
        
        // we are finished with the queue and our ParseOperation
        self.queue = nil;
    };
    
    [self.queue addOperation:parser]; // this will start the "ParseOperation"
    
    // ownership of appListData has been transferred to the parse operation
    // and should no longer be referenced in this thread
    self.appListData = nil;
}

#pragma mark - private view setup

- (void)setupGridView:(AQGridView*)gridView {
    if( gridView == nil ){
        return;
    }
    
    gridView.contentOffset = CGPointMake(0, 0);
    

    

    //gridView.resizesCellWidthToFit = YES;
    
//    CGSize size =  gridView.contentSize;
//    size.height = 0;
//    [gridView setContentSize:size];
    
/*
    CGRect rect = gridView.frame;
    rect.size.height = 60;
    [gridView setFrame:rect];
    [gridView setContentSize:rect.size];*/

	UIEdgeInsets inset = gridView.contentInset;
	inset.bottom = 120;
	[gridView setContentInset:inset];

    
    if( gridView.gridFooterView != nil ){
        id footer = gridView.gridFooterView;
        if( footer != nil ){
            if([footer isKindOfClass:[LazyLoadingDemoFooterView class]]){
                LazyLoadingDemoFooterView *v = (LazyLoadingDemoFooterView*)footer;
                v.activityIndicator.hidden = NO;
                [v.activityIndicator startAnimating];
                return;
            }
        }
    }
    
    NSString *xibName;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        xibName = @"LazyLoadingDemoViewCellLoading_pad";
    } else {
        xibName = @"LazyLoadingDemoViewCellLoading_phone";
    }
    
    NSArray *nib = [[NSBundle mainBundle] loadNibNamed:xibName owner:nil options:nil];
    LazyLoadingDemoFooterView *footerView = (LazyLoadingDemoFooterView *)[nib objectAtIndex:0];
    footerView.activityIndicator.hidden = NO;
    [footerView.activityIndicator startAnimating];
    gridView.gridFooterView = footerView;
    

}


#pragma mark -
#pragma mark Grid View Data Source

- (NSUInteger) numberOfItemsInGridView: (AQGridView *) aGridView
{
    return ( [_contentsArray count] );
}

- (AQGridViewCell *) gridView: (AQGridView *) aGridView cellForItemAtIndex: (NSUInteger) index
{
//    NSLog(@"cellForItemAtIndex = %d", index);
    
	static NSString *CellIdentifier = @"LazyLoadingDemoViewCell";
	
	AQGridViewCell *cell = (AQGridViewCell *)[aGridView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil)
	{
		[[NSBundle mainBundle] loadNibNamed:@"LazyLoadingDemoViewCell" owner:self options:nil];
        
		cell = [[AQGridViewCell alloc] initWithFrame:self.lazyLoadingViewCell.frame
									  reuseIdentifier:CellIdentifier];
		[cell.contentView addSubview:self.lazyLoadingViewCell];
		
		cell.selectionStyle = AQGridViewCellSelectionStyleNone;
	}
    
    UIView *view = [cell.subviews objectAtIndex:0];

    AppRecord *appRecord = [self.contentsArray objectAtIndex:index];
    UILabel *iconTitle = (UILabel*)[view viewWithTag:2];
    iconTitle.text = appRecord.appName;
    
    UIImageView *iconImg = (UIImageView*)[view viewWithTag:1];
    
    if ( appRecord.appIcon ) {
        iconImg.image = appRecord.appIcon;
    }
    else
    {
        if (!_isDragging_msg && !_isDecliring_msg)
        {
            [self startIconDownload:appRecord index:[NSNumber numberWithInteger:index]];
        }
        else
        {
            iconImg.image = [UIImage imageNamed:@"Placeholder.png"];
        }
    }
    
    
	return cell;
}

- (CGSize) portraitGridCellSizeForGridView: (AQGridView *) aGridView
{
	[[NSBundle mainBundle] loadNibNamed:@"LazyLoadingDemoViewCell" owner:self options:nil];
	return self.lazyLoadingViewCell.frame.size;
}


// -------------------------------------------------------------------------------
//	startIconDownload:forIndexPath:
// -------------------------------------------------------------------------------
- (void)startIconDownload:(AppRecord *)appRecord index:(NSNumber*)index
{

    IconDownloader *iconDownloader = [self.imageDownloadsInProgress objectForKey:index];

    if (iconDownloader == nil){
        // まだ取得開始していない
        
        iconDownloader = [[IconDownloader alloc] init];
        iconDownloader.appRecord = appRecord;
        [iconDownloader setCompletionHandler:^{
            
            AQGridViewCell *cell = [self.gridView cellForItemAtIndex:[index intValue]];
            
            // Display the newly loaded image
            UIView *view = [cell.subviews objectAtIndex:0];
            UIImageView *iconImg = (UIImageView*)[view viewWithTag:1];
            iconImg.image = appRecord.appIcon;
            
            // Remove the IconDownloader from the in progress list.
            // This will result in it being deallocated.
            [self.imageDownloadsInProgress removeObjectForKey:index];
            
            //[cell.contentView setNeedsLayout];
            
        }];
        [self.imageDownloadsInProgress setObject:iconDownloader forKey:index];
        
        [iconDownloader startDownload];
    }

}

#pragma mark -
#pragma mark ScrollView Delegate

//ドラッグ終了時にコール
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate{
    NSLog(@"scrollViewDidEndDragging");
    
    self.isDragging_msg = FALSE;
    [self.gridView reloadData];
}

// スクロール・ビューの動きが減速終了した。
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView{
    NSLog(@"scrollViewDidEndDecelerating");

    self.isDecliring_msg = FALSE;
    [self.gridView reloadData];
}

//ドラッグ開始時にコール
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView{
    NSLog(@"scrollViewWillBeginDragging");

    self.isDragging_msg = TRUE;
}

//スクロール・ビューの動きが減速しだした
- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView{
    NSLog(@"scrollViewWillBeginDecelerating");

    self.isDecliring_msg = TRUE;
}

@end
