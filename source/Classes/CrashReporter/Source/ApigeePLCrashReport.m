/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2008-2010 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "ApigeePLCrashReport.h"
#import "ApigeeCrashReporter.h"

#import "../Generated/iOS/crash_report.pb-c.h"

struct Apigee__PLCrashReportDecoder {
    Apigee_Plcrash__CrashReport *crashReport;
};

#define IMAGE_UUID_DIGEST_LEN 16

@interface Apigee_PLCrashReport (PrivateMethods)

- (Apigee_Plcrash__CrashReport *) decodeCrashData: (NSData *) data error: (NSError **) outError;
- (Apigee_PLCrashReportSystemInfo *) extractSystemInfo: (Apigee_Plcrash__CrashReport__SystemInfo *) systemInfo error: (NSError **) outError;
- (Apigee_PLCrashReportProcessorInfo *) extractProcessorInfo: (Apigee_Plcrash__CrashReport__Processor *) processorInfo error: (NSError **) outError;
- (Apigee_PLCrashReportMachineInfo *) extractMachineInfo: (Apigee_Plcrash__CrashReport__MachineInfo *) machineInfo error: (NSError **) outError;
- (Apigee_PLCrashReportApplicationInfo *) extractApplicationInfo: (Apigee_Plcrash__CrashReport__ApplicationInfo *) applicationInfo error: (NSError **) outError;
- (Apigee_PLCrashReportProcessInfo *) extractProcessInfo: (Apigee_Plcrash__CrashReport__ProcessInfo *) processInfo error: (NSError **) outError;
- (NSArray *) extractThreadInfo: (Apigee_Plcrash__CrashReport *) crashReport error: (NSError **) outError;
- (NSArray *) extractImageInfo: (Apigee_Plcrash__CrashReport *) crashReport error: (NSError **) outError;
- (Apigee_PLCrashReportExceptionInfo *) extractExceptionInfo: (Apigee_Plcrash__CrashReport__Exception *) exceptionInfo error: (NSError **) outError;
- (Apigee_PLCrashReportSignalInfo *) extractSignalInfo: (Apigee_Plcrash__CrashReport__Signal *) signalInfo error: (NSError **) outError;

@end


static void populate_nserror (NSError **error, Apigee_PLCrashReporterError code, NSString *description);

/**
 * Provides decoding of crash logs generated by the PLCrashReporter framework.
 *
 * @warning This API should be considered in-development and subject to change.
 */
@implementation Apigee_PLCrashReport

/**
 * Initialize with the provided crash log data. On error, nil will be returned, and
 * an NSError instance will be provided via @a error, if non-NULL.
 *
 * @param encodedData Encoded plcrash crash log.
 * @param outError If an error occurs, this pointer will contain an NSError object
 * indicating why the crash log could not be parsed. If no error occurs, this parameter
 * will be left unmodified. You may specify NULL for this parameter, and no error information
 * will be provided.
 *
 * @par Designated Initializer
 * This method is the designated initializer for the PLCrashReport class.
 */
