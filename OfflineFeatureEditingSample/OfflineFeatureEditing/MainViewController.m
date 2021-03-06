// Copyright 2013 ESRI
//
// All rights reserved under the copyright laws of the United States
// and applicable international laws, treaties, and conventions.
//
// You may freely redistribute and use this sample code, with or
// without modification, provided you include the original copyright
// notice and use restrictions.
//
// See the use restrictions at http://help.arcgis.com/en/sdk/10.0/usageRestrictions.htm
//

#import "MainViewController.h"
#import "AppDelegate.h"
#import "FeatureTemplatePickerViewController.h"
#import "SVProgressHUD.h"
#import "JSBadgeView.h"
#import "UIAlertView+NSCookbook.h"
#import "LoadingView.h"
#import "BackgroundHelper.h"

#define kTilePackageName @"SanFrancisco"
#define kFeatureServiceURL @"http://services.arcgis.com/P3ePLMYs2RVChkJx/arcgis/rest/services/Wildfire/FeatureServer"

@interface MainViewController () <AGSLayerDelegate, AGSMapViewTouchDelegate, AGSPopupsContainerDelegate, AGSMapViewLayerDelegate, AGSCalloutDelegate, AGSFeatureLayerEditingDelegate, FeatureTemplatePickerDelegate>{
    
    
    AGSLocalTiledLayer *_localTiledLayer;

    NSString *_replicaJobId;
    AGSPopupsContainerViewController *_popupsVC;
    AGSSketchGraphicsLayer *_sgl;
    
    JSBadgeView* _badge;
    LoadingView* _loadingView;
    
    BOOL _goingLocal;
    BOOL _goingLive;
    BOOL _viewingLocal;
    
    
    UITextView *_logsTextView;
    
    NSMutableString *_allStatus;
    
    UIPopoverController* _pvc;
    FeatureTemplatePickerViewController* _featureTemplatePickerVC;
    
    BOOL _newlyDownloaded;
}
@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UIView *badgeView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *liveActivityIndicator;
@property (weak, nonatomic) IBOutlet UIToolbar *geometryEditToolbar;


@property (nonatomic, strong) AGSGDBGeodatabase *geodatabase;
@property (nonatomic, strong) AGSGDBSyncTask *gdbTask;
@property (nonatomic, strong) id<AGSCancellable> cancellable;
@property (nonatomic, strong) AGSMapView* mapView;
- (IBAction)cancelEditingGeometry:(id)sender;
- (IBAction)doneEditingGeometry:(id)sender;
@end

@implementation MainViewController


- (void)viewDidLoad{
    
    [super viewDidLoad];
    
    //Add a map view to the UI
    self.mapView = [[AGSMapView alloc]initWithFrame:self.mapContainer.bounds];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.mapContainer addSubview:self.mapView];
    self.mapView.touchDelegate = self;
    self.mapView.layerDelegate = self;
    self.mapView.callout.delegate = self;

    //Add the basemap layer from a tile package
    _localTiledLayer =  [AGSLocalTiledLayer localTiledLayerWithName:kTilePackageName];
    
    //Add layer delegate to catch errors in case the local tiled layer is replaced and problems arise
    _localTiledLayer.delegate = self;
    
    [self.mapView addMapLayer:_localTiledLayer];
    


    _allStatus = [NSMutableString string];
    
    
    //Add a view that will display logs
    CGRect f = self.mapView.frame;
    _logsTextView = [[UITextView alloc]initWithFrame:f];
    _logsTextView.hidden = YES;
    _logsTextView.userInteractionEnabled = YES;
    _logsTextView.autoresizingMask = _mapView.autoresizingMask;
    _logsTextView.backgroundColor = [[UIColor blackColor]colorWithAlphaComponent:.78];
    _logsTextView.textColor = [UIColor whiteColor];
    _logsTextView.editable = NO;
    
    //Add a swipe gesture recognizer that will show this view
    UISwipeGestureRecognizer *gr2 = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(showLogsGesture:)];
    gr2.direction = UISwipeGestureRecognizerDirectionUp;
    [self.logsLabel addGestureRecognizer:gr2];

    //Add a tap gesture recognizer that will hide this view
    UITapGestureRecognizer *gr = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(hideLogsGesture:)];
    [_logsTextView addGestureRecognizer:gr];
    [self.view addSubview:_logsTextView];
    
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(featuresLoaded:) name:AGSFeatureLayerDidLoadFeaturesNotification object:nil];
    
    [self switchToLiveData];


}

