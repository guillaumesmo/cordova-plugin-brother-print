#import "APPPrinter.h"
#import <Cordova/CDVAvailability.h>
#import <BRPtouchPrinterKitW/BRPtouchPrintInfo.h>
#import <BRPtouchPrinterKitW/BRPtouchPrinter.h>
#import <BRPtouchPrinterKitW/BRPtouchDeviceInfo.h>

@interface APPPrinter ()

@property (retain) NSString* callbackId;

@end

@implementation APPPrinter

- (void) isAvailable:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* pluginResult;
        BOOL isAvailable = ptp != nil && [ptp isPrinterReady];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                           messageAsBool:isAvailable];

        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:command.callbackId];
    }];
}

- (void) getPrinterList:(CDVInvokedUrlCommand*)command
{
    actCommand = command;
    [self searchPrinters];
}

- (void) setPrinter:(CDVInvokedUrlCommand*) invokedCommand {
    NSArray*  arguments = [invokedCommand arguments];
    NSMutableDictionary* settings = [arguments objectAtIndex:0];

    BRPtouchPrintInfo* printInfo;
    printInfo = [[BRPtouchPrintInfo alloc] init];
    printInfo.strPaperName = @"62mm";
    printInfo.nPrintMode = PRINT_FIT;
    printInfo.nOrientation = ORI_LANDSCAPE;
    printInfo.nHorizontalAlign = ALIGN_CENTER;
    printInfo.nVerticalAlign = ALIGN_MIDDLE;
    printInfo.nAutoCutFlag = 1;
    printInfo.nAutoCutCopies = 1;

    //	BRPtouchPrinter Class initialize (Release will be done in [dealloc])
    ptp = [[BRPtouchPrinter alloc] initWithPrinterName:[settings objectForKey:@"name"] interface:CONNECTION_TYPE_WLAN];
    [ptp setPrintInfo:printInfo];
    [ptp setIPAddress:[settings objectForKey:@"ipAddress"]];

    CDVPluginResult* pluginResult;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:invokedCommand.callbackId];
}

- (BOOL) print:(CDVInvokedUrlCommand*) invokedCommand {
    if (ptp == nil) {
        NSLog(@"Printer not set");
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                 messageAsString:@"Printer not set"]
                                callbackId:invokedCommand.callbackId];
        return NO;
    }
    NSArray*  arguments = [invokedCommand arguments];
    NSMutableDictionary* settings = [arguments objectAtIndex:1];

    [self.commandDelegate runInBackground:^{
        [self _print:settings command:invokedCommand];
    }];
    return YES;
}

- (void) searchPrinters
{
    ptn = [[BRPtouchNetworkManager alloc] init];
    ptn.delegate = self;

    [ptn setPrinterNames:[NSArray arrayWithObjects:@"Brother QL-710W", @"Brother QL-720NW", @"Brother QL-810W", @"Brother QL-820NWB", @"Brother QL-1110NWB", @"Brother QL-1115NWB", nil]];
    [ptn startSearch: 5.0];
}

- (BOOL) _print: (NSMutableDictionary*) settings
        command: (CDVInvokedUrlCommand*) invokedCommand
{
    NSString* text = [settings objectForKey:@"text"];
    NSInteger width = [[settings objectForKey:@"width"] integerValue];
    NSInteger height = [[settings objectForKey:@"height"] integerValue];
    NSInteger maxFontSize = [[settings objectForKey:@"font"] integerValue];
    CGRect rect = CGRectMake(0, 0, width, height);

    UIGraphicsBeginImageContext(rect.size);
    [[UIColor blackColor] set];

    int fontSize = 0;

    CGSize calcsize = CGSizeMake(0, 0);

    while( calcsize.width <= rect.size.width && calcsize.height <= rect.size.height && fontSize < maxFontSize ) {
        fontSize++;
        calcsize = [text sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:(fontSize + 1) weight:UIFontWeightHeavy]}];
    }

    NSLog(@"Final font size is %d", fontSize);

    float y_pos = (rect.size.height - calcsize.height)/2;
    CGRect textRect = CGRectMake(0, y_pos, rect.size.width, calcsize.height);

    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByClipping;
    paragraphStyle.alignment = NSTextAlignmentCenter;
    [text drawInRect:textRect withAttributes: @{ NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightHeavy],
                                                 NSParagraphStyleAttributeName: paragraphStyle }];

    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGImageRef imgRef = [newImage CGImage];

//    NSData *imageData = UIImagePNGRepresentation(newImage);
//    NSLog(@"%@", [imageData base64Encoding]);
//    return NO;

    // Do print
    NSString* resultStr;
    BOOL error = NO;

    if ([ptp isPrinterReady] && !communicationStarted) {
        NSLog(@"Ready");
        communicationStarted = [ptp startCommunication];
        if (communicationStarted) {
            NSLog(@"Cumunication started %d", communicationStarted);
            int result = [ptp printImage:imgRef copy:1];

            if (result < 0) {
                resultStr = [NSString stringWithFormat:@"Result: %d", result];
                error = YES;
            }
            else {
                NSLog(@"Print successful");
            }
        }
        else {
            NSLog(@"Communication not started");
            resultStr = @"error_notready";
            error = YES;
        }
        [ptp endCommunication];
        communicationStarted = FALSE;
        NSLog(@"Communication ended");
    }
    else {
        NSLog(@"Not ready");
        resultStr = @"error_notready";
        error = YES;
    }

    CDVPluginResult* pluginResult;
    if (!error) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:resultStr];
    }

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:invokedCommand.callbackId];
    return YES;
}

-(void)didFinishSearch:(id)sender
{
    NSMutableArray* aryListData = (NSMutableArray*)[ptn getPrinterNetInfo];
    NSMutableArray *printers =[NSMutableArray array];

    for (BRPtouchDeviceInfo* bpni in aryListData) {
        NSMutableDictionary* printerDict = [NSMutableDictionary dictionaryWithCapacity:2];
        [printerDict setObject:bpni.strModelName forKey:@"name"];
        [printerDict setObject:bpni.strIPAddress forKey:@"ipAddress"];
        [printers addObject:printerDict];
    }

    CDVPluginResult* pluginResult;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                      messageAsArray:printers];

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:actCommand.callbackId];
}

@end