- (id) initWithData: (NSData *) encodedData error: (NSError **) outError {
    if ((self = [super init]) == nil) {
        // This shouldn't happen, but we have to fufill our API contract
        populate_nserror(outError, Apigee_PLCrashReporterErrorUnknown, @"Could not initialize superclass");
        return nil;
    }


    /* Allocate the struct and attempt to parse */
    _decoder = malloc(sizeof(Apigee__PLCrashReportDecoder));
    _decoder->crashReport = [self decodeCrashData: encodedData error: outError];

    /* Check if decoding failed. If so, outError has already been populated. */
    if (_decoder->crashReport == NULL) {
        goto error;
    }


    /* System info */
    _systemInfo = [[self extractSystemInfo: _decoder->crashReport->system_info error: outError] retain];
    if (!_systemInfo)
        goto error;
    
    /* Machine info */
    if (_decoder->crashReport->machine_info != NULL) {
        _machineInfo = [[self extractMachineInfo: _decoder->crashReport->machine_info error: outError] retain];
        if (!_machineInfo)
            goto error;
    }

    /* Application info */
    _applicationInfo = [[self extractApplicationInfo: _decoder->crashReport->application_info error: outError] retain];
    if (!_applicationInfo)
        goto error;
    
    /* Process info. Handle missing info gracefully -- it is only included in v1.1+ crash reports. */
    if (_decoder->crashReport->process_info != NULL) {
        _processInfo = [[self extractProcessInfo: _decoder->crashReport->process_info error:outError] retain];
        if (!_processInfo)
            goto error;
    }

    /* Signal info */
    _signalInfo = [[self extractSignalInfo: _decoder->crashReport->signal error: outError] retain];
    if (!_signalInfo)
        goto error;

    /* Thread info */
    _threads = [[self extractThreadInfo: _decoder->crashReport error: outError] retain];
    if (!_threads)
        goto error;

    /* Image info */
    _images = [[self extractImageInfo: _decoder->crashReport error: outError] retain];
    if (!_images)
        goto error;

    /* Exception info, if it is available */
    if (_decoder->crashReport->exception != NULL) {
        _exceptionInfo = [[self extractExceptionInfo: _decoder->crashReport->exception error: outError] retain];
        if (!_exceptionInfo)
            goto error;
    }

    return self;

error:
    [self release];
    return nil;
}

- (void) dealloc {
    /* Free the data objects */
    [_systemInfo release];
    [_applicationInfo release];
    [_processInfo release];
    [_signalInfo release];
    [_threads release];
    [_images release];
    [_exceptionInfo release];

    /* Free the decoder state */
    if (_decoder != NULL) {
        if (_decoder->crashReport != NULL) {
            Apigee_protobuf_c_message_free_unpacked((Apigee_ProtobufCMessage *) _decoder->crashReport, &Apigee_protobuf_c_system_allocator);
        }

        free(_decoder);
        _decoder = NULL;
    }

    [super dealloc];
}

/**
 * Return the binary image containing the given address, or nil if no binary image
 * is found.
 *
 * @param address The address to search for.
 */
- (Apigee_PLCrashReportBinaryImageInfo *) imageForAddress: (uint64_t) address {
    for (Apigee_PLCrashReportBinaryImageInfo *imageInfo in self.images) {
        if (imageInfo.imageBaseAddress <= address && address < (imageInfo.imageBaseAddress + imageInfo.imageSize))
            return imageInfo;
    }

    /* Not found */
    return nil;
}

// property getter. Returns YES if machine information is available.
- (BOOL) hasMachineInfo {
    if (_machineInfo != nil)
        return YES;
    return NO;
}

// property getter. Returns YES if process information is available.
- (BOOL) hasProcessInfo {
    if (_processInfo != nil)
        return YES;
    return NO;
}

// property getter. Returns YES if exception information is available.
- (BOOL) hasExceptionInfo {
    if (_exceptionInfo != nil)
        return YES;
    return NO;
}

@synthesize systemInfo = _systemInfo;
@synthesize machineInfo = _machineInfo;
@synthesize applicationInfo = _applicationInfo;
@synthesize processInfo = _processInfo;
@synthesize signalInfo = _signalInfo;
@synthesize threads = _threads;
@synthesize images = _images;
@synthesize exceptionInfo = _exceptionInfo;

@end


/**
 * @internal
 * Private Methods
 */
@implementation Apigee_PLCrashReport (PrivateMethods)

/**
 * Decode the crash log message.
 *
 * @warning MEMORY WARNING. The caller is responsible for deallocating th ePlcrash__CrashReport instance
 * returned by this method via protobuf_c_message_free_unpacked().
 */