- (void)viewDidUnload{
    [self setMapContainer:nil];
    [self setLogsLabel:nil];
    [self setLeftContainer:nil];
    [self setAddFeatureButton:nil];
    [self setSyncButton:nil];
    [self setGoOfflineButton:nil];
    [self setGoOfflineButton:nil];
    [self setOfflineStatusLabel:nil];
    [super viewDidUnload];
}

- (void)didReceiveMemoryWarning{
    [super didReceiveMemoryWarning];
    if(!_pvc.popoverVisible){
        _pvc =  nil;
        _featureTemplatePickerVC = nil;
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation{
    return YES;
}


#pragma mark Gesture Recognizers

-(void)hideLogsGesture:(UIGestureRecognizer*)gr{
    _logsTextView.hidden = YES;
}

-(void)showLogsGesture:(UIGestureRecognizer*)gr{
    _logsTextView.hidden = NO;
}

#pragma mark AGSLayerDelegate methods

-(void)layerDidLoad:(AGSLayer *)layer{
    if([layer isKindOfClass:[AGSFeatureLayer class]]){
        AGSFeatureLayer* fl = (AGSFeatureLayer*)layer;
        if(self.mapView.mapScale>fl.minScale)
            [self.mapView zoomToScale:fl.minScale animated:YES];
        [SVProgressHUD popActivity];
    }
}


-(void)layer:(AGSLayer *)layer didFailToLoadWithError:(NSError *)error{
    NSString *errmsg;
    
    if([layer isKindOfClass:[AGSFeatureLayer class]]){
        AGSFeatureLayer* fl = (AGSFeatureLayer*)layer;
        errmsg = [NSString stringWithFormat:@"Failed to load %@. Error:%@",fl.URL, error];
        
        // activity shown when loading online layer, dismiss this
        [SVProgressHUD popActivity];
    }
    else if([layer isKindOfClass:[AGSLocalTiledLayer class]]){
        errmsg = [NSString stringWithFormat:@"Failed to load local tiled layer. Error:%@", error];
    }
    
    [self logStatus:errmsg];
}

#pragma mark - AGSFeatureLayerDidLoadFeaturesNotification
- (void) featuresLoaded:(NSNotification*) notification{
    //Show the activity indicator for a couple of seconds
    [self.liveActivityIndicator startAnimating];
    AGSFeatureLayer* fLyr = (AGSFeatureLayer*)notification.object;
    [self logStatus:[NSString stringWithFormat:@"Refreshed live data %@",fLyr.URL]];
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self.liveActivityIndicator stopAnimating];
    });
}

#pragma mark - AGSMapViewTouchDelegate methods
- (void) mapView:(AGSMapView *)mapView didClickAtPoint:(CGPoint)screen mapPoint:(AGSPoint *)mappoint features:(NSDictionary *)features {
    
    //Show popups for features that were tapped on
    NSMutableArray *tappedFeatures = [[NSMutableArray alloc]init];
    NSEnumerator* keys = [features keyEnumerator];
    for (NSString* key in keys) {
        [tappedFeatures addObjectsFromArray:[features objectForKey:key]];
    }
        if (tappedFeatures.count){
            [self showPopupsForFeatures:tappedFeatures];
        }
        else{
            [self hidePopupsVC];
        }
    
}

#pragma mark - Showing popups
-(void)showPopupsForFeatures:(NSArray*)features{
    NSMutableArray *popups = [NSMutableArray arrayWithCapacity:features.count];

    for (id<AGSFeature> feature in features) {
        AGSPopup* popup;
        
        //If the feature is a graphic (means we are in Live mode)
        if([feature isKindOfClass:[AGSGraphic class]]){
            AGSGraphic* graphic = (AGSGraphic*)feature;
            AGSPopupInfo* popupInfo = [AGSPopupInfo popupInfoForFeatureLayer:(AGSFeatureLayer*)graphic.layer];
            popup = [AGSPopup popupWithGraphic:graphic popupInfo:popupInfo];
            
        //If the feature is a gdbfeature (means we are in Local mode)
        }else if ([feature isKindOfClass:[AGSGDBFeature class]]){
            AGSGDBFeature* gdbFeature = (AGSGDBFeature*)feature;
            AGSPopupInfo* popupInfo = [AGSPopupInfo popupInfoForGDBFeatureTable:gdbFeature.table];
            popup = [AGSPopup popupWithGDBFeature:gdbFeature popupInfo:popupInfo];
        }
        [popups addObject:popup];
    }
    
        [self showPopupsVCForPopups:popups];
}

