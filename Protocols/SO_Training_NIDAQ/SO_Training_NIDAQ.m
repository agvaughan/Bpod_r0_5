%{
----------------------------------------------------------------------------

This file is part of the Bpod Project
Copyright (C) 2014 Joshua I. Sanders, Cold Spring Harbor Laboratory, NY, USA

----------------------------------------------------------------------------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3.

This program is distributed  WITHOUT ANY WARRANTY and without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
%}
function SO_Training_NIDAQ
% Cued outcome task
% Written by Tom Sikkens 5/2015.

global BpodSystem

%% Define parameters

S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S

if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings
    
    S.GUI.NumTrialTypes = 2;
    S.GUI.SinWaveFreq1 = 10000; %Hz
    S.GUI.SinWaveFreq2 = 4000;  %Hz
    S.GUI.use_punishment = 1;
    beep;
%     disp('Fitz just set use_punishment to zero for training and forgot to change it back');
    
    S.NoLick = 1.5; %s
    S.ITI = 1; %ITI duration is set to be exponentially distributed later
    S.SoundDuration = 1; %sd
    S.RewardValveCode = 2;
    S.RewardAmount = 5; %ul
    S.PunishValveCode = 4;
    S.PunishValveTime = 0.2; %s
    S.Delay = 0.5; %s
    S.RewardValveTime =  GetValveTimes(S.RewardAmount, S.RewardValveCode);
    S.DirectDelivery = 1; % 0 = 'no' 1 = 'yes'
    
      
    % For triggering laser on BNC 1
    S.PreTrialRecording  = 0; % After ITI
    S.PostTrialRecording = 3; % After trial before exit
    
    

end

% Initialize parameter GUI plugin
BpodParameterGUI('init', S);

%% Define trials

MaxTrials = 5000;
rng('shuffle')
TrialTypes = randi(S.GUI.NumTrialTypes,1,MaxTrials);
p = rand(1,MaxTrials);

%Training
if ~S.GUI.use_punishment
    UsOutcome = ones(size(TrialTypes));
    UsOutcome(p <= 0.55 & TrialTypes == 2) = 0;
    UsOutcome( p >= 0.9 & TrialTypes == 1) = 0;
elseif S.GUI.use_punishment
    % With 'punishment'
    % 1 - reward
    % 2 - punish
    % 0 - omission
    UsOutcome = zeros(size(TrialTypes));
    
    % Trial type 1 : 80% reward, 10% punish, 10% omission
    UsOutcome(p <= 0.8           & TrialTypes == 1) = 1;
    UsOutcome(p > 0.8 & p <= 0.9 & TrialTypes == 1) = 2;
    
    % Trial type 2 : 65% punish, 15% reward, 10% omission
    UsOutcome(p <= 0.65           & TrialTypes == 2) = 2;
    UsOutcome(p > 0.65 & p <= 0.9 & TrialTypes == 2) = 1;
end
BpodSystem.Data.TrialTypes = []; % The trial type of each trial completed will be added here.