- (Apigee_Plcrash__CrashReport *) decodeCrashData: (NSData *) data error: (NSError **) outError {
    const struct Apigee_PLCrashReportFileHeader *header;
    const void *bytes;

    bytes = [data bytes];
    header = bytes;

    /* Verify that the crash log is sufficently large */
    if (sizeof(struct Apigee_PLCrashReportFileHeader) >= [data length]) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, NSLocalizedString(@"Could not decode truncated crash log",
                                                                                             @"Crash log decoding error message"));
        return NULL;
    }

    /* Check the file magic */
    if (memcmp(header->magic, Apigee_PLCRASH_REPORT_FILE_MAGIC, strlen(Apigee_PLCRASH_REPORT_FILE_MAGIC)) != 0) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid,NSLocalizedString(@"Could not decode invalid crash log header",
                                                                                            @"Crash log decoding error message"));
        return NULL;
    }

    /* Check the version */
    if(header->version != Apigee_PLCRASH_REPORT_FILE_VERSION) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, [NSString stringWithFormat: NSLocalizedString(@"Could not decode unsupported crash report version: %d", 
                                                                                                                         @"Crash log decoding message"), header->version]);
        return NULL;
    }

    Apigee_Plcrash__CrashReport *crashReport = Apigee_plcrash__crash_report__unpack(&Apigee_protobuf_c_system_allocator, [data length] - sizeof(struct Apigee_PLCrashReportFileHeader), header->data);
    if (crashReport == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, NSLocalizedString(@"An unknown error occured decoding the crash report", 
                                                                                             @"Crash log decoding error message"));
        return NULL;
    }

    return crashReport;
}


/**
 * Extract system information from the crash log. Returns nil on error.
 */
- (Apigee_PLCrashReportSystemInfo *) extractSystemInfo: (Apigee_Plcrash__CrashReport__SystemInfo *) systemInfo error: (NSError **) outError {
    NSDate *timestamp = nil;
    NSString *osBuild = nil;
    
    /* Validate */
    if (systemInfo == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing System Information section", 
                                           @"Missing sysinfo in crash report"));
        return nil;
    }
    
    if (systemInfo->os_version == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing System Information OS version field", 
                                           @"Missing sysinfo operating system in crash report"));
        return nil;
    }

    /* Set up the build, if available */
    if (systemInfo->os_build != NULL)
        osBuild = [NSString stringWithUTF8String: systemInfo->os_build];
    
    /* Set up the timestamp, if available */
    if (systemInfo->timestamp != 0)
        timestamp = [NSDate dateWithTimeIntervalSince1970: systemInfo->timestamp];
    
    /* Done */
    return [[[Apigee_PLCrashReportSystemInfo alloc] initWithOperatingSystem: (Apigee_PLCrashReportOperatingSystem) systemInfo->operating_system
                                              operatingSystemVersion: [NSString stringWithUTF8String: systemInfo->os_version]
                                                operatingSystemBuild: osBuild
                                                        architecture: (Apigee_PLCrashReportArchitecture) systemInfo->architecture
                                                           timestamp: timestamp] autorelease];
}

/**
 * Extract processor information from the crash log. Returns nil on error.
 */
- (Apigee_PLCrashReportProcessorInfo *) extractProcessorInfo: (Apigee_Plcrash__CrashReport__Processor *) processorInfo error: (NSError **) outError {
    /* Validate */
    if (processorInfo == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing processor info section", 
                                           @"Missing processor info in crash report"));
        return nil;
    }

    return [[[Apigee_PLCrashReportProcessorInfo alloc] initWithTypeEncoding: (Apigee_PLCrashReportProcessorTypeEncoding) processorInfo->encoding
                                                                type: processorInfo->type
                                                             subtype: processorInfo->subtype] autorelease];
}

/**
 * Extract machine information from the crash log. Returns nil on error.
 */
- (Apigee_PLCrashReportMachineInfo *) extractMachineInfo: (Apigee_Plcrash__CrashReport__MachineInfo *) machineInfo error: (NSError **) outError {
    NSString *model = nil;
    Apigee_PLCrashReportProcessorInfo *processorInfo;

    /* Validate */
    if (machineInfo == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing Machine Information section", 
                                           @"Missing machine_info in crash report"));
        return nil;
    }

    /* Set up the model, if available */
    if (machineInfo->model != NULL)
        model = [NSString stringWithUTF8String: machineInfo->model];

    /* Set up the processor info. */
    processorInfo = [self extractProcessorInfo: machineInfo->processor error: outError];
    if (processorInfo == nil)
        return nil;

    /* Done */
    return [[[Apigee_PLCrashReportMachineInfo alloc] initWithModelName: model
                                                  processorInfo: processorInfo
                                                 processorCount: machineInfo->processor_count
                                          logicalProcessorCount: machineInfo->logical_processor_count] autorelease];
}