-(void)hidePopupsVC{
    if ([[AGSDevice currentDevice] isIPad]) {
        for (UIView *sv in _leftContainer.subviews){
            [sv removeFromSuperview];
        }
        _popupsVC = nil;
        _leftContainer.hidden = YES;
    }
    else {
        [_popupsVC dismissViewControllerAnimated:YES completion:^{
            _popupsVC = nil;
        }];
    }
    
}


-(void)showPopupsVCForPopups:(NSArray*)popups{
    
    [self hidePopupsVC];
    
    //Create the view controller for the popups
        _popupsVC = [[AGSPopupsContainerViewController alloc]initWithPopups:popups usingNavigationControllerStack:NO];
        _popupsVC.delegate = self;
        _popupsVC.style = AGSPopupsContainerStyleBlack;
        _popupsVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;        
    
    //On ipad, display the popups vc a form sheet on the left
    if ([[AGSDevice currentDevice] isIPad]) {
        _leftContainer.hidden = NO;
        _popupsVC.modalPresentationStyle = UIModalPresentationFormSheet;
        _popupsVC.view.frame = _leftContainer.bounds;
        [_leftContainer addSubview:_popupsVC.view];
    }
    //On iphone, display the vc in full screen
    else {
        _popupsVC.modalPresentationStyle = UIModalPresentationFullScreen;
        _popupsVC.view.frame = self.view.bounds;
        [self presentViewController:_popupsVC animated:YES completion:nil];

    }
}

#pragma mark Action methods

- (IBAction)addFeatureAction:(id)sender {
    
    //Initialize the template picker view controller
    if(!_featureTemplatePickerVC){
        _featureTemplatePickerVC = [[FeatureTemplatePickerViewController alloc]init];
        _featureTemplatePickerVC.delegate = self;
        [_featureTemplatePickerVC addTemplatesForLayersInMap:self.mapView];
    }
    
    //On iPad, display the template picker vc in a popover
    if ([[AGSDevice currentDevice]isIPad]) {
        if(!_pvc){
            _pvc = [[UIPopoverController alloc]initWithContentViewController:_featureTemplatePickerVC];
        }
        [_pvc presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionDown animated:YES];
        
    //On iPhone, display the vc full screen
    }else{
        [self presentViewController:_featureTemplatePickerVC animated:YES completion:nil];
    }
    

}

- (IBAction)deleteGDBAction:(id)sender {
    if (_viewingLocal || _goingLocal){
        [self logStatus:@"cannot delete local data while displaying it"];
        return;
    }
    _geodatabase = nil;
    
    //Remove all files with .geodatabase, .geodatabase-shm, and .geodatabase-wal file extensions
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [paths objectAtIndex:0];
    NSArray *files = [[NSFileManager defaultManager]contentsOfDirectoryAtPath:path error:nil];
    for (NSString *file in files){
        BOOL remove = [file hasSuffix:@".geodatabase"] || [file hasSuffix:@".geodatabase-shm"] || [file hasSuffix:@".geodatabase-wal"];
        if (remove){
            NSError* error;
            [[NSFileManager defaultManager]removeItemAtPath:[path stringByAppendingPathComponent:file] error:&error];
            [self logStatus:[NSString stringWithFormat:@"deleting %@",file]];
            
        }
    }
    [self logStatus:[NSString stringWithFormat:@"deleted all local data"]];
}

