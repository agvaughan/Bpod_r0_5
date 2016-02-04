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
function Olfactory2AFC_NIDAQ

% This protocol demonstrates control of the Island Motion olfactometer by using the hardware serial port to control an Arduino Leonardo Ethernet client.
% Written by Josh Sanders, 10/2014.
%
% SETUP
% You will need:
% - An Island Motion olfactometer: http://island-motion.com/5.html
% - Arduino Leonardo double-stacked with the Arduino Ethernet shield and the Bpod shield
% - This computer connected to the olfactometer's Ethernet router
% - The Ethernet shield connected to the same router
% - Arduino Leonardo connected to this computer (note its COM port)
% - Arduino Leonardo programmed with the Serial Ethernet firmware (in /Bpod Firmware/SerialEthernetModule/)

global BpodSystem

%% Define parameters
S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S
if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings
    S.GUI.RewardAmount = 5;
    S.GUI.StimulusDelayDuration = 0;
    S.GUI.MaxOdorDuration   = 1;
    S.GUI.TimeForResponse   = 5;
    S.GUI.TimeoutDuration   = 2;
    S.GUI.PostTrialDuration = 1;
end

% Initialize parameter GUI plugin
BpodParameterGUI('init', S);

%% Define trials
MaxTrials = 5000;
TrialTypes = ceil(rand(1,MaxTrials)*2);
BpodSystem.Data.TrialTypes = []; % The trial type of each trial completed will be added here.