/**
 * Extract application information from the crash log. Returns nil on error.
 */
- (Apigee_PLCrashReportApplicationInfo *) extractApplicationInfo: (Apigee_Plcrash__CrashReport__ApplicationInfo *) applicationInfo
                                                    error: (NSError **) outError
{    
    /* Validate */
    if (applicationInfo == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing Application Information section", 
                                           @"Missing app info in crash report"));
        return nil;
    }

    /* Identifier available? */
    if (applicationInfo->identifier == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing Application Information app identifier field", 
                                           @"Missing app identifier in crash report"));
        return nil;
    }

    /* Version available? */
    if (applicationInfo->version == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing Application Information app version field", 
                                           @"Missing app version in crash report"));
        return nil;
    }
    
    /* Done */
    NSString *identifier = [NSString stringWithUTF8String: applicationInfo->identifier];
    NSString *version = [NSString stringWithUTF8String: applicationInfo->version];

    return [[[Apigee_PLCrashReportApplicationInfo alloc] initWithApplicationIdentifier: identifier
                                                          applicationVersion: version] autorelease];
}


/**
 * Extract process information from the crash log. Returns nil on error.
 */
- (Apigee_PLCrashReportProcessInfo *) extractProcessInfo: (Apigee_Plcrash__CrashReport__ProcessInfo *) processInfo
                                            error: (NSError **) outError
{    
    /* Validate */
    if (processInfo == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing Process Information section", 
                                           @"Missing process info in crash report"));
        return nil;
    }
    
    /* Name available? */
    NSString *processName = nil;
    if (processInfo->process_name != NULL)
        processName = [NSString stringWithUTF8String: processInfo->process_name];
    
    /* Path available? */
    NSString *processPath = nil;
    if (processInfo->process_path != NULL)
        processPath = [NSString stringWithUTF8String: processInfo->process_path];
    
    /* Parent Name available? */
    NSString *parentProcessName = nil;
    if (processInfo->parent_process_name != NULL)
        parentProcessName = [NSString stringWithUTF8String: processInfo->parent_process_name];

    /* Required elements */
    NSUInteger processID = processInfo->process_id;
    NSUInteger parentProcessID = processInfo->parent_process_id;

    /* Done */
    return [[[Apigee_PLCrashReportProcessInfo alloc] initWithProcessName: processName
                                                        processID: processID
                                                      processPath: processPath
                                                parentProcessName: parentProcessName
                                                  parentProcessID: parentProcessID
                                                           native: processInfo->native] autorelease];
}

/**
 * Extract stack frame information from the crash log. Returns nil on error, or a PLCrashReportStackFrameInfo
 * instance on success.
 */
- (Apigee_PLCrashReportStackFrameInfo *) extractStackFrameInfo: (Apigee_Plcrash__CrashReport__Thread__StackFrame *) stackFrame error: (NSError **) outError {
    /* There should be at least one thread */
    if (stackFrame == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid,
                         NSLocalizedString(@"Crash report is missing stack frame information",
                                           @"Missing stack frame info in crash report"));
        return nil;
    }
    
    return [[[Apigee_PLCrashReportStackFrameInfo alloc] initWithInstructionPointer: stackFrame->pc] autorelease];
}

/**
 * Extract thread information from the crash log. Returns nil on error, or an array of PLCrashLogThreadInfo
 * instances on success.
 */