- (IBAction)syncAction:(id)sender {
    
    if (self.cancellable){
        // if already syncing just return
        return;
    }
    [SVProgressHUD showWithStatus:@"Synchronizing \n changes"];
    [self logStatus:@"Starting sync process..."];
    
    //Create default sync params based on the geodatabase
    //You can modify the param to change sync options (sync direction, included layers, etc)
    AGSGDBSyncParameters* param = [[AGSGDBSyncParameters alloc]initWithGeodatabase:self.geodatabase];

    //kick off the sync operation
    self.cancellable = [self.gdbTask syncGeodatabase:self.geodatabase params:param status:^(AGSResumableTaskJobStatus status, NSDictionary *userInfo) {
        [self logStatus:[NSString stringWithFormat:@"sync status: %@", [self statusMessageForAsyncStatus:status]]];
    } completion:^(AGSGDBEditErrors* editErrors, NSError *syncError) {
        self.cancellable = nil;
        if (syncError){
            [self logStatus:[NSString stringWithFormat:@"error sync'ing: %@", syncError]];
            [SVProgressHUD showErrorWithStatus:@"Error encountered"];
        }
        else{
 
// TODO: Handle sync edit errors
            
            [self logStatus:[NSString stringWithFormat:@"sync complete"]];
            [SVProgressHUD showSuccessWithStatus:@"Sync complete"];
            [BackgroundHelper postLocalNotificationIfAppNotActive:@"sync complete"];
            
            //Remove the local edits badge from the sync button
            [self showEditsInGeodatabaseAsBadge:nil];
            
        }
        
    }];
}

- (IBAction)switchModeAction:(id)sender {
    
    if (_goingLocal){
        return;
    }
    
    if (_viewingLocal){
        if([self.geodatabase hasLocalEdits]){
            UIAlertView* av = [[UIAlertView alloc]initWithTitle:@"Local data contains edits" message:@"Do you want to sync them with the service?" delegate:nil cancelButtonTitle:@"Later" otherButtonTitles:@"Yes", nil];
            [av showWithCompletion:^(UIAlertView *alertView, NSInteger buttonIndex) {
                switch (buttonIndex) {
                    case 0: //No, just switch to live
                        [self switchToLiveData];
                        break;
                    case 1: //Yes, sync instead
                        [self syncAction:nil];
                        break;
                    default:
                        break;
                }
            }];
            return;
        }else{
            [self switchToLiveData];
        }
    }
    else{
        
        [self switchToLocalData];
    }
}
#pragma mark - Online/Offline methods