%% Initialize plots
scrsz = get(groot,'ScreenSize');
BpodSystem.ProtocolFigures.OutcomePlotFig = figure('Position', [25 scrsz(4)/2-150 scrsz(3)-50  scrsz(4)/6],'Name','Outcome plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.OutcomePlot = axes('Position', [.075 .3 .89 .6]);
OutcomePlot_Pavlov(BpodSystem.GUIHandles.OutcomePlot,'init',1-TrialTypes, UsOutcome);

% AGV - this doesn't seem to exist?  Also, S.TrialTypes is not defined.
%OutcomePlot_SO_Training(BpodSystem.GUIHandles.OutcomePlot,'init',2-S.TrialTypes);


%% NIDAQ :: Set up NIDAQ data aquisision

% Global variable to accumulate data.
global NidaqData_thisTrial
scrsz = get(groot,'ScreenSize'); % AGV
BpodSystem.ProtocolFigures.NIDAQDebugFig  = figure('Position', [scrsz(3)/2+25 scrsz(4)*2/3-100 scrsz(3)/2-50  scrsz(4)/3],'Name','Nidaq Duration plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.ProtocolFigures.NIDAQFig       = figure('Position', [25          scrsz(4)*2/3-100 scrsz(3)/2-50  scrsz(4)/3],'Name','NIDAQ plot','numbertitle','off');
BpodSystem.ProtocolFigures.NIDAQPanel1     = subplot(3,1,1);
BpodSystem.ProtocolFigures.NIDAQPanel2     = subplot(3,1,2);
BpodSystem.ProtocolFigures.NIDAQPanel3     = subplot(3,1,3);

% Define parameters for analog inputs.  Some params not used for manual trigger.
nidaq.duration                 = 20;        % 5 second acquisition, but this will continue until the stateMatrix finishes
nidaq.sample_rate              = 10000;     % 10khz aquisition
nidaq.ai_channels              = {'ai0','ai1','ai2'};       % 4 channels

% Define parameters for analog outputs
% Currently ctr2 gate  --> PFI1 --> channel 10 with channel 9 as Digital
% Ground
nidaq.ao_channels                 = {'port0/line0'};           % 1 channel (for laser)
nidaq.ao_data                     = ones(nidaq.sample_rate,length(nidaq.ao_channels));
%nidaq.ao_data                     = round(rand(nidaq.sample_rate,length(nidaq.ao_channels)));

% Note :: for this nidaq, we have to reset clock synchronization after
% every daq.reset!  This is dumb, but there you go.
% ni: National Instruments PCIe-6320 (Device ID: 'Dev1')
% This module is in slot 4294967295 of the PXI Chassis 4294967295.
% http://www.mathworks.com/matlabcentral/answers/37134-data-acquisition-from-ni-pxie-1062q
daq.reset
daq.HardwareInfo.getInstance('DisableReferenceClockSynchronization',true);

% Set up session and channels
nidaq.session = daq.createSession('ni')
for ch = nidaq.ai_channels
    addAnalogInputChannel(nidaq.session,'Dev1',ch,'Voltage');
end
for ch = nidaq.ao_channels
    addDigitalChannel(nidaq.session,'Dev1',ch, 'OutputOnly')
end

% Sampling rate and continuous updating (important for queue-ing ao data)
nidaq.session.Rate = nidaq.sample_rate;
nidaq.session.IsContinuous = true;

% Accumulate data as the trial goes on, and add a pretty plot to look at.
    function processNidaqData(src,event)
        % Save trial data to the global nidaqTrailData variable.
        % Also, plot the data as it comes in.
        %figure(BpodSystem.ProtocolFigures.NIDAQFig);
        %subplot(2,1,1); 
        %plot(event.TimeStamps, event.Data);
        %subplot(2,1,2);
        
        NidaqData_thisTrial = [NidaqData_thisTrial;event.Data*10]; % Why * 10?  With lockin at 10x the total amplification is 100x.
        %plot(BpodSystem.ProtocolFigures.NIDAQPanel,(1:length(NidaqData_thisTrial))/nidaq.sample_rate,bsxfun(@minus,NidaqData_thisTrial,mean(NidaqData_thisTrial(1:min(1000,size(NidaqData_thisTrial,1))))));
%         plot(BpodSystem.ProtocolFigures.NIDAQPanel1,(1:length(NidaqData_thisTrial))/nidaq.sample_rate,NidaqData_thisTrial(:,1)-mean(NidaqData_thisTrial(:,1)));
%         plot(BpodSystem.ProtocolFigures.NIDAQPanel2,(1:length(NidaqData_thisTrial))/nidaq.sample_rate,NidaqData_thisTrial(:,2)-mean(NidaqData_thisTrial(:,2)));
%         plot(BpodSystem.ProtocolFigures.NIDAQPanel3,(1:length(NidaqData_thisTrial))/nidaq.sample_rate,NidaqData_thisTrial(:,3)-mean(NidaqData_thisTrial(:,3)));
        plot(BpodSystem.ProtocolFigures.NIDAQPanel1,(1:length(NidaqData_thisTrial))/nidaq.sample_rate,NidaqData_thisTrial(:,1));
        plot(BpodSystem.ProtocolFigures.NIDAQPanel2,(1:length(NidaqData_thisTrial))/nidaq.sample_rate,NidaqData_thisTrial(:,2));
        plot(BpodSystem.ProtocolFigures.NIDAQPanel3,(1:length(NidaqData_thisTrial))/nidaq.sample_rate,NidaqData_thisTrial(:,3));

        %xlim(BpodSystem.ProtocolFigures.NIDAQPanel,[0 max([15,size(NidaqData_thisTrial,1)/nidaq.sample_rate])]);
        %xlim(BpodSystem.ProtocolFigures.NIDAQPane2,[0 max([15,size(NidaqData_thisTrial,1)/nidaq.sample_rate])]);
        %xlim(BpodSystem.ProtocolFigures.NIDAQPane3,[0 max([15,size(NidaqData_thisTrial,1)/nidaq.sample_rate])]);
        %ylim(BpodSystem.ProtocolFigures.NIDAQPanel,[-10 10])
        %ylim(BpodSystem.ProtocolFigures.NIDAQPane2,[-10 10])
        %ylim(BpodSystem.ProtocolFigures.NIDAQPane3,[-10 10])
        ylabel(BpodSystem.ProtocolFigures.NIDAQPanel1,{'Response','(Post-LOCKIN)'})
        ylabel(BpodSystem.ProtocolFigures.NIDAQPanel2,{'Response','(Pre-LOCKIN)'})
        ylabel(BpodSystem.ProtocolFigures.NIDAQPanel3,{'Lockin TTL Out'})
        xlabel(BpodSystem.ProtocolFigures.NIDAQPanel3,'Time (seconds')
        %ylim([-5 5]);
        %axis tight
        drawnow;
        legend(nidaq.ai_channels,'Location','East')
    end
lh{1} = nidaq.session.addlistener('DataAvailable',@processNidaqData);
lh{2} = nidaq.session.addlistener('DataRequired', @(src,event) src.queueOutputData(nidaq.ao_data));
%nidaq.session.NotifyWhenDataAvailableExceeds = nidaq.sample_rate;
% /NIDAQ setup.

%% Define stimuli and send to sound server

SF = 192000; % Sound card sampling rate
Sound1 = GenerateSineWave(SF, S.GUI.SinWaveFreq1, S.SoundDuration); % Sampling freq (hz), Sine frequency (hz), duration (s)
Sound2 = GenerateSineWave(SF, S.GUI.SinWaveFreq2, S.SoundDuration); % Sampling freq (hz), Sine frequency (hz), duration (s)


PsychToolboxSoundServer('init')
PsychToolboxSoundServer('Load', 1, Sound1);
PsychToolboxSoundServer('Load', 2, Sound2);

BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';

%% Main trial loop

for currentTrial = 1:MaxTrials
    
    switch UsOutcome(currentTrial)
        case 1
                StateChangeArgument1 = 'Reward';
                 
                if S.DirectDelivery == 1;
                    StateChangeArgument2 = 'Reward';
                else
                	StateChangeArgument2 = 'PostUS';
                end
                
        case 2
                StateChangeArgument1 = 'Punish';
                StateChangeArgument2 = 'Punish';
        case 0
                StateChangeArgument1 = 'PostUS';
                StateChangeArgument2 = 'PostUS';
    end
       
    S.ITI = 10;
    while S.ITI > 4
        S.ITI = exprnd(1)+0.5;
    end
    
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    
    sma = NewStateMatrix(); % Assemble state matrix
    sma = SetGlobalTimer(sma, 1, S.SoundDuration + S.Delay);
    sma = AddState(sma,'Name', 'NoLick', ...
        'Timer', S.NoLick,...
        'StateChangeConditions', {'Tup', 'ITI','Port2In','RestartNoLick'},...
        'OutputActions', {'PWM1', 255}); %Light On
    sma = AddState(sma,'Name', 'RestartNoLick', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup', 'NoLick',},...
        'OutputActions', {'PWM1', 255}); %Light On
    sma = AddState(sma, 'Name', 'ITI', ...
        'Timer',S.ITI,...
        'StateChangeConditions', {'Tup', 'PreTrialRecording'},...
        'OutputActions', {});
    sma = AddState(sma, 'Name','PreTrialRecording',...
        'Timer',S.PreTrialRecording,...
        'StateChangeConditions',{'Tup','StartStimulus'},...
        'OutputActions',{});
    sma = AddState(sma, 'Name', 'StartStimulus', ...
        'Timer', 0.025,...
        'StateChangeConditions', {'Tup','DeliverStimulus'},...
        'OutputActions', {'SoftCode',TrialTypes(currentTrial)});
     
    % AGV 7/30/2015 - changed to avoid WaitForUs state, which seems to
    % crash.
    sma = AddState(sma, 'Name', 'DeliverStimulus', ...
        'Timer', S.SoundDuration,...
        'StateChangeConditions', {'Tup','Delay'},...
        'OutputActions', {'GlobalTimerTrig',1});
    
    sma = AddState(sma, 'Name','Delay', ...
        'Timer', S.Delay,...
        'StateChangeConditions', {'Tup',StateChangeArgument2},... % usually either Punish or Reward
        'OutputActions', {});
    
%     sma = AddState(sma, 'Name', 'DeliverStimulus', ...
%         'Timer', S.SoundDuration,...
%         'StateChangeConditions', {'Port2In','WaitForUS','Tup','Delay'},...
%         'OutputActions', {'GlobalTimerTrig',1});

%     sma = AddState(sma, 'Name','Delay', ...
%         'Timer', S.Delay,...
%         'StateChangeConditions', {'Port2In','WaitForUS','Tup',StateChangeArgument2},...
%         'OutputActions', {});
    
    sma = AddState(sma, 'Name', 'WaitForUS', ...
        'Timer',3,...
        'StateChangeConditions', {'GlobalTimer1_End', StateChangeArgument1},...
        'OutputActions', {});
    
    sma = AddState(sma,'Name', 'Reward', ...
        'Timer',S.RewardValveTime,...
        'StateChangeConditions', {'Tup', 'PostUS'},...
        'OutputActions', {'BNCState', 1,'ValveState', S.RewardValveCode});
    
    sma = AddState(sma, 'Name', 'Punish', ...
        'Timer',S.PunishValveTime, ...
        'StateChangeConditions', {'Tup', 'PostUS'}, ...
        'OutputActions', {'BNCState', 1,'ValveState', S.PunishValveCode});
    
    sma = AddState(sma,'Name','PostUS',...
        'Timer',1,...
        'StateChangeConditions',{'Port2In','ResetDrinkingTimer','Tup','PostTrialRecording'},...
        'OutputActions',{});
  
    sma = AddState(sma,'Name','ResetDrinkingTimer',...
        'Timer',0,...
        'StateChangeConditions',{'Tup','PostUS'},...
        'OutputActions',{'BNCState', 1}); % To signal licks.
    
    sma = AddState(sma, 'Name','PostTrialRecording',...
        'Timer',S.PostTrialRecording,...
        'StateChangeConditions',{'Tup','exit'},...
        'OutputActions',{});

    BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
    SendStateMatrix(sma);
    
    % NIDAQ :: Initialize data matrix and start nidaq in background - this takes ~150ms
    NidaqData_thisTrial = [];
    nidaq.session.queueOutputData(nidaq.ao_data)
    % Dropping from 10hz to 5hz seems to fix the short-nidaq-recording bug?
    nidaq.session.NotifyWhenDataAvailableExceeds = nidaq.session.Rate/5; % Must be done after queueing data.
    nidaq.session.prepare(); %Saves 50ms on startup time, perhaps more for repeats.
    nidaq.session.startBackground(); % takes ~0.1 second to start and release control.
    % /NIDAQ
    
    % Run state matrix
    RawEvents = RunStateMatrix();  % Blocking!
    
    % NIDAQ :: Stop nidaq.session and cleanup
    nidaq.session.stop() % Kills ~0.002 seconds after state matrix is done.
    wait(nidaq.session) % Tring to wait until session is done - did we record the full session?
    % ..... :: Ensure we drop our outputs back to zero if at all possible - takes ~0.01 seconds.
    nidaq.session.outputSingleScan(zeros(1,length(nidaq.ao_channels))); 
    % ..... :: Save data in BpodSystem format.
    BpodSystem.Data.NidaqData{currentTrial} = NidaqData_thisTrial;
    % /NIDAQ

    if ~isempty(fieldnames(RawEvents)) % If trial data was returned
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        BpodSystem.Data.TrialTypes(currentTrial) = TrialTypes(currentTrial); % Adds the trial type of the current trial to data
        Outcomes = UpdateOutcomePlot(TrialTypes, BpodSystem.Data, UsOutcome);
        BpodSystem.Data.TrialOutcome(currentTrial) = Outcomes(currentTrial);
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    end    
    
    trial_duration = BpodSystem.Data.RawEvents.Trial{currentTrial}.States.PostTrialRecording(2);
    nidaq_duration = size(BpodSystem.Data.NidaqData{currentTrial},1);
    %     fprintf('\ntrial          :: %.2f\n',currentTrial)
    %     fprintf('trial_duration :: %.2f\n',trial_duration)
    %     fprintf('nidaq_duration :: %.2f\n',nidaq_duration/nidaq.sample_rate)
    %     fprintf('difference     :: %.2f\n',trial_duration - nidaq_duration/nidaq.sample_rate)
    if (trial_duration - nidaq_duration/nidaq.sample_rate) >= 0.5,
            fprintf('ERROR :: Trial %.0f ::  Missing data at end of trial (> 0.5s) :: %.2f\n',currentTrial,trial_duration - nidaq_duration/nidaq.sample_rate)
    end
    %assert( (trial_duration - nidaq_duration/nidaq.sample_rate) <= 0.5, 'ERROR :: Missing data at end of trial (> 0.5s)' )        
    
    if BpodSystem.BeingUsed == 0
        return
    end 
   
    %% Debugging figure - trying to figure out why nidaq duration drops sometimes.
    % I haven't seen this bug since I changed update freq to 5hz vs. 10hz,
    % so it could be that I guess.
    figure(BpodSystem.ProtocolFigures.NIDAQDebugFig); 
    subplot(2,2,1)
    cla; hold on
    plot(1:currentTrial, cellfun(@(x) x.States.PostTrialRecording(1),BpodSystem.Data.RawEvents.Trial),'b')
    plot(1:currentTrial, cellfun(@(x) x.States.PostTrialRecording(2),BpodSystem.Data.RawEvents.Trial),'g')
    plot(1:currentTrial, cellfun(@(x) size(x,1)/nidaq.sample_rate, BpodSystem.Data.NidaqData),'r')
    legend({'PostTrialRecording(1)','PostTrialRecording(2)','Nidaq'})
    ylabel('Seconds')
    subplot(2,2,3)
    stem(1:currentTrial, ...
        cellfun(@(x) size(x,1)/nidaq.sample_rate, BpodSystem.Data.NidaqData) - ...
        cellfun(@(x) x.States.PostTrialRecording(2),BpodSystem.Data.RawEvents.Trial),'ro')
    ylims = ylim;
    ylim([ min(-1,ylims(1)) max(1,ylims(2)) ])
    ylabel('BAD <-- Seconds --> OK')
    legend('Difference')
    subplot(1,2,2); cla; hold on
    plot(1:currentTrial, cellfun(@(x) mean(x(1:nidaq.sample_rate,1)), BpodSystem.Data.NidaqData),'bo')
    title('Signal in 1st second of recording')
    axis on
    drawnow
    
    if currentTrial == 500,
       % Started at 9:30 pm
       % Changed to 5hz updating.
       % Not restarted before testing.
       disp('Stopped at trial 500 for debugging')
       datestr(now,31)
       keyboard
    end
    
    
end

 

end

%% sub-functions
function Outcomes = UpdateOutcomePlot(TrialTypes, Data, UsOutcome)
global BpodSystem
Outcomes = zeros(1,Data.nTrials);

% 0 - LICK + REWARD
% 1 - LICK + PUNISH
% 2 - NO_LICK + REWARD
% 3 - NO LICK + OMISSION
% 4 - NO LICK + PUNISH
% 5 - LICK + OMISSION



for x = 1:Data.nTrials
    Lick = ~isnan(Data.RawEvents.Trial{x}.States.WaitForUS(1)) ;
    if ~isnan(Data.RawEvents.Trial{x}.States.Reward(1)) && Lick ==1
        Outcomes(x) = 1;
    elseif ~isnan(Data.RawEvents.Trial{x}.States.Punish(1))&& Lick == 1
        Outcomes(x) = 0;
    elseif Lick ~= 1 && UsOutcome(x) == 1
        Outcomes(x) = 2;
    elseif ~isnan(Data.RawEvents.Trial{x}.States.Punish(1))
        Outcomes(x) = 4;
    elseif Lick == 1
        Outcomes(x) = 5;
    else 
        Outcomes(x) = 3;
    end
end
OutcomePlot_Pavlov(BpodSystem.GUIHandles.OutcomePlot,'update',Data.nTrials+1,1-TrialTypes,Outcomes, UsOutcome)
end


