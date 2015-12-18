/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	An AUAudioUnit subclass implementing a low-pass filter with resonance. Illustrates parameter management and rendering, including in-place processing and buffer management.
*/

#import "FilterDemo.h"
#import <AVFoundation/AVFoundation.h>
#import "FilterDSPKernel.hpp"
#import "BufferedAudioBus.hpp"

@interface AUv3FilterDemo ()

@property AUAudioUnitBus *outputBus;
@property AUAudioUnitBusArray *inputBusArray;
@property AUAudioUnitBusArray *outputBusArray;

@property (nonatomic, readwrite) AUParameterTree *parameterTree;

@end


@implementation AUv3FilterDemo {
	// C++ members need to be ivars; they would be copied on access if they were properties.
    FilterDSPKernel _kernel;

    BufferedInputBus _inputBus;
}
@synthesize parameterTree = _parameterTree;

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription options:(AudioComponentInstantiationOptions)options error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];

    if (self == nil) {
    	return nil;
    }
	
	// Initialize a default format for the busses.
    AVAudioFormat *defaultFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100. channels:2];

	// Create a DSP kernel to handle the signal processing.
	_kernel.init(defaultFormat.channelCount, defaultFormat.sampleRate);
	
	// Create a parameter object for the cutoff frequency.
	AUParameter *cutoffParam = [AUParameterTree createParameterWithIdentifier:@"cutoff" name:@"Cutoff"
			address:FilterParamCutoff
			min:12.0 max:20000.0 unit:kAudioUnitParameterUnit_Hertz unitName:nil
			flags: 0 valueStrings:nil dependentParameters:nil];
	
	// Create a parameter object for the filter resonance.
	AUParameter *resonanceParam = [AUParameterTree createParameterWithIdentifier:@"resonance" name:@"Resonance"
			address:FilterParamResonance
			min:-20.0 max:20.0 unit:kAudioUnitParameterUnit_Decibels unitName:nil
			flags: 0 valueStrings:nil dependentParameters:nil];
	
	// Initialize the parameter values.
	cutoffParam.value = 400.0;
	resonanceParam.value = -5.0;
	_kernel.setParameter(FilterParamCutoff, cutoffParam.value);
	_kernel.setParameter(FilterParamResonance, resonanceParam.value);
	
	// Create the parameter tree.
    _parameterTree = [AUParameterTree createTreeWithChildren:@[
		cutoffParam,
		resonanceParam
	]];

	// Create the input and output busses.
	_inputBus.init(defaultFormat, 8);
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormat error:nil];

	// Create the input and output bus arrays.
	_inputBusArray  = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeInput  busses: @[_inputBus.bus]];
	_outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeOutput busses: @[_outputBus]];

	// Make a local pointer to the kernel to avoid capturing self.
	__block FilterDSPKernel *filterKernel = &_kernel;

	// implementorValueObserver is called when a parameter changes value.
	_parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
		filterKernel->setParameter(param.address, value);
	};
	
	// implementorValueProvider is called when the value needs to be refreshed.
	_parameterTree.implementorValueProvider = ^(AUParameter *param) {
		return filterKernel->getParameter(param.address);
	};
	
	// A function to provide string representations of parameter values.
	_parameterTree.implementorStringFromValueCallback = ^(AUParameter *param, const AUValue *__nullable valuePtr) {
		AUValue value = valuePtr == nil ? param.value : *valuePtr;
	
		switch (param.address) {
			case FilterParamCutoff:
				return [NSString stringWithFormat:@"%.f", value];
			
			case FilterParamResonance:
				return [NSString stringWithFormat:@"%.2f", value];
			
			default:
				return @"?";
		}
	};

	self.maximumFramesToRender = 512;
	
	return self;
}

#pragma mark - AUAudioUnit Overrides

- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}

- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
	if (![super allocateRenderResourcesAndReturnError:outError]) {
		return NO;
	}
	
    if (self.outputBus.format.channelCount != _inputBus.bus.format.channelCount) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_FailedInitialization userInfo:nil];
        }
        // Notify superclass that initialization was not successful
        self.renderResourcesAllocated = NO;
        
        return NO;
    }
	
	_inputBus.allocateRenderResources(self.maximumFramesToRender);
	
	_kernel.init(self.outputBus.format.channelCount, self.outputBus.format.sampleRate);
	_kernel.reset();
	
	/*	
		While rendering, we want to schedule all parameter changes. Setting them 
        off the render thread is not thread safe.
	*/
	__block AUScheduleParameterBlock scheduleParameter = self.scheduleParameterBlock;
	
	// Ramp over 20 milliseconds.
	__block AUAudioFrameCount rampTime = AUAudioFrameCount(0.02 * self.outputBus.format.sampleRate);
	
	self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
		scheduleParameter(AUEventSampleTimeImmediate, rampTime, param.address, value);
	};
	
	return YES;
}
	
- (void)deallocateRenderResources {
	[super deallocateRenderResources];
	
	_inputBus.deallocateRenderResources();
	
	// Make a local pointer to the kernel to avoid capturing self.
	__block FilterDSPKernel *filterKernel = &_kernel;

	// Go back to setting parameters instead of scheduling them.
	self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
		filterKernel->setParameter(param.address, value);
	};
}
	
- (AUInternalRenderBlock)internalRenderBlock {
	/*
		Capture in locals to avoid ObjC member lookups. If "self" is captured in
        render, we're doing it wrong.
	*/
	__block FilterDSPKernel *state = &_kernel;
	__block BufferedInputBus *input = &_inputBus;
    
    return ^AUAudioUnitStatus(
			 AudioUnitRenderActionFlags *actionFlags,
			 const AudioTimeStamp       *timestamp,
			 AVAudioFrameCount           frameCount,
			 NSInteger                   outputBusNumber,
			 AudioBufferList            *outputData,
			 const AURenderEvent        *realtimeEventListHead,
			 AURenderPullInputBlock      pullInputBlock) {
		AudioUnitRenderActionFlags pullFlags = 0;

		AUAudioUnitStatus err = input->pullInput(&pullFlags, timestamp, frameCount, 0, pullInputBlock);
		
        if (err != 0) {
			return err;
		}
		
		AudioBufferList *inAudioBufferList = input->mutableAudioBufferList;
		
		/* 
			If the caller passed non-nil output pointers, use those. Otherwise,     
            process in-place in the input buffer. If your algorithm cannot process 
            in-place, then you will need to preallocate an output buffer and use 
            it here.
		*/
		AudioBufferList *outAudioBufferList = outputData;
		if (outAudioBufferList->mBuffers[0].mData == nullptr) {
			for (UInt32 i = 0; i < outAudioBufferList->mNumberBuffers; ++i) {
				outAudioBufferList->mBuffers[i].mData = inAudioBufferList->mBuffers[i].mData;
			}
		}
		
		state->setBuffers(inAudioBufferList, outAudioBufferList);
		state->processWithEvents(timestamp, frameCount, realtimeEventListHead);

		return noErr;
	};
}

- (NSArray<NSNumber *> *)magnitudesForFrequencies:(NSArray<NSNumber *> *)frequencies {
	FilterDSPKernel::BiquadCoefficients coefficients;

    double inverseNyquist = 2.0 / self.outputBus.format.sampleRate;
	
    coefficients.calculateLopassParams(_kernel.cutoffRamper.goal(), _kernel.resonanceRamper.goal());
	
    NSMutableArray<NSNumber *> *magnitudes = [NSMutableArray arrayWithCapacity:frequencies.count];
	
    for (NSNumber *number in frequencies) {
		double frequency = [number doubleValue];
		double magnitude = coefficients.magnitudeForFrequency(frequency * inverseNyquist);

        [magnitudes addObject:@(magnitude)];
	}
	
    return [NSArray arrayWithArray:magnitudes];
}

@end


