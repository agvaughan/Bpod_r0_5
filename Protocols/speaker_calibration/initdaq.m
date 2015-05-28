%  Initialize NI DAQ card
%
% Santiago Jaramillo - 2007.11.10
% Based on CalibrationSpeakers/CalibrateForTuningCurve.m

fprintf('Initializing Nidaq...');

% Input channel for recording
hwinfo = daqhwinfo('nidaq');
AnalogInputObj = analoginput('nidaq',hwinfo.InstalledBoardIds{1});
set(AnalogInputObj,'InputType','SingleEnded');
inchan = addchannel(AnalogInputObj,0);

% Set some general parameters.
% Target sample rate is card's maximum.
cardinfo=daqhwinfo( AnalogInputObj );
set(AnalogInputObj,'SampleRate', cardinfo.MaxSampleRate );
AnalogInputObj.Channel.InputRange=[-10 10];
AnalogInputObj.Channel.SensorRange=[-10 10];
AnalogInputObj.Channel.UnitsRange=[-10 10];

set(AnalogInputObj,'LoggingMode','Memory');
set(AnalogInputObj,'SamplesPerTrigger',inf);

set(AnalogInputObj,'TriggerType','Immediate');   % trigger without using dio lines

fprintf('  Done!\n\n');

%AnalogInputObj

%fprintf('To start one trigger, run: start(AnalogInputObj);\n');
%fprintf('To stop, run: stop(AnalogInputObj);\n');

return


% -- Use card timer --
wait( AnalogInputObj, 2);
% --- Get data ---
[MicData,TimeVec]=getdata( AnalogInputObj,AnalogInputObj.SamplesAvailable);