%% Initialize plots
BpodSystem.ProtocolFigures.OutcomePlotFig = figure('Position', [200 200 1000 200],'name','Outcome plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.OutcomePlot = axes('Position', [.075 .3 .89 .6]);
OutcomePlot(BpodSystem.GUIHandles.OutcomePlot,'init',2-TrialTypes);
BpodNotebook('init');

%% Initialize Ethernet client on hardware serial port 1 and connect to olfactometer
SerialEthernet('Init', 'COM5'); % Set this to the correct COM port for Arduino Leonardo
pause(1);
OlfIP = [192 168 0 104];
SerialEthernet('Connect', OlfIP, 3336);
SerialEthernet('MessageMode', 1); % Force a connection release/renew after each string sent from the Ethernet module (necessary to prevent crashes for the Rechia olfactometer)

%% Define odors, program Ethernet server with commands for switching olfactometer valves
LeftOdor = [90 10]; % Flow rate on Banks 1 and 2 in ml/min
RightOdor = [10 90];
ValveOpenCommand = Valves2EthernetString('Bank1', 1, 'Bank2', 1); % From RechiaOlfactometer plugin. Simultaneously sets banks 1 and 2 to valve 1
ValveCloseCommand = Valves2EthernetString('Bank1', 0, 'Bank2', 0); % Simultaneously sets banks 1 and 2 to valve 0 (exhaust)
SerialEthernet('LoadString', 1, ValveOpenCommand); % Sets the "open" command as string 1
SerialEthernet('LoadString', 2, ValveCloseCommand); % Sets the "close" command as string 2

%% Set up NIDAQ data aquisision
%{

Timeline ::
- NIDAQ and State Matrix
- SendStateMatrix()
- start AO (ie., drive laser)
- wait for AO to startc
- start AI (simultaneously)
- RunStateMatrix()
    - Send a reference pulse from Bpod to AI(4) at NosePokeIn.
- Stop AI
- Stop AO

Input Channels :
    1 : Photodetector 1 input.
    2 : Photodetector 2 input.
    3 : Reference signal input.
    4 : Trigger channel

Output Channels :
    1 : Laser stimulus (1 for the duration of the trial)

We trigger aquisition in software before starting the Bpod state machine,
and then will just align things appropriately using Bpod triggers in the
Trigger Channel.
    
%}
%%
% Define parameters for analog inputs.  Some params not used for manual trigger.
ai.duration                 = 11;        % 10 second acquisition
ai.sample_rate              = 10000;     % 10khz aquisition
ai.channels                 = 1:4;       % 4 channels - do not 
ai.trigger_type             = 'manual';  % Manual trigger [ie., start(ai.AI)]

% Define parameters for analog outputs
ao.duration                 = ai.duration*1.1; % Same as input, with a hedge.
ao.channels                 = 0;           % 1 channel (for laser)
ao.sample_rate              = 10000;       % 10 second acquisition
ao.trigger_type             = 'Manual';
%ao.trigger_channel          = 4;
%ao.trigger_condition        = 'Rising';    % 10 second acquisition

%% Set up DAQ object
% The architecture here is that we initialize a DAQ input object with the
% following channels:
% Ai0  :: (+- amplified) input from the photometer.
% Ai4  :: Rotary encoder from the wheel,.
% Ai5  :: 
% Pfl1 :: trigger
%
% The laser will be stimulated from the bpod itself, via BNC-1 or BNC-2 
% turned on/off  via states WaitForCenterPoke/PostTrialPeriod. Both BNCs
% are used, so one can be used to trigger the DAQ and one used to drive the
% laser. Note that the BNC triggers are 2-bytes, so 
%0 = OFF, 1 = BNC1 ON, 2 = BNC2 ON, 3 = BNC1 ON & BNC2 ON
% 
% The input trigger is set to PFI1/TRIG2 (ie., channel 10 with 9 reference
% on the SCB-68 on this rig)

s = daq.createSession('ni')
addAnalogInputChannel(s,'Dev1','ai0', 'Voltage');
addTriggerConnection(s,'external','Dev1/PFI1','StartTrigger')
startForeground(s)

%%
% Initialize analoginput
DAQ = daq.createSession('ni');
DAQ.addAnalogInputChannel('Dev1',ai.channels,'Voltage');
DAQ.Rate = ai.sample_rate;
DAQ.DurationInSeconds = ai.duration;
% Initialize Trigger
DAQ.TriggersPerRun = Inf;
DAQ.ExternalTriggerTimeout = 500;
DAQ

DAQ.startBackground()


%% Main trial loop
try,
    for currentTrial = 1:MaxTrials
        S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
        if TrialTypes(currentTrial) == 1
            SetBankFlowRate(OlfIP, 1, LeftOdor(1)); % Set bank 1 to 100ml/min (requires Bpod computer on same ethernet network as olfactometer)
            SetBankFlowRate(OlfIP, 2, LeftOdor(2)); % Set bank 2 to 0ml/min
        else
            SetBankFlowRate(OlfIP, 1, RightOdor(1)); % Set bank 1 to 100ml/min
            SetBankFlowRate(OlfIP, 2, RightOdor(2)); % Set bank 2 to 0ml/min
        end
        R = GetValveTimes(S.GUI.RewardAmount, [1 3]); LeftValveTime = R(1); RightValveTime = R(2); % Update reward amounts
        switch TrialTypes(currentTrial) % Determine trial-specific state matrix fields
            case 1
                LeftActionState = 'Reward'; RightActionState = 'Punish';
                ValveCode = 1; ValveTime = LeftValveTime;
            case 2
                LeftActionState = 'Punish'; RightActionState = 'Reward';
                ValveCode = 4; ValveTime = RightValveTime;
        end
        sma = NewStateMatrix(); % Assemble state matrix
        sma = AddState(sma, 'Name', 'WaitForCenterPoke', ...
            'Timer', 0,...
            'StateChangeConditions', {'Port2In', 'Delay'},...
            'OutputActions', {'BNCState', 3});
        sma = AddState(sma, 'Name', 'Delay', ...
            'Timer', S.GUI.StimulusDelayDuration,...
            'StateChangeConditions', {'Tup', 'DeliverStimulus'},...
            'OutputActions', {});
        sma = AddState(sma, 'Name', 'DeliverStimulus', ...
            'Timer', S.GUI.MaxOdorDuration,...
            'StateChangeConditions', {'Tup', 'WaitForResponse', 'Port2Out', 'WaitForResponse'},...
            'OutputActions', {'Serial1Code', 1});
        sma = AddState(sma, 'Name', 'WaitForResponse', ...
            'Timer', S.GUI.TimeForResponse,...
            'StateChangeConditions', {'Tup', 'exit', 'Port1In', LeftActionState, 'Port3In', RightActionState},...
            'OutputActions', {'Serial1Code', 2, 'PWM1', 255, 'PWM3', 255});
        sma = AddState(sma, 'Name', 'Reward', ...
            'Timer', ValveTime,...
            'StateChangeConditions', {'Tup', 'PostTrialPeriod'},...
            'OutputActions', {'ValveState', ValveCode});
        sma = AddState(sma, 'Name', 'Punish', ...
            'Timer', S.GUI.TimeoutDuration,...
            'StateChangeConditions', {'Tup', 'PostTrialPeriod'},...
            'OutputActions', {});
        sma = AddState(sma, 'Name', 'EarlyWithdrawalPunish', ...
            'Timer', S.GUI.TimeoutDuration,...
            'StateChangeConditions', {'Tup', 'PostTrialPeriod'},...
            'OutputActions', {});
        sma = AddState(sma,'Name','PostTrialPeriod', ...
            'Timer', S.GUI.PostTrialDuration,...
            'StateChangeConditions',{'Tup','exit'},...
            'OutputActions', {'BNCState', 3});
        
        SendStateMatrix(sma);
        
        
        % Run state matrix
        RawEvents = RunStateMatrix();
        
        % Recover AI data and cleaup AI/AO.
        ai.data = getdata(ai.AI);
        stop(ao.AO)

        % Trigger code.
        %aitime = get(ai,'InitialTriggerTime');
        %aotime = get(AO,'InitialTriggerTime');
        %delta = abs(aotime - aitime);
        %sprintf('%d',delta(6))
        
        delete(ai); clear ai
        delete(AO); clear AO
        
        % Cleanup NIDAQ
        
        if ~isempty(fieldnames(RawEvents)) % If trial data was returned
            % TODO :: PLOTTING FOR NIDAQ
            BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
            BpodSystem.Data = BpodNotebook('sync', BpodSystem.Data); % Sync with Bpod notebook plugin
            BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
            BpodSystem.Data.TrialTypes(currentTrial) = TrialTypes(currentTrial); % Adds the trial type of the current trial to data
            UpdateOutcomePlot(TrialTypes, BpodSystem.Data);
            SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
        end
        HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
        if BpodSystem.BeingUsed == 0
            return
        end
    end % Loop across trials
catch,
    % Cleanup ai/ao objects
    stop(ai.AI)
    stop(ao.AO)
    delete(ai.AI);
    delete(ao.AO);
    rethrow(lasterror)
end

aitime = get(ai,'InitialTriggerTime');
aotime = get(AO,'InitialTriggerTime');
delta = abs(aotime - aitime);
sprintf('%d',delta(6))

delete(ai); clear ai
delete(AO); clear AO

function UpdateOutcomePlot(TrialTypes, Data)
global BpodSystem
Outcomes = zeros(1,Data.nTrials);
for x = 1:Data.nTrials
    if ~isnan(Data.RawEvents.Trial{x}.States.Reward(1))
        Outcomes(x) = 1;
    elseif ~isnan(Data.RawEvents.Trial{x}.States.Punish(1))
        Outcomes(x) = 0;
    else
        Outcomes(x) = 3;
    end
end
OutcomePlot(BpodSystem.GUIHandles.OutcomePlot,'update',Data.nTrials+1,2-TrialTypes,Outcomes)