-(void)switchToLiveData{
    
    _goingLive = YES;
    [self logStatus:@"loading live data"];

    //Clear out the template picker so that we create it again when needed using templates in the live data
    _featureTemplatePickerVC = nil;


    self.gdbTask = [[AGSGDBSyncTask alloc]initWithURL:[NSURL URLWithString:kFeatureServiceURL]];
    __weak MainViewController* weakSelf = self;
    self.gdbTask.loadCompletion = ^(NSError* error){
        
        //Remove all local feature layers
        for (AGSLayer* lyr in weakSelf.mapView.mapLayers) {
            if ([lyr isKindOfClass:[AGSFeatureTableLayer class]]) {
                [weakSelf.mapView removeMapLayer:lyr];
            }
        }
        
        //Add live feature layers
        for (AGSMapServiceLayerInfo* info in weakSelf.gdbTask.featureServiceInfo.layerInfos) {
            [SVProgressHUD showProgress:-1 status:@"Loading \n live data"];
            NSURL* url = [weakSelf.gdbTask.URL URLByAppendingPathComponent:[NSString stringWithFormat:@"%lu",(unsigned long)info.layerId]];
            
            AGSFeatureLayer* fl = [AGSFeatureLayer featureServiceLayerWithURL:url mode:AGSFeatureLayerModeOnDemand credential:weakSelf.gdbTask.credential];
            fl.outFields = @[@"*"];
            fl.delegate = weakSelf;
            fl.editingDelegate = weakSelf;
            fl.expirationInterval = 60;
            fl.autoRefreshOnExpiration = YES;
            
            [weakSelf.mapView addMapLayer:fl];
            [weakSelf logStatus:[NSString stringWithFormat:@"loading: %@", [fl.URL absoluteString]]];
        }
        [weakSelf logStatus:@"now in live mode"];
        [weakSelf updateStatus];
    };
    
    _goingLive = NO;
    _viewingLocal = NO;
    
}
-(void)switchToLocalData{
    
    _goingLocal = YES;
    
    //Clear out the template picker so that we create it again when needed using templates in the local data
    _featureTemplatePickerVC = nil;

    
    AGSGDBGenerateParameters *params = [[AGSGDBGenerateParameters alloc]initWithFeatureServiceInfo:self.gdbTask.featureServiceInfo];
    
    //NOTE: You should typically set this to a smaller envelope covering an area of interest
    //Setting to maxEnvelope here because sample data covers limited area in San Francisco
    params.extent = self.mapView.maxEnvelope;
    params.outSpatialReference = self.mapView.spatialReference;
    NSMutableArray* layers = [[NSMutableArray alloc]init];
    for (AGSMapServiceLayerInfo* layerInfo in self.gdbTask.featureServiceInfo.layerInfos) {
        [layers addObject:[NSNumber numberWithInt: (int)layerInfo.layerId]];
    }
    params.layerIDs = layers;
    _newlyDownloaded = NO;
    [SVProgressHUD showWithStatus:@"Preparing to \n download"];
    [self.gdbTask generateGeodatabaseWithParameters:params downloadFolderPath:nil useExisting:YES status:^(AGSResumableTaskJobStatus status, NSDictionary *userInfo) {
        
        //If we are fetching result, display download progress
        if(status == AGSResumableTaskJobStatusFetchingResult){
            _newlyDownloaded = YES;
            NSNumber* totalBytesDownloaded = userInfo[@"AGSDownloadProgressTotalBytesDownloaded"];
            NSNumber* totalBytesExpected = userInfo[@"AGSDownloadProgressTotalBytesExpected"];
            if(totalBytesDownloaded!=nil && totalBytesExpected!=nil){
                double dPercentage = (double)([totalBytesDownloaded doubleValue]/[totalBytesExpected doubleValue]);
                [SVProgressHUD showProgress:dPercentage status:@"Downloading \n features"];
            }
        }else{
            //don't want to log status for "fetching result" state because
            //status block gets called many times a second when downloading.
            //we only log status for other states here
            [self logStatus:[NSString stringWithFormat:@"Status: %@", [self statusMessageForAsyncStatus:status]]];
        }
    } completion:^(AGSGDBGeodatabase *geodatabase, NSError *error) {
        if (error){
            //handle the error
            _goingLocal = NO;
            _viewingLocal = NO;
            [self logStatus:[NSString stringWithFormat:@"error taking feature layers offline: %@", error]];
            [SVProgressHUD showErrorWithStatus:@"Couldn't download features"];
        }
        else{
            //take app into offline mode
            _goingLocal = NO;
            _viewingLocal = YES;
            [self logStatus:@"now viewing local data"];
            [BackgroundHelper postLocalNotificationIfAppNotActive:@"Features downloaded."];
            
            //remove the live feature layers
            for (AGSLayer* lyr in self.mapView.mapLayers) {
                if([lyr isKindOfClass:[AGSFeatureLayer class]])
                    [self.mapView removeMapLayer:lyr];
            }
            
            //add layers from local geodatabase
            self.geodatabase = geodatabase;
            for (AGSFeatureTable* fTable in geodatabase.featureTables) {
                if ([fTable hasGeometry]) {
                    [self.mapView addMapLayer:[[AGSFeatureTableLayer alloc]initWithFeatureTable:fTable]];
                }
            }
            
            if (_newlyDownloaded) {
                [SVProgressHUD showSuccessWithStatus:@"Finished \n downloading"];
            }else{
                [SVProgressHUD dismiss];
                [self showEditsInGeodatabaseAsBadge:geodatabase];
                UIAlertView* av = [[UIAlertView alloc]initWithTitle:@"Found local data" message:@" It may contain edits or may be out of date. Do you want synchronize it with the service?" delegate:nil cancelButtonTitle:@"Later" otherButtonTitles:@"Yes", nil];
                [av showWithCompletion:^(UIAlertView *alertView, NSInteger buttonIndex) {
                    switch (buttonIndex) {
                        case 0: //do nothing
                            break;
                        case 1: //Yes, sync
                            [self syncAction:nil];
                            break;
                        default:
                            break;
                    }
                }];
                
            }
        }
        [self updateStatus];
        
        
    }];
    
    
}

#pragma mark - FeatureTemplatePickerViewControllerDelegate methods

