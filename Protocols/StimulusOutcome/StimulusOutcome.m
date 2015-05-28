function StimulusOutcome

global BpodSystem

%% Define parameters

S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S

if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings
    
    S.GUI.NumTrialTypes = 2;
    S.GUI.SinWaveFreq1 = 20000; 
    S.GUI.SinWaveFreq2 = 4000;
    
    
    
    S.NoLick = 1.5;
    S.ITI = 1;
    S.SoundDuration = 1; 
    S.RewardValveCode = 1;
    S.RewardAmount = 3;
    S.PunishValveCode = 2;
    S.PunishValveTime = 0.2; 
    S.Delay = 1;
    S.RewardValveTime =  GetValveTimes(S.RewardAmount, S.RewardValveCode);
end

% Initialize parameter GUI plugin
BpodParameterGUI('init', S);

%% Define trials

MaxTrials = 5000;
rng('shuffle')
TrialTypes = randi(S.GUI.NumTrialTypes,1,MaxTrials);
p = rand(1,MaxTrials);
UsOutcome = zeros(size(TrialTypes));
UsOutcome(p <= 0.8 & TrialTypes == 1) = 1;
UsOutcome(p <= 0.65 & TrialTypes == 2) = 2;
UsOutcome(p > 0.8 & p <= 0.9 & TrialTypes == 1) = 2;
UsOutcome(p > 0.65 & p <= 0.9 & TrialTypes == 2) = 1;

BpodSystem.Data.TrialTypes = []; % The trial type of each trial completed will be added here.

%% Initialize plots

BpodSystem.ProtocolFigures.OutcomePlotFig = figure('Position', [400 400 1000 200],'Name','Outcome plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.OutcomePlot = axes('Position', [.075 .3 .89 .6]);
OutcomePlot_Pavlov(BpodSystem.GUIHandles.OutcomePlot,'init',1-TrialTypes, UsOutcome);

%% Define stimuli and send to sound server

SF = 192000; % Sound card sampling rate
Sound1 = GenerateSineWave(SF, S.GUI.SinWaveFreq1, S.SoundDuration); % Sampling freq (hz), Sine frequency (hz), duration (s)
Sound2 = GenerateSineWave(SF, S.GUI.SinWaveFreq2, S.SoundDuration); % Sampling freq (hz), Sine frequency (hz), duration (s)


PsychToolboxSoundServer('init')
PsychToolboxSoundServer('Load', 1, Sound1);
PsychToolboxSoundServer('Load', 2, Sound2);

BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';

%% Main trial loop
tic
for currentTrial = 1:MaxTrials
    
    switch UsOutcome(currentTrial)
        case 1
                StateChangeArgument1 = 'Reward';
                StateChangeArgument2 = 'PostUS';
                
        case 2
                StateChangeArgument1 = 'Punish';
                StateChangeArgument2 = 'Punish';
        case 0
                StateChangeArgument1 = 'PostUS';
                StateChangeArgument2 = 'PostUS';
     end
        

        
    S.ITI = 10;
    while S.ITI > 4
    S.ITI = exprnd(1)+1;
    end
    
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    
    sma = NewStateMatrix(); % Assemble state matrix
    sma = SetGlobalTimer(sma, 1, S.SoundDuration + S.Delay);
    sma = AddState(sma,'Name', 'NoLick', ...
        'Timer', S.NoLick,...
        'StateChangeConditions', {'Tup', 'ITI','Port1In','RestartNoLick'},...
        'OutputActions', {'PWM1', 255});
    sma = AddState(sma,'Name', 'RestartNoLick', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup', 'NoLick',},...
        'OutputActions', {'PWM1', 255});
    sma = AddState(sma, 'Name', 'ITI', ...
        'Timer',S.ITI,...
        'StateChangeConditions', {'Tup', 'StartStimulus'},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'StartStimulus', ...
        'Timer', 0.025,...
        'StateChangeConditions', {'Tup','DeliverStimulus'},...
        'OutputActions', {'SoftCode',TrialTypes(currentTrial)});
     sma = AddState(sma, 'Name', 'DeliverStimulus', ...
        'Timer', S.SoundDuration,...
        'StateChangeConditions', {'Port1In','WaitForUS','Tup','Delay'},...
        'OutputActions', {'GlobalTimerTrig',1});
    sma = AddState(sma, 'Name','Delay', ...
        'Timer', S.Delay,...
        'StateChangeConditions', {'Port1In','WaitForUS','Tup',StateChangeArgument2},...
        'OutputActions', {});
    sma = AddState(sma, 'Name', 'WaitForUS', ...
        'Timer',3,...
        'StateChangeConditions', {'GlobalTimer1_End', StateChangeArgument1},...
        'OutputActions', {});
    sma = AddState(sma,'Name', 'Reward', ...
        'Timer',S.RewardValveTime,...
        'StateChangeConditions', {'Tup', 'PostUS'},...
        'OutputActions', {'ValveState', S.RewardValveCode});
    sma = AddState(sma, 'Name', 'Punish', ...
        'Timer',S.PunishValveTime, ...
        'StateChangeConditions', {'Tup', 'PostUS'}, ...
        'OutputActions', {'ValveState', S.PunishValveCode});
    sma = AddState(sma,'Name','PostUS',...
        'Timer',0.5,...
        'StateChangeConditions',{'Tup','exit'},...
        'OutputActions',{});
    SendStateMatrix(sma);
    a(currentTrial) = toc;
     tic
    RawEvents = RunStateMatrix;
    if ~isempty(fieldnames(RawEvents)) % If trial data was returned
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        BpodSystem.Data.TrialTypes(currentTrial) = TrialTypes(currentTrial); % Adds the trial type of the current trial to data
        UpdateOutcomePlot(TrialTypes, BpodSystem.Data, UsOutcome);
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    end
    if BpodSystem.BeingUsed == 0
        save test a
        return
        
    end 
   
end
end

%% sub-functions
function UpdateOutcomePlot(TrialTypes, Data, UsOutcome)
global BpodSystem
Outcomes = zeros(1,Data.nTrials);

for x = 1:Data.nTrials
    Lick = ~isnan(Data.RawEvents.Trial{x}.States.WaitForUS(1)) ;
    if ~isnan(Data.RawEvents.Trial{x}.States.Reward(1))
        Outcomes(x) = 1;
    elseif ~isnan(Data.RawEvents.Trial{x}.States.Punish(1))&& Lick == 1
        Outcomes(x) = 0;
    elseif isnan(Data.RawEvents.Trial{x}.States.Reward(1))&& UsOutcome(x) == 1
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


