%% CAPTURING DATA THROUGH PICOSCOPE

% DEVICE SETUP
clc;
close all;
clear all;
PS5000aConfig;
channelA = ps5000aEnuminfo.enPS5000AChannel.PS5000A_CHANNEL_A;
channelB = ps5000aEnuminfo.enPS5000AChannel.PS5000A_CHANNEL_B;

if (exist('ps5000aDeviceObj', 'var') && ps5000aDeviceObj.isvalid && strcmp(ps5000aDeviceObj.status, 'open'))
    openDevice = questionDialog(['Device object ps5000aDeviceObj has an open connection. ' ...
        'Do you wish to close the connection and continue?'], ...
        'Device Object Connection Open');
    
    if (openDevice == PicoConstants.TRUE)
        % Close connection to device.
        disconnect(ps5000aDeviceObj);
        delete(ps5000aDeviceObj);
    else
        return;
    end
end

ps5000aDeviceObj = icdevice('picotech_ps5000a_generic'); 
connect(ps5000aDeviceObj);
[status.getUnitInfo, unitInfo] = invoke(ps5000aDeviceObj, 'getUnitInfo');
disp(unitInfo);
fprintf('\n');

% CHANNEL SETUP 

% Channel A
channelSettings(1).enabled = PicoConstants.TRUE; % Enabling Channel A
channelSettings(1).coupling = ps5000aEnuminfo.enPS5000ACoupling.PS5000A_DC; % Setting the Coupling for Channel A to be DC
channelSettings(1).range = ps5000aEnuminfo.enPS5000ARange.PS5000A_10V; % Setting range to 10V
channelSettings(1).analogueOffset = 0.0; % Setting the analogue signal offset value
% Variables that will be required later
channelARangeMv = PicoConstants.SCOPE_INPUT_RANGES(channelSettings(1).range + 1);
disp(['ChA range in mV: ' num2str(channelARangeMv)])
fprintf('\n')

% Channel B
channelSettings(2).enabled = PicoConstants.FALSE;
channelSettings(2).coupling = ps5000aEnuminfo.enPS5000ACoupling.PS5000A_DC;
channelSettings(2).range = ps5000aEnuminfo.enPS5000ARange.PS5000A_2V;
channelSettings(2).analogueOffset = 0.0;
% Variables that will be required later
channelBRangeMv = PicoConstants.SCOPE_INPUT_RANGES(channelSettings(2).range + 1);
disp(['ChB range in mV: ' num2str(channelBRangeMv)])
fprintf('\n')

% Keep the status values returned from the driver.
numChannels = get(ps5000aDeviceObj, 'channelCount');
status.setChannelStatus = zeros(numChannels, 1);

[status.currentPowerSource] = invoke(ps5000aDeviceObj, 'ps5000aCurrentPowerSource');

if (status.currentPowerSource == PicoStatus.PICO_POWER_SUPPLY_NOT_CONNECTED)
    numChannels = PicoConstants.DUAL_SCOPE;
end
for ch = 1:numChannels
   status.setChannelStatus(ch) = invoke(ps5000aDeviceObj, 'ps5000aSetChannel', ...
        (ch - 1), channelSettings(ch).enabled, ...
        channelSettings(ch).coupling, channelSettings(ch).range, ...
        channelSettings(ch).analogueOffset);
end

disp(['Number of Channels: ', num2str(numChannels)]);
fprintf('\n');

% TRIGGER FOR CHANNEL A

triggerGroupObj = get(ps5000aDeviceObj, 'Trigger');
triggerGroupObj = triggerGroupObj(1);

% If trigger condition not met in 1 second the scope will
% automatically start to capture data 1000mS
set(triggerGroupObj, 'autoTriggerMs', 1000);

[status.setSimpleTrigger] = invoke(triggerGroupObj, 'setSimpleTrigger', 0, 500, 2);

% DATA BUFFER --> Driver Buffer & Application Buffer

