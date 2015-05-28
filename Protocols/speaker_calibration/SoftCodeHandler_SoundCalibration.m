function SoftCodeHandler_SoundCalibration(ID)

global AnalogInputObj

switch ID
    case 1 
        PsychToolboxSoundServer('Play', ID);
    case 2
        start(AnalogInputObj)
    otherwise
        PsychToolboxSoundServer('StopAll');
end