- (void)featureTemplatePickerViewController:(FeatureTemplatePickerViewController *)featureTemplatePickerViewController didSelectFeatureTemplate:(AGSFeatureTemplate *)template forLayer:(id<AGSGDBFeatureSourceInfo>)layer{
    if ([[AGSDevice currentDevice]isIPad]) {
        [_pvc
         dismissPopoverAnimated:YES];
        if([layer isKindOfClass:[AGSFeatureLayer class]]){
            AGSFeatureLayer* fLayer = (AGSFeatureLayer*)layer;
            AGSGraphic* graphic = [fLayer featureWithTemplate:template];
            [fLayer addGraphic:graphic];
            AGSPopupInfo *pi = [AGSPopupInfo popupInfoForFeatureLayer:fLayer];
            AGSPopup *p = [[AGSPopup alloc]initWithGraphic:graphic popupInfo:pi featureLayer:fLayer];
            [self showPopupsVCForPopups:@[p]];
            [_popupsVC startEditingCurrentPopup];
        }else if([layer isKindOfClass:[AGSGDBFeatureTable class]]){
            AGSGDBFeatureTable* fTable = (AGSGDBFeatureTable*) layer;
            AGSGDBFeature* feature = [fTable featureWithTemplate:template];
            AGSPopupInfo *pi = [AGSPopupInfo popupInfoForGDBFeatureTable:fTable];
            AGSPopup *p = [[AGSPopup alloc]initWithGDBFeature:feature popupInfo:pi];
            [self showPopupsVCForPopups:@[p]];
            [_popupsVC startEditingCurrentPopup];
        }

    }else{
        [featureTemplatePickerViewController dismissViewControllerAnimated:YES completion:^{
            if([layer isKindOfClass:[AGSFeatureLayer class]]){
                AGSFeatureLayer* fLayer = (AGSFeatureLayer*)layer;
                AGSGraphic* graphic = [fLayer featureWithTemplate:template];
                [fLayer addGraphic:graphic];
                AGSPopupInfo *pi = [AGSPopupInfo popupInfoForFeatureLayer:fLayer];
                AGSPopup *p = [[AGSPopup alloc]initWithGraphic:graphic popupInfo:pi featureLayer:fLayer];
                [self showPopupsVCForPopups:@[p]];
                [_popupsVC startEditingCurrentPopup];
            }else if([layer isKindOfClass:[AGSGDBFeatureTable class]]){
                AGSGDBFeatureTable* fTable = (AGSGDBFeatureTable*) layer;
                AGSGDBFeature* feature = [fTable featureWithTemplate:template];
                AGSPopupInfo *pi = [AGSPopupInfo popupInfoForGDBFeatureTable:fTable];
                AGSPopup *p = [[AGSPopup alloc]initWithGDBFeature:feature popupInfo:pi];
                [self showPopupsVCForPopups:@[p]];
                [_popupsVC startEditingCurrentPopup];
            }

        }];
    }
    
}

- (void) featureTemplatePickerViewControllerWasDismissed:(FeatureTemplatePickerViewController *)featureTemplatePickerViewController{
    if ([[AGSDevice currentDevice]isIPad]) {
        [_pvc
         dismissPopoverAnimated:YES];
    }else{
        [featureTemplatePickerViewController dismissViewControllerAnimated:YES completion:nil];
    }
}



#pragma mark AGSPopupsContainerDelegate methods

-(AGSGeometry *)popupsContainer:(id<AGSPopupsContainer>)popupsContainer wantsNewMutableGeometryForPopup:(AGSPopup *)popup{
    switch (popup.gdbFeatureSourceInfo.geometryType) {
        case AGSGeometryTypePoint:
            return [[AGSMutablePoint alloc]initWithSpatialReference:self.mapView.spatialReference];
            break;
        case AGSGeometryTypePolygon:
            return [[AGSMutablePolygon alloc]initWithSpatialReference:self.mapView.spatialReference];
            break;
        case AGSGeometryTypePolyline:
            return [[AGSMutablePolyline alloc]initWithSpatialReference:self.mapView.spatialReference];
            break;
        default:
            return [[AGSMutablePoint alloc]initWithSpatialReference:self.mapView.spatialReference];
            break;
    }
}

