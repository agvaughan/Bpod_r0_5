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
function LW_training
% Lick-withholding training protocol
% Written by Hyun-Jae Pi 11/2014.

global BpodSystem
%% Define parameters
S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S
if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings
    
    S.GUI.TrainingLevel = 3;   % <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    S.GUI.SinWaveFreq1 = 3000; % Hz
    S.GUI.StimulusDuration = 1.5;
    S.GUI.RewardAmount = 5;    % uL
    S.GUI.ITI = 1;             % sec
    
    S.InitialDelay = 1;
    S.RestartInitialDelay = 1;
    S.DeliverStimulus = 0;
    S.Drinking = 1;
    S.WaitForRewardLick = 3;
    S.SoundDuration1 = S.GUI.StimulusDuration;
    S.RewardValveCode =1;
    S.PunishValveCode =2;
    S.PunishValveTime = 0.2; % 200ms airpuff
end


switch S.GUI.TrainingLevel
    case 1     % RestartITI w/ tone + NoSound Stim + DD
        DirectDelivery =1;
        StateChangeConditionsArgument = {'Tup', 'Reward'};
        OutputActionArgument = {};
    case 2     % Directly Delivery + air puff
        DirectDelivery =1;
        StateChangeConditionsArgument = {'Port1In', 'Punish','Tup', 'Reward'};
        OutputActionArgument = {'SoftCode', 1, 'BNCState', 1};
    case 3     % full task w/ shorter waiting 1.5s
        DirectDelivery =0;
        StateChangeConditionsArgument = {'Port1In', 'Punish'};
        OutputActionArgument = {'SoftCode', 1, 'BNCState', 1};
end

% Initialize parameter GUI plugin
BpodParameterGUI('init', S);

%% Define trials
numTrialTypes = 1;  %%%    <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
MaxTrials = 5000;
TrialTypes = ceil(rand(1,MaxTrials)*numTrialTypes);
BpodSystem.Data.TrialTypes = []; % The trial type of each trial completed will be added here.

%% Initialize plots
BpodSystem.ProtocolFigures.OutcomePlotFig = figure('Position', [400 600 1000 200],'Name','Outcome plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.OutcomePlot = axes('Position', [.075 .3 .89 .6]);
OutcomePlot_LW_training(BpodSystem.GUIHandles.OutcomePlot,'init',2-TrialTypes);

%% Define stimuli and send to sound server
SF = 192000; % Sound card sampling rate
Sound1 = GenerateSineWave(SF, S.GUI.SinWaveFreq1, S.SoundDuration1); % Sampling freq (hz), Sine frequency (hz), duration (s)
PunishSound = (rand(1,SF*.5)*2) - 1;

% Program sound server
PsychToolboxSoundServer('init')
PsychToolboxSoundServer('Load', 1, Sound1);
PsychToolboxSoundServer('Load', 4, PunishSound);

% Set soft code handler to trigger sounds
BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';
%PulsePal

%% Main trial loop
for currentTrial = 1:MaxTrials
    
    %    ProgramPulsePal(ParameterMatrix);
    S.RewardValveTime =  GetValveTimes(S.GUI.RewardAmount, [1]);
    S.TriggerPunish = PoissonValue(0.1);
    S.TriggerReward = PoissonValue(0.1);
    
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    
    sma = NewStateMatrix(); % Assemble state matrix
    sma = AddState(sma, 'Name', 'InitialDelay', ...
        'Timer', S.InitialDelay,...
        'StateChangeConditions', {'Port1In','RestartInitialDelay','Tup', 'DeliverStimulus'},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'RestartInitialDelay', ...
        'Timer', S.RestartInitialDelay,...
        'StateChangeConditions', {'Tup', 'InitialDelay'},...
        'OutputActions', {});
    
    switch DirectDelivery 
        case 1     
        sma = AddState(sma, 'Name', 'DeliverStimulus', ...
            'Timer', S.DeliverStimulus,...
            'StateChangeConditions', {'Tup', 'WaitForPunishLick'},...
            'OutputActions', OutputActionArgument);
        sma = AddState(sma, 'Name', 'WaitForPunishLick', ...
            'Timer', S.GUI.StimulusDuration,...
            'StateChangeConditions', StateChangeConditionsArgument,...
            'OutputActions', {});      
        case 0
        sma = AddState(sma, 'Name', 'DeliverStimulus', ...
            'Timer', S.DeliverStimulus,...
            'StateChangeConditions', {'Tup', 'WaitForPunishLick'},...
            'OutputActions', OutputActionArgument);
        sma = AddState(sma, 'Name', 'WaitForPunishLick', ...
            'Timer', S.GUI.StimulusDuration,...
            'StateChangeConditions', {'Tup', 'WaitForRewardLick', 'Port1In', 'TriggerPunish' },...
            'OutputActions', {});
    end
    
    sma = AddState(sma, 'Name', 'TriggerPunish', ...
        'Timer', S.TriggerPunish,...
        'StateChangeConditions', {'Tup', 'Punish'}, ...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'Punish', ...
        'Timer',S.PunishValveTime, ...
        'StateChangeConditions', {'Tup', 'ITI'}, ...
        'OutputActions', {'ValveState', S.PunishValveCode,'SoftCode',255,'PWM1', 128});  %maybe WN & LED are just during training
    sma = AddState(sma, 'Name', 'WaitForRewardLick', ...
        'Timer',S.WaitForRewardLick,...
        'StateChangeConditions', {'Tup', 'ITI', 'Port1In', 'TriggerReward'},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'TriggerReward', ...
        'Timer',S.TriggerReward,...
        'StateChangeConditions', {'Tup', 'Reward',},...
        'OutputActions', {});
    sma = AddState(sma,'Name', 'Reward', ...
        'Timer',S.RewardValveTime,...
        'StateChangeConditions', {'Tup', 'Drinking'},...
        'OutputActions', {'ValveState', S.RewardValveCode});
    sma = AddState(sma,'Name', 'Drinking', ...
        'Timer', S.Drinking,...
        'StateChangeConditions', {'Tup', 'ITI','Port1In','ResetDrinkingTimer'},...
        'OutputActions', {});
    sma = AddState(sma,'Name', 'ResetDrinkingTimer', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup', 'Drinking',},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'ITI', ...
        'Timer',S.GUI.ITI,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {});
    SendStateMatrix(sma);
    RawEvents = RunStateMatrix;
    if ~isempty(fieldnames(RawEvents)) % If trial data was returned
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
        % BpodSystem.Data = BpodNotebook(BpodSystem.Data); % Sync with Bpod notebook plugin
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        BpodSystem.Data.TrialTypes(currentTrial) = TrialTypes(currentTrial); % Adds the trial type of the current trial to data
        Outcomes = UpdateOutcomePlot(TrialTypes, BpodSystem.Data);
        BpodSystem.Data.TrialOutcome(currentTrial) = Outcomes(currentTrial);
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    end
    if BpodSystem.BeingUsed == 0
        return
    end
end
end


%% sub-functions
function Outcomes = UpdateOutcomePlot(TrialTypes, Data)
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
OutcomePlot_LW_training(BpodSystem.GUIHandles.OutcomePlot,'update',Data.nTrials+1,2-TrialTypes,Outcomes)
end

% generate value from Poisson distribution
function value = PoissonValue(lambda)
value = poissrnd(lambda*10)*0.01;
end
