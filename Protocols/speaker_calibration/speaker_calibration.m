function speaker_calibration
%Speaker calibration for Bpod system
%Tom Sikkens 4/2/15

global BpodSystem
%% Setup system parameter
S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S
if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings
    S.GUI.SoundFreq = [3000, 8000, 20000]; % Frequencies to be calibrated (Hz)
    S.GUI.nFreq = length(S.GUI.SoundFreq);
    S.SoundDuration = 0.8; % s
    S.TimeToRecord = 0.500;
    S.BandLimitRatios = [ 1/sqrt(2) sqrt(2)];
end

BpodParameterGUI('init', S);

% --- Setup NI-card ---
initdaq % Create object AnalogInputObj
global AnalogInputObj

% --- Set the acquisition card ---
set(AnalogInputObj,'SamplesPerTrigger',S.TimeToRecord*round(AnalogInputObj.samplerate));


% --- Define Attenuation Vector ---
AttenuationVector = zeros(1,3);

% --- Set Output filename 
Outputfn = 'C:\Users\Tom\Documents\MATLAB\Bpod_0_5\Calibration Files\SoundCalibration.mat';

% --- Set Target Intensity
TargetSPL = 50; % dB

%% Define stimuli and send to sound server
SF = 192000; % Sound card sampling rate
Sound = GenerateSineWave(SF, S.GUI.SoundFreq(1), S.SoundDuration1); % Sampling freq (hz), Sine frequency (hz), duration (s)

% Program sound server
PsychToolboxSoundServer('init')
PsychToolboxSoundServer('Load', 1, Sound);

% Set soft code handler to trigger sounds
BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_SoundCalibration';

%% Main trial loop

for iFreq=1:Nfreq            % -- Loop through frequencies --
    Sound = GenerateSineWave(SF, S.GUI.SoundFreq(iFreq), S.SoundDuration); % Sampling freq (hz), Sine frequency (hz), duration (s)
    BandLimits = S.GUI.SoundFreq(iFreq) * BandLimitRatios;
    FAILURE=true;
    while FAILURE
        try
            AttenuationVector(iFreq) = GetAmplitude(Sound,TargetSPL,...
            BandLimits);
            FAILURE=false;
        catch
            FAILURE=true;
            fprintf('***** There was an error. This step will be repeated. *****');
        end
    end
    fprintf('\n');
end    

SoundCalibration = [];
SoundCalibration.attenuation = AttenuationVector;
SoundCalibration.frequencies = S.SoundFreq;
save(Outputfn,SoundCalibration)

end

function Amplitude = GetAmplitude(S,Sound,TargetSPL,BandLimits)

    

    InitialAmplitude = 0.01;
    AcceptableDifference_dBSPL = 0.5;
    MaxIterations = 8;
    SPLref = 20e-6;

    S.Amplitude = InitialAmplitude;

    for iTry = 1:MaxIterations
        Sound = Amplitude.*Sound;
        PowerAtThisFrequency = SoundResponse(S,Sound,BandLimits);
        PowerAtThisFrequency_dBSPL = 10*log10(PowerAtThisFrequency/SPLref^2);
        fprintf('Attentuation = %0.4f  ->  Power = %0.2f dB-SPL\n',Amplitude,PowerAtThisFrequency_dBSPL);
        PowerDifference_dBSPL = PowerAtThisFrequency_dBSPL - TargetSPL;

            if(abs(PowerDifference_dBSPL)<AcceptableDifference_dBSPL)
                break;
            elseif(iTry<MaxIterations)
                AmpFactor = sqrt(10^(PowerDifference_dBSPL/10));
                Amplitude = Amplitude/AmpFactor;
                % If it cannot find the right level, set to 0.1
                if(SoundParam.Amplitude>1)
                    Amplitude = 1;
                end
            end
    end
end

function Power = SoundResponse(S,Sound,BandLimits)

global AnalogInputObj

PsychToolboxSoundServer('Load', 1, Sound);
OutputSound = {'SoftCode', 1};
OutputRecord = {'SoftCode', 2};
FsIn = AnalogInputObj.samplerate; % NI-card sampling rate

% ---Assemble state matrix---
sma = NewStateMatrix(); 
sma = AddState(sma, 'Name', 'DeliverSound', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup','Pause'},...
        'OutputActions', OutputSound);
sma = AddState(sma, 'Name', 'Pause', ...
        'Timer', 0.1,...
        'StateChangeConditions', {'Tup','StartRecord'},...
        'OutputActions', {});
sma = AddState(sma, 'Name', 'StartRecord', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup','Record'},...
        'OutputActions', OutputRecord);
sma = AddState(sma, 'Name', 'Record', ...
        'Timer', S.TimeToRecord+0.1,...
        'StateChangeConditions', {'Tup','exit'},...
        'OutputActions', {});
SendStateMatrix(sma);

[RawSignal.Data,RawSignal.TimeVec]=getdata(AnalogInputObj,AnalogInputObj.SamplesAvailable);

% --- Calculate power ---
ThisPSD = pwelch(RawSignal.Data,'Fs',FsIn);
Power = band_power(ThisPSD.Data,ThisPSD.Frequencies,BandLimits);

end