-(void) popupsContainer:(id<AGSPopupsContainer>)popupsContainer readyToEditGeometry:(AGSGeometry *)geometry forPopup:(AGSPopup *)popup {

    if (!_sgl){
        _sgl = [[AGSSketchGraphicsLayer alloc]initWithGeometry:geometry];
        [_mapView addMapLayer:_sgl];
        _mapView.touchDelegate = _sgl;
    }
    else{
        _sgl.geometry = geometry;
    }
    
    // if we are on iPhone, hide the popupsVC and show editing UI
    if (![[AGSDevice currentDevice] isIPad]) {
        [_popupsVC dismissViewControllerAnimated:YES completion:nil];
        [self toggleGeometryEditUI];
    }
}


-(void)popupsContainerDidFinishViewingPopups:(id<AGSPopupsContainer>)popupsContainer{
    //
    // this clears _currentPopups
    [self hidePopupsVC];
}

-(void)popupsContainer:(id<AGSPopupsContainer>)popupsContainer didCancelEditingForPopup:(AGSPopup *)popup {
    [_mapView removeMapLayer:_sgl];
    _sgl = nil;
    _mapView.touchDelegate = self;
    [self hidePopupsVC];
}

-(void) popupsContainer:(id<AGSPopupsContainer>)popupsContainer didFinishEditingForPopup:(AGSPopup *)popup {

    [_mapView removeMapLayer:_sgl];
    _sgl = nil;
    _mapView.touchDelegate = self;
    
    // dealing with 'offline' feature
    // popup vc has already committed edits to the local geodatabase
    if (popup.gdbFeature){
        [self showEditsInGeodatabaseAsBadge:popup.gdbFeatureTable.geodatabase];
        [self logStatus:@"feature saved"];
        [self hidePopupsVC];
    }
    // dealing with 'online' feature
    // we must apply edits to the server
    else if (popup.graphic){
        _loadingView = [LoadingView loadingViewInView:_popupsVC.view withText:@"Applying edit to server..."];
        if ([popup.featureLayer objectIdForFeature:popup.graphic]<0){
            [popup.featureLayer addFeatures:@[popup.graphic]];
        }
        else{
            [popup.featureLayer updateFeatures:@[popup.graphic]];
        }
    }
    
}

-(void) popupsContainer:(id<AGSPopupsContainer>)popupsContainer didDeleteForPopup:(AGSPopup *)popup {
    [self logStatus:@"delete succeded"];
    [self showEditsInGeodatabaseAsBadge:popup.gdbFeatureTable.geodatabase];
    [self hidePopupsVC];
}

-(void) popupsContainer:(id<AGSPopupsContainer>)popupsContainer wantsToDeleteForPopup:(AGSPopup *)popup{
    AGSFeatureLayer* fLayer = (AGSFeatureLayer*) popup.graphic.layer;
    [fLayer deleteFeaturesWithObjectIds:@[[NSNumber numberWithLongLong:[fLayer objectIdForFeature:popup.graphic]]]];
    _loadingView = [LoadingView loadingViewInView:_popupsVC.view withText:@"Applying edit to server..."];
}

#pragma mark AGSFeatureLayerEditingDelegate methods

-(void)featureLayer:(AGSFeatureLayer *)featureLayer operation:(NSOperation *)op didFeatureEditsWithResults:(AGSFeatureLayerEditResults *)editResults{
    [_loadingView removeView];
    if(editResults.addResults){
        AGSEditResult* res = editResults.addResults[0];
        if (res.error){
            [self logStatus:[NSString stringWithFormat:@"add failed: %@", res.error]];
        }
        else{
            [self logStatus:[NSString stringWithFormat:@"add succeeded: %ld", (long)res.objectId]];
            [self hidePopupsVC];
        }
    }
    
    if(editResults.updateResults){
        AGSEditResult* res = editResults.updateResults[0];
        if (res.error){
            [self logStatus:[NSString stringWithFormat:@"update failed: %@", res.error]];
        }
        else{
            [self logStatus:[NSString stringWithFormat:@"update succeeded: %ld", (long)res.objectId]];
            [self hidePopupsVC];
        }
    }
    
    if(editResults.deleteResults){
        AGSEditResult* res = editResults.deleteResults[0];
        if (res.error){
            [self logStatus:[NSString stringWithFormat:@"delete failed: %@", res.error]];
        }
        else{
            [self logStatus:[NSString stringWithFormat:@"delete succeeded: %ld", (long)res.objectId]];
            [self hidePopupsVC];
        }
    }
}