overviewBufferSize  = 100000; % Size of the buffer to collect data from buffer.
segmentIndex        = 0;   
ratioMode           = ps5000aEnuminfo.enPS5000ARatioMode.PS5000A_RATIO_MODE_NONE; % No downsampling, returns raw data values

% Buffers to be passed to the driver
pDriverBufferChA = libpointer('int16Ptr', zeros(overviewBufferSize, 1, 'int16'));

status.setDataBufferChA = invoke(ps5000aDeviceObj, 'ps5000aSetDataBuffer', ...
    channelA, pDriverBufferChA, overviewBufferSize, segmentIndex, ratioMode);

% Application Buffers - these are for copying from the driver into.
pAppBufferChA = libpointer('int16Ptr', zeros(overviewBufferSize, 1, 'int16'));

% Streaming properties and functions are located in the Instrument Driver's Streaming group
streamingGroupObj = get(ps5000aDeviceObj, 'Streaming');
streamingGroupObj = streamingGroupObj(1);
status.setAppDriverBuffersA = invoke(streamingGroupObj, 'setAppAndDriverBuffers', channelA, ...
    pAppBufferChA, pDriverBufferChA, overviewBufferSize);

% ADC RESOLUTION
[status.setResolution, resolution] = invoke(ps5000aDeviceObj, 'ps5000aSetDeviceResolution', 16);  
maxADCCount = get(ps5000aDeviceObj, 'maxADCValue');

% SAMPLING RATE
% For 1 MS/s
set(streamingGroupObj, 'streamingInterval', 1e-6);

% for 1Ms/s
set(ps5000aDeviceObj, 'numPreTriggerSamples', 0);
set(ps5000aDeviceObj, 'numPostTriggerSamples', 1000000);

% STREAMING PARAMETER
downSampleRatio = 1;
downSampleRatioMode = ps5000aEnuminfo.enPS5000ARatioMode.PS5000A_RATIO_MODE_NONE;

% DATA COLLECTION FINAL BUFFER
maxSamples = get(ps5000aDeviceObj, 'numPreTriggerSamples') + ...
    get(ps5000aDeviceObj, 'numPostTriggerSamples');

finalBufferLength = round(1.5 * maxSamples / downSampleRatio);
pBufferChAFinal = libpointer('singlePtr', zeros(finalBufferLength, 1, 'single'));
originalPowerSource = invoke(ps5000aDeviceObj, 'ps5000aCurrentPowerSource');

% Start streaming data collection.
[status.runStreaming, sampleInterval, sampleIntervalTimeUnitsStr] = ...
    invoke(streamingGroupObj, 'ps5000aRunStreaming', downSampleRatio, ...
    downSampleRatioMode, overviewBufferSize);
    
% Variables to be used when collecting the data:
hasAutoStopOccurred = PicoConstants.FALSE;  % Indicates if the device has stopped automatically.
powerChange         = PicoConstants.FALSE;  % If the device power status has changed.
newSamples          = 0; % Number of new samples returned from the driver.
previousTotal       = 0; % The previous total number of samples.
totalSamples        = 0; % Total samples captured by the device.
startIndex          = 0; % Start index of data in the buffer returned.
hasTriggered        = 0; % To indicate if trigger has occurred.
triggeredAtIndex    = 0; % The index in the overall buffer where the trigger occurred.

time = zeros(overviewBufferSize / downSampleRatio, 1);	% Array to hold time values
status.getStreamingLatestValuesStatus = PicoStatus.PICO_OK; % OK

while(hasAutoStopOccurred == PicoConstants.FALSE && status.getStreamingLatestValuesStatus == PicoStatus.PICO_OK)
    ready = PicoConstants.FALSE;
       while (ready == PicoConstants.FALSE)
       status.getStreamingLatestValuesStatus = invoke(streamingGroupObj, 'getStreamingLatestValues'); 
       ready = invoke(streamingGroupObj, 'isReady');
       end
    
    % Check for data
    [newSamples, startIndex] = invoke(streamingGroupObj, 'availableData');
    if (newSamples > 0)
        % Check if the scope has triggered.
        [triggered, triggeredAt] = invoke(streamingGroupObj, 'isTriggerReady');
        if (triggered == PicoConstants.TRUE)
            % Adjust trigger position as MATLAB does not use zero-based indexing.
            bufferTriggerPosition = triggeredAt + 1;
            fprintf('Triggered - index in buffer: %d\n', bufferTriggerPosition);
            hasTriggered = triggered;

            % Set the total number of samples at which the device triggered.
            triggeredAtIndex = totalSamples + bufferTriggerPosition;
        end

        previousTotal   = totalSamples;
        totalSamples    = totalSamples + newSamples;
        fprintf('Collected %d samples, startIndex: %d total: %d.\n', newSamples, startIndex, totalSamples);
        
        % Position indices of data in the buffer(s).
        firstValuePosn = startIndex + 1;
        lastValuePosn = startIndex + newSamples;
        
        % Convert data values to millivolts from the application buffer(s).
        bufferChAmV = adc2mv(pAppBufferChA.Value(firstValuePosn:lastValuePosn), channelARangeMv, maxADCCount);

        % Copy data into the final buffer(s).
        pBufferChAFinal.Value(previousTotal + 1:totalSamples) = bufferChAmV;
       
        % Clear variables for use again
        clear bufferChAmV;
        clear firstValuePosn;
        clear lastValuePosn;
        clear startIndex;
        clear triggered;
        clear triggerAt;
   end
   
    % Check if auto stop has occurred.
    hasAutoStopOccurred = invoke(streamingGroupObj, 'autoStopped');
end

fprintf('\n');

% STOP THE DEVICE & NUMBER OF SAMPLES COLLECTED
[status.stop] = invoke(ps5000aDeviceObj, 'ps5000aStop');
[status.noOfStreamingValues, numStreamingValues] = invoke(streamingGroupObj, 'ps5000aNoOfStreamingValues');
fprintf('Number of samples available after data collection: %u\n', numStreamingValues);

% Process data
if (totalSamples < finalBufferLength)
    pBufferChAFinal.Value(totalSamples + 1:end) = [];
end
% Retrieve data for the channels.
channelAFinal = pBufferChAFinal.Value();

writematrix(channelAFinal, 'EP_Ard1_raw.csv')
% writematrix(channelAFinal, 'EP_Ard2_raw.csv')

% Plot total data collected
finalFigure = figure('Name','PicoScope 5000 Series (A API) Example - Streaming Mode Capture', ...
    'NumberTitle','off');
finalFigureAxes = axes('Parent', finalFigure);
hold(finalFigureAxes, 'on');
grid(finalFigureAxes, 'on');
if (strcmp(sampleIntervalTimeUnitsStr, 'us'))
    xlabel(finalFigureAxes, 'Time (\us)');
else
    xLabelStr = strcat('Time (', sampleIntervalTimeUnitsStr, ')');
    xlabel(finalFigureAxes, xLabelStr);
end
ylabel(finalFigureAxes, 'Voltage (mV)');
hold(finalFigureAxes, 'off');
time = (double(sampleInterval) * double(downSampleRatio)) * (0:length(channelAFinal) - 1);

% Channel A
chAAxes = subplot(1,1,1); 
plot(chAAxes, time, channelAFinal, 'b');
xLabelStr = strcat('Time (', sampleIntervalTimeUnitsStr, ')');
xlabel(chAAxes, xLabelStr);
ylabel(chAAxes, 'Voltage (mV)');
title(chAAxes, 'Data acquisition on channel A (Final)');
grid(chAAxes, 'on');

% Disconnect device
disconnect(ps5000aDeviceObj);
delete(ps5000aDeviceObj);
