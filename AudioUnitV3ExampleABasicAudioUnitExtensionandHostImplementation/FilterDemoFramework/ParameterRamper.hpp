/*
	<samplecode>
		<abstract>
			Utility class to manage DSP parameters which can change value smoothly (be ramped) while rendering, without introducing clicks or other distortion into the signal.
		</abstract>
	</samplecode>
*/

#ifndef ParameterRamper_h
#define ParameterRamper_h

// N.B. This is C++.

#import <AudioToolbox/AudioToolbox.h>

class ParameterRamper {
	float clampLow, clampHigh;
    float _goal;
    float inverseSlope;
    AUAudioFrameCount samplesRemaining;

public:
	ParameterRamper(float value) {
		set(value);
	}

    void set(float value) {
        _goal = value;
        inverseSlope = 0.0;
        samplesRemaining = 0;
    }

    void startRamp(float newGoal, AUAudioFrameCount duration) {
        if (duration == 0) {
            set(newGoal);
        }
        else {
            /*
            	Set a new ramp.
            	Assigning to inverseSlope must come before assigning to goal.
            */
            inverseSlope = (get() - newGoal) / float(duration);
            samplesRemaining = duration;
            _goal = newGoal;
        }
    }

    float get() const {
        /*
			For long ramps, integrating a sum loses precision and does not reach 
            the goal at the right time. So instead, a line equation is used. y = m * x + b.
		*/
        return inverseSlope * float(samplesRemaining) + _goal;
    }
	
	float goal() const { return _goal; }
	
    void step() {
        // Do this in each inner loop iteration after getting the value.
        if (samplesRemaining != 0) {
			--samplesRemaining;
		}
    }

    float getStep() {
        // Combines get and step. Saves a multiply-add when not ramping.
        if (samplesRemaining != 0) {
            float value = get();
            --samplesRemaining;
            return value;
        }
		else {
            return _goal;
        }
    }

    void stepBy(AUAudioFrameCount n) {
        /*
            When a parameter does not participate in the current inner loop, you 
            will want to advance it after the end of the loop.
        */
        if (n >= samplesRemaining) {
			samplesRemaining = 0;
        }
		else {
			samplesRemaining -= n;
		}
    }
};

#endif /* ParameterRamper_h */