#pragma mark - Convenience methods

- (NSNumber*) numberOfEditsInGeodatabase:(AGSGDBGeodatabase*)gdb{
    int total = 0;
    for (AGSGDBFeatureTable* ftable in gdb.featureTables) {
        total += [ftable addedFeatures].count + [ftable deletedFeatures].count + [ftable updatedFeatures].count;
    }
    return [NSNumber numberWithInt:total] ;
}

-(void)logStatus:(NSString*)status{
    
    if (![NSThread isMainThread]){
        [self performSelectorOnMainThread:@selector(logStatus:) withObject:status waitUntilDone:NO];
        return;
    }
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearStatus) object:nil];
    
    // show basic status
    self.logsLabel.text = status;
    
    NSString *hideText = @"\nTap to hide...";
    
    NSDateFormatter *df = [[NSDateFormatter alloc]init];
    df.dateStyle = NSDateFormatterNoStyle;
    df.timeStyle = NSDateFormatterShortStyle;
    status = [NSString stringWithFormat:@"%@ - %@\n\n", [df stringFromDate:[NSDate date]], status];
    [_allStatus insertString:status atIndex:0];
    if ([[UIDevice currentDevice]userInterfaceIdiom] == UIUserInterfaceIdiomPad){
        _logsTextView.text = [NSString stringWithFormat:@"%@\n\n%@", hideText, _allStatus];
    }
    else{
        _logsTextView.text = [NSString stringWithFormat:@"%@\n\n%@", hideText, _allStatus];
    }
    NSLog(@"%@", status);
    
    // write to log file
    AppDelegate *app = (AppDelegate*)[UIApplication sharedApplication].delegate;
    [app logAppStatus:status];
    
    [self performSelector:@selector(clearStatus) withObject:nil afterDelay:2];
}

-(void)clearStatus{
    self.logsLabel.text = @"swipe up to show activity log   ";
}

-(void)updateStatus{
    
    if (![NSThread isMainThread]){
        [self performSelectorOnMainThread:@selector(updateStatus) withObject:nil waitUntilDone:NO];
        return;
    }
    
    
    // set status
    if (_goingLocal){
        _offlineStatusLabel.text = @"switching to local data...";
    }
    else if (_goingLive){
        _offlineStatusLabel.text = @"switching to live data...";
    }
    else if (_viewingLocal){
        _offlineStatusLabel.text = @"Local data";
        _goOfflineButton.title = @"switch to live";
    }
    else if (!_viewingLocal){
        _offlineStatusLabel.text = @"Live data";
        _goOfflineButton.title = @"download";
        [self showEditsInGeodatabaseAsBadge:nil];
    }
    
    _goOfflineButton.enabled = !_goingLocal && !_goingLive;
    self.syncButton.enabled = _viewingLocal;


}

-(NSString*)statusMessageForAsyncStatus:(AGSResumableTaskJobStatus)status
{
    return AGSResumableTaskJobStatusAsString(status);
}

- (void) showEditsInGeodatabaseAsBadge:(AGSGDBGeodatabase*)geodatabase{
    [_badge removeFromSuperview];
    if ([geodatabase hasLocalEdits]) {
        _badge = [[JSBadgeView alloc]initWithParentView:self.badgeView alignment:JSBadgeViewAlignmentCenterRight];
        _badge.badgeText = [[self numberOfEditsInGeodatabase:geodatabase] stringValue];
        
    }
}


-(void)featureLayerDidLoadFeatures:(NSNotification*)notification{
    [SVProgressHUD popActivity];
}

#pragma mark Sketch toolbar UI

- (void)toggleGeometryEditUI {
    self.geometryEditToolbar.hidden = !self.geometryEditToolbar.hidden;
}

- (IBAction)cancelEditingGeometry:(id)sender {
    [self doneEditingGeometry:nil];
}

- (IBAction)doneEditingGeometry:(id)sender {
    [_mapView removeMapLayer:_sgl];
    _sgl = nil;
    _mapView.touchDelegate = self;
    [self toggleGeometryEditUI];
    [self presentViewController:_popupsVC animated:YES completion:nil];
}

#pragma mark -


@end