- (NSArray *) extractThreadInfo: (Apigee_Plcrash__CrashReport *) crashReport error: (NSError **) outError {
    /* There should be at least one thread */
    if (crashReport->n_threads == 0) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid,
                         NSLocalizedString(@"Crash report is missing thread state information",
                                           @"Missing thread info in crash report"));
        return nil;
    }

    /* Handle all threads */
    NSMutableArray *threadResult = [NSMutableArray arrayWithCapacity: crashReport->n_threads];
    for (size_t thr_idx = 0; thr_idx < crashReport->n_threads; thr_idx++) {
        Apigee_Plcrash__CrashReport__Thread *thread = crashReport->threads[thr_idx];
        
        /* Fetch stack frames for this thread */
        NSMutableArray *frames = [NSMutableArray arrayWithCapacity: thread->n_frames];
        for (size_t frame_idx = 0; frame_idx < thread->n_frames; frame_idx++) {
            Apigee_Plcrash__CrashReport__Thread__StackFrame *frame = thread->frames[frame_idx];
            Apigee_PLCrashReportStackFrameInfo *frameInfo = [self extractStackFrameInfo: frame error: outError];
            if (frameInfo == nil)
                return nil;

            [frames addObject: frameInfo];
        }

        /* Fetch registers for this thread */
        NSMutableArray *registers = [NSMutableArray arrayWithCapacity: thread->n_registers];
        for (size_t reg_idx = 0; reg_idx < thread->n_registers; reg_idx++) {
            Apigee_Plcrash__CrashReport__Thread__RegisterValue *reg = thread->registers[reg_idx];
            Apigee_PLCrashReportRegisterInfo *regInfo;

            /* Handle missing register name (should not occur!) */
            if (reg->name == NULL) {
                populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, @"Missing register name in register value");
                return nil;
            }

            regInfo = [[[Apigee_PLCrashReportRegisterInfo alloc] initWithRegisterName: [NSString stringWithUTF8String: reg->name]
                                                              registerValue: reg->value] autorelease];
            [registers addObject: regInfo];
        }

        /* Create the thread info instance */
        Apigee_PLCrashReportThreadInfo *threadInfo = [[[Apigee_PLCrashReportThreadInfo alloc] initWithThreadNumber: thread->thread_number
                                                                                   stackFrames: frames 
                                                                                       crashed: thread->crashed 
                                                                                     registers: registers] autorelease];
        [threadResult addObject: threadInfo];
    }
    
    return threadResult;
}


/**
 * Extract binary image information from the crash log. Returns nil on error.
 */
- (NSArray *) extractImageInfo: (Apigee_Plcrash__CrashReport *) crashReport error: (NSError **) outError {
    /* There should be at least one image */
    if (crashReport->n_binary_images == 0) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid,
                         NSLocalizedString(@"Crash report is missing binary image information",
                                           @"Missing image info in crash report"));
        return nil;
    }

    /* Handle all records */
    NSMutableArray *images = [NSMutableArray arrayWithCapacity: crashReport->n_binary_images];
    for (size_t i = 0; i < crashReport->n_binary_images; i++) {
        Apigee_Plcrash__CrashReport__BinaryImage *image = crashReport->binary_images[i];
        Apigee_PLCrashReportBinaryImageInfo *imageInfo;

        /* Validate */
        if (image->name == NULL) {
            populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, @"Missing image name in image record");
            return nil;
        }

        /* Extract UUID value */
        NSData *uuid = nil;
        if (image->uuid.len == 0) {
            /* No UUID */
            uuid = nil;
        } else {
            uuid = [NSData dataWithBytes: image->uuid.data length: image->uuid.len];
        }
        assert(image->uuid.len == 0 || uuid != nil);
        
        /* Extract code type (if available). */
        Apigee_PLCrashReportProcessorInfo *codeType = nil;
        if ((codeType = [self extractProcessorInfo: image->code_type error: outError]) == nil)
            return nil;


        imageInfo = [[[Apigee_PLCrashReportBinaryImageInfo alloc] initWithCodeType: codeType
                                                                baseAddress: image->base_address
                                                                       size: image->size
                                                                       name: [NSString stringWithUTF8String: image->name]
                                                                       uuid: uuid] autorelease];
        [images addObject: imageInfo];
    }

    return images;
}

/**
 * Extract  exception information from the crash log. Returns nil on error.
 */
- (Apigee_PLCrashReportExceptionInfo *) extractExceptionInfo: (Apigee_Plcrash__CrashReport__Exception *) exceptionInfo
                                               error: (NSError **) outError
{
    /* Validate */
    if (exceptionInfo == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing Exception Information section", 
                                           @"Missing appinfo in crash report"));
        return nil;
    }
    
    /* Name available? */
    if (exceptionInfo->name == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing exception name field", 
                                           @"Missing appinfo operating system in crash report"));
        return nil;
    }
    
    /* Reason available? */
    if (exceptionInfo->reason == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing exception reason field", 
                                           @"Missing appinfo operating system in crash report"));
        return nil;
    }
    
    /* Done */
    NSString *name = [NSString stringWithUTF8String: exceptionInfo->name];
    NSString *reason = [NSString stringWithUTF8String: exceptionInfo->reason];
    
    /* Fetch stack frames for this thread */
    NSMutableArray *frames = nil;
    if (exceptionInfo->n_frames > 0) {
        frames = [NSMutableArray arrayWithCapacity: exceptionInfo->n_frames];
        for (size_t frame_idx = 0; frame_idx < exceptionInfo->n_frames; frame_idx++) {
            Apigee_Plcrash__CrashReport__Thread__StackFrame *frame = exceptionInfo->frames[frame_idx];
            Apigee_PLCrashReportStackFrameInfo *frameInfo = [self extractStackFrameInfo: frame error: outError];
            if (frameInfo == nil)
                return nil;
            
            [frames addObject: frameInfo];
        }
    }

    if (frames == nil) {
        return [[[Apigee_PLCrashReportExceptionInfo alloc] initWithExceptionName: name reason: reason] autorelease];
    } else {
        return [[[Apigee_PLCrashReportExceptionInfo alloc] initWithExceptionName: name
                                                                   reason: reason 
                                                              stackFrames: frames] autorelease];
    }
}

/**
 * Extract signal information from the crash log. Returns nil on error.
 */
- (Apigee_PLCrashReportSignalInfo *) extractSignalInfo: (Apigee_Plcrash__CrashReport__Signal *) signalInfo
                                       error: (NSError **) outError
{
    /* Validate */
    if (signalInfo == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing Signal Information section", 
                                           @"Missing appinfo in crash report"));
        return nil;
    }
    
    /* Name available? */
    if (signalInfo->name == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing signal name field", 
                                           @"Missing appinfo operating system in crash report"));
        return nil;
    }
    
    /* Code available? */
    if (signalInfo->code == NULL) {
        populate_nserror(outError, Apigee_PLCrashReporterErrorCrashReportInvalid, 
                         NSLocalizedString(@"Crash report is missing signal code field", 
                                           @"Missing appinfo operating system in crash report"));
        return nil;
    }
    
    /* Done */
    NSString *name = [NSString stringWithUTF8String: signalInfo->name];
    NSString *code = [NSString stringWithUTF8String: signalInfo->code];
    
    return [[[Apigee_PLCrashReportSignalInfo alloc] initWithSignalName: name code: code address: signalInfo->address] autorelease];
}

@end

/**
 * @internal
 
 * Populate an NSError instance with the provided information.
 *
 * @param error Error instance to populate. If NULL, this method returns
 * and nothing is modified.
 * @param code The error code corresponding to this error.
 * @param description A localized error description.
 * @param cause The underlying cause, if any. May be nil.
 */
static void populate_nserror (NSError **error, Apigee_PLCrashReporterError code, NSString *description) {
    NSDictionary *userInfo;
    
    if (error == NULL)
        return;
    
    /* Create the userInfo dictionary */
    userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                description, NSLocalizedDescriptionKey,
                nil
                ];
    
    *error = [NSError errorWithDomain: Apigee_PLCrashReporterErrorDomain code: code userInfo: userInfo];
}
