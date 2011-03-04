function processedData = processGliderData(gliderData, options)
%PROCESSGLIDERDATA - Processes glider data 
%  This function processes glider data previously loaded by functions
%  like LOADSEGMENTDATA or LOADTRANSECTDATA.
%  Among other things, this functions converts position from NMEA to
%  decimal degrees, interpolates navigation (trajectory, pitch, etc),
%  Derives variables (salinity, density, ...), applies corrections, etc.
%
% Syntax: processedData = processGliderData(gliderData, options)
%
% Inputs:
%    gliderData - Structure returned by the function LOADTRANSECTDATA
%    options - Structure with several fields
%
% Outputs:
%    processedData - Structure with the computed timeseries
%
% Example:
%    processedData = processGliderData(gliderData, options)
%
% Other m-files required: m_lldist (from m_map toolbox)
%  - m_lldist (from m_map toolbox), geographical distance computation
%  - seawater toolbox, to manage hydrographic variables
% Subfunctions: none
% MAT-files required: none
%
% See also: LOADTRANSECTDATA, CORRECTTHERMALLAG
%
% Author: Bartolome Garau
% Work address: Parc Bit, Naorte, Bloc A 2ºp. pta. 3; Palma de Mallorca SPAIN. E-07121
% Author e-mail: tgarau@socib.es
% Website: http://www.socib.es
% Creation: 23-Feb-2011
%

    % Initialize output variable
    processedData = [];

%% Check input parameters
    % Get the data matrix and check its size
    data = gliderData.data;
    maxRows = size(data, 1);
    if maxRows <= 2,
        disp('No initial data to process');
        return;
    end;

    % Parse the processing options
    remain = textscan(options.salinityCorrected, '%s', 'Delimiter', '_');
    correctionTokens = remain{1};
%     remain = options.salinityCorrected;
%     correctionTokens = {};
%     while true
%         [currentToken, remain] = strtok(remain, '_');
%         if isempty(currentToken),  break;  end
%         correctionTokens = [correctionTokens; currentToken]; %#ok<AGROW>
%     end
    
    % Get the column definition: m_present_time, m_lon, ...
    strucContent = fieldnames(gliderData);
    for fieldIdx = 1:length(strucContent),
        fieldName = char(strucContent(fieldIdx));
        if (numel(gliderData.(fieldName)) == 1) && isnumeric(gliderData.(fieldName)), % if column definition
            fieldContent = gliderData.(fieldName);
            eval([fieldName, ' = ', num2str(fieldContent), ';']);
        end;
    end;
    clear structContent fieldName fieldIdx fieldContent;

    % Get time scale range. This will be the continous
    % range to interpolate the rest of variables
    if exist('m_present_time', 'var')
        time_col = m_present_time;
    elseif exist('sci_m_present_time', 'var')
        time_col = sci_m_present_time;
    else
        disp('No variable to use as time range');
        return;
    end;
    goodRows = (~isnan(data(:, time_col)));
    data = data(goodRows, :);
    data = sortrows(data, time_col);
    timeRange = data(:, time_col);

    % Transform lat and lon coords BEFORE interpolating,
    % from degrees and decimal minutes to decimal degrees
    if exist('m_gps_lat', 'var') && exist('m_gps_lon', 'var')
        lat_col = m_gps_lat;
        lon_col = m_gps_lon;
    elseif exist('m_lat', 'var') && exist('m_lon', 'var')
        lat_col = m_lat;
        lon_col = m_lon;
    else
        disp('No variables to use as lat/lon position');
        return;
    end;
    data(:, lat_col) = nmeaToDeg(data(:, lat_col));
    data(:, lon_col) = nmeaToDeg(data(:, lon_col));
    
    % Interpolate data in time if missing, coordinates and others
    varsRange = [lat_col, lon_col];
    if exist('m_pitch', 'var')
        varsRange = [varsRange, m_pitch];
    end;
    if exist('m_depth', 'var')
        varsRange = [varsRange, m_depth];
    end;

    % Loop through each variable and interpolate it
    for varIdx = varsRange,

        % Get the not nan values from the current variable
        currentVar = data(:, varIdx);
        notNanIdx  = find(~isnan(currentVar));
        numNotNan  = length(notNanIdx);

        % If it has values but not in all the range,
        % it needs to be interpolated.
        if and(numNotNan > 1, numNotNan < maxRows),
            varValues       = currentVar(notNanIdx);
            timeValues      = timeRange(notNanIdx);
            data(:, varIdx) = interp1(timeValues, varValues, timeRange);
        end;
    end;
    clear varValues varIdx timeValues currentVar numNotNan notNanIdx;

    % Trim the matrix where values could not be interpolated, that is,
    % denan original data (cut beginning and ending)
    % *Note: Any effect in loosing data without spatio-temporal reference?
    varsRange  = [time_col, lat_col, lon_col];
    containNan = isnan(data(:, varsRange));
    containNan = sum(containNan, 2);
    dsBadRows  = find((containNan > 0));
    dsGoodRows = find((containNan == 0));
    data       = data(dsGoodRows, :);
    disp(['Found ', num2str(length(dsBadRows)), ' records without spatio-temporal reference']);
    
    maxRows = length(dsGoodRows);
    if (maxRows <= 2),
        disp('No interpolated data to process');
        return;
    end;
    clear notNanRows containNan varsRange;
    
%% TIME BASE

    % Generate "time" timeseries
    timeserie.navTime = data(:, time_col);
    if exist('sci_m_present_time', 'var')
        timeserie.sciTime = data(:, sci_m_present_time);
    elseif exist('sci_ctd41cp_timestamp', 'var')
        timeserie.sciTime = data(:, sci_ctd41cp_timestamp);
    else
        disp('No science time found! Using navigation time');
        timeserie.sciTime = timeserie.navTime;
    end;
    % Remove nans from science time, assuming 
    % regular sampling was performed in time gaps    
    if isfield(timeserie, 'sciTime') && options.allowSciTimeFill
        timeserie.sciTime = fillScienceTime(timeserie.sciTime);
    end;
    
%% Put the rest of variables in vectors 

    % Generate "coordinate" timeseries
    timeserie.latitude  = data(:, lat_col);
    timeserie.longitude = data(:, lon_col);
 
    % Generate transects information based on waypoint changes
    if exist('c_wpt_lat', 'var') && exist('c_wpt_lon', 'var')
        wptLat    = nmeaToDeg(data(:, c_wpt_lat));
        wptLon    = nmeaToDeg(data(:, c_wpt_lon));
        transects = getTransects(timeserie.navTime, wptLon, wptLat);
    else
        disp('No waypoint vars found to identify transects');
        transects = [timeserie.navTime(1), timeserie.navTime(end)];
    end;
    
    if exist('m_pitch', 'var')
        timeserie.pitch = data(:, m_pitch);
        if all(isnan(timeserie.pitch))
            timeserie.pitch = 26 * pi / 180 * ones(size(timeserie.pitch));
        end;
    end;

    % Physics: Sea-Bird CTD41CP
    ctdAvailable = 0;
    if exist('sci_water_cond', 'var') && exist('sci_water_temp', 'var') && ...
            exist('sci_water_pressure', 'var')
        tmp = data(:, [sci_water_cond, sci_water_temp, sci_water_pressure]);
        if any(~isnan(tmp(:))) % if there is any data
            timeserie.conductivity  = data(:, sci_water_cond);
            timeserie.temperature  = data(:, sci_water_temp);
            timeserie.pressure = 10 * data(:, sci_water_pressure); % From bars to decibars
            ctdAvailable = 1;
        end;
    end;
    if ~ctdAvailable && exist('m_water_cond', 'var') && exist('m_water_temp', 'var') && ...
            exist('m_water_pressure', 'var')
        tmp = data(:, [m_water_cond, m_water_temp, m_water_pressure]);
        if any(~isnan(tmp(:))) % if there is any data
            timeserie.conductivity  = data(:, m_water_cond);
            timeserie.temperature  = data(:, m_water_temp);
            timeserie.pressure = 10 * data(:, m_water_pressure); % From bars to decibars
            ctdAvailable = 1;
        end;
    end;

%     % Optics: ocr504R (Satlantic OCR-504 Radiance configuration)
%     ocrAvailable = 0;
%     if exist('sci_ocr504I_irrad1', 'var') && exist('sci_ocr504I_irrad2', 'var') && ...
%             exist('sci_ocr504I_irrad3', 'var') && exist('sci_ocr504I_irrad4', 'var')
%         tmp = data(:, [sci_ocr504I_irrad1, sci_ocr504I_irrad2, sci_ocr504I_irrad3, sci_ocr504I_irrad4]);
%         if any(~isnan(tmp(:))) % if there is any data
%             timeserie.irradiance412nm = data(:, sci_ocr504I_irrad1);
%             timeserie.irradiance442nm = data(:, sci_ocr504I_irrad2);
%             timeserie.irradiance491nm = data(:, sci_ocr504I_irrad3);
%             timeserie.irradiance664nm = data(:, sci_ocr504I_irrad4);
%             ocrAvailable = 1;
%         end;
%     end;
% 
%     % Optics: bb3slo (wet labs bb3slo backscatter triplet sensor)
%     bb3Available = 0;
%     if exist('sci_bb3slo_b470_scaled', 'var') && exist('sci_bb3slo_b532_scaled', 'var') && ...
%             exist('sci_bb3slo_b660_scaled', 'var')
%         tmp = data(:, [sci_bb3slo_b470_scaled, sci_bb3slo_b532_scaled, sci_bb3slo_b660_scaled]);
%         if any(~isnan(tmp(:))) % if there is any data
%             timeserie.backscatter470 = data(:, sci_bb3slo_b470_scaled);
%             timeserie.backscatter532 = data(:, sci_bb3slo_b532_scaled);
%             timeserie.backscatter660 = data(:, sci_bb3slo_b660_scaled);
%             bb3Available = 1;
%         end;
%     end;
% 
%     % Optics: bbfl2s (wet labs bbfl2slo fluorometer / backscatter sensor)
%     bbfAvailable = 0;
%     if exist('sci_bbfl2s_bb_scaled', 'var') && exist('sci_bbfl2s_chlor_scaled', 'var') && ...
%             exist('sci_bbfl2s_cdom_scaled', 'var')
%         tmp = data(:, [sci_bbfl2s_bb_scaled, sci_bbfl2s_chlor_scaled, sci_bbfl2s_cdom_scaled]);
%         if any(~isnan(tmp(:))) % if there is any data
%             timeserie.backscatter = data(:, sci_bbfl2s_bb_scaled);
%             timeserie.chlorophyll = data(:, sci_bbfl2s_chlor_scaled);
%             timeserie.cdom        = data(:, sci_bbfl2s_cdom_scaled);
%             bbfAvailable = 1;
%         end;
%     end;

    % Optics: flntu (wet labs flntu fluorometer and turbidity sensor)
    flntuAvailable = 0;
    if exist('sci_flntu_chlor_units', 'var') && exist('sci_flntu_turb_units', 'var')
        tmp = data(:, [sci_flntu_chlor_units, sci_flntu_turb_units]);
        if any(~isnan(tmp(:))) && length(unique(tmp(~isnan(tmp)))) > 1% if there is any data
            timeserie.chlorophyll = data(:, sci_flntu_chlor_units);
            timeserie.turbidity   = data(:, sci_flntu_turb_units);
            flntuAvailable = 1;
        end;
    end;

    % Optics: Aanderaa Oxygen Optode 3835
    oxyAvailable = 0;
    if exist('sci_oxy3835_oxygen', 'var') && exist('sci_oxy3835_saturation', 'var')
        tmp = data(:, [sci_oxy3835_oxygen, sci_oxy3835_saturation]);
        if any(~isnan(tmp(:))) % if there is any data
            timeserie.oxygen            = data(:, sci_oxy3835_oxygen);
            timeserie.oxygen_saturation = data(:, sci_oxy3835_saturation);
            oxyAvailable = 1;
        end;
    end;

    % Get water currents processGliderDataDevelopmentinformation
    waterAvailable = 0;
    if exist('m_final_water_vx', 'var') && exist('m_final_water_vy', 'var') && ...
       exist('x_dr_state', 'var')
        waterColumns = [m_final_water_vx, m_final_water_vy, x_dr_state];
        tmp = data(:, waterColumns);
        if any(~isnan(tmp))
            areGood = double(~isnan(data(:, waterColumns)));
            waterDataIdx = find(sum(areGood, 2) > 0);
            waterInfo.time = data(waterDataIdx, time_col);
            waterInfo.lon  = data(waterDataIdx, lon_col);
            waterInfo.lat  = data(waterDataIdx, lat_col);
            waterInfo.m_final_water_vx = data(waterDataIdx, m_final_water_vx);
            waterInfo.m_final_water_vy = data(waterDataIdx, m_final_water_vy);
            waterInfo.x_dr_state = data(waterDataIdx, x_dr_state);
            waterAvailable = 1;
        end;
    end;
    
    % Distance over ground
    timeserie.distanceOverGround = ...
        [0; cumsum(m_lldist(timeserie.longitude, timeserie.latitude))];
    
%% Apply Pressure Filter
    if isfield(timeserie, 'pressure') && options.allowPressFilter
        timeserie.pressure = applyPressureFilter(...
            timeserie.sciTime, timeserie.pressure, options);
    end;

    if ctdAvailable
        % Physics (derived)
        timeserie.depth = sw_dpth(timeserie.pressure, timeserie.latitude);
        timeserie.salinity = sw_salt(10 * timeserie.conductivity / sw_c3515, timeserie.temperature, timeserie.pressure);
        timeserie.density = sw_dens(timeserie.salinity, timeserie.temperature, timeserie.pressure);
    end;

%% REMOVE DESYNCHRONIZED DATA
    % How well are the two timeseries (navigation/science) synchornized?
    if isfield(timeserie, 'navTime') && isfield(timeserie, 'sciTime')
        timeLag = abs(timeserie.navTime - timeserie.sciTime);
        samplingPeriod = median(diff(timeserie.navTime));
        lagThreshold = 2.5 * samplingPeriod;
        isSynchronized = (timeLag <= lagThreshold);
        disp(['Data collected every ', num2str(samplingPeriod), ' seconds (in average)']);
        disp(['Established threshold of ', num2str(lagThreshold), ' seconds']);
        disp(['Data synchronized: ', num2str(sum(isSynchronized)), ' records out of ', num2str(length(timeserie.navTime))]);
        if options.allowDesynchroDeletion
            strucContent = fieldnames(timeserie);
            for fieldIdx = 1:length(strucContent)
                currentFieldName = strucContent{fieldIdx};
                currentFieldContent = timeserie.(currentFieldName);
                timeserie.(currentFieldName) = currentFieldContent(isSynchronized);
            end;
        end;

    end;

    % Make depth timeserie continous for inflection point detection
    goodidx = find(~isnan(timeserie.depth));
    timeserie.continousDepth = interp1(...
        timeserie.sciTime(goodidx), timeserie.depth(goodidx),...
    	timeserie.sciTime);

    % Find inflection points:
    %timeserie.profile_index  = nan(size(timeserie.navTime));
    % where first derivative is zero (or changes its sign).
    firstDer      = diff(timeserie.continousDepth);
    dProd         = firstDer(2:end) .* firstDer(1:end-1);
    inflectionInd = [1; 1 + find(dProd <= 0); length(timeserie.continousDepth)];
%     % Eliminate consecutive points (due to noise, just in case).
%     diffInd       = diff(inflectionInd, 1);
%     inflectionInd = inflectionInd((diffInd > 5));
    % Remove inflection indexes that mark a "shallow" profile
    timeserie.profile_index = findProfiles(timeserie.depth, inflectionInd);
    
    maxCasts = max(timeserie.profile_index);

%     if options.debugPlot
%         plot(timeserie.navTime, timeserie.depth, 'k.-', ...
%              timeserie.navTime(inflectionInd), timeserie.depth(inflectionInd), 'ro');
%         set(gca, 'YDir', 'reverse');
%         try
%             print('-dpng', fullfile(options.debugPlotPath, 'inflectionPoints.png'));
%         catch ME
%             disp(ME.message);
%         end;
%         figure; clf; hold on;
%         plot(timeserie.sciTime(1:2:end), timeserie.depth(1:2:end), '.k-'); 
%         scatter(timeserie.sciTime(1:2:end), timeserie.depth(1:2:end), 30, timeserie.temperature(1:2:end), 'filled');
%         figure; clf; hold on;
%         plot(timeserie.sciTime(1:2:end), timeserie.depth(1:2:end), '.k-'); 
%         scatter(timeserie.sciTime(1:2:end), timeserie.depth(1:2:end), 30, timeserie.salinity(1:2:end), 'filled');
% 
% 
%         plot(processedData.sciTime, processedData.depth, '.k-'); hold on;
%         scatter(processedData.sciTime, processedData.depth, 30, processedData.temperature, 'filled');
%         scatter(processedData.sciTime, processedData.depth, 30, processedData.salinity, 'filled');
%         set(gca, 'YDir', 'reverse');
%         caxis([13.5, 14.5])
%         caxis([38, 38.2])
%         colorbar
%     end;    

%% SENSOR LAG PARAMETERS IDENTIFICATION
    if ctdAvailable && ismember('T', correctionTokens)
        timeserie.Tcor = nan(size(timeserie.navTime));
        if isfield(options, 'tempTimeConstant')
            TTimeConstant = options.tempTimeConstant;
        else
            TTimeConstant = findVariableTimeConstant(timeserie, 'temperature', options);
            disp(['Temperature time constant found (T): ', num2str(TTimeConstant)]);
            if isnan(TTimeConstant)
                disp('Will not perform T sensor lag correction');
                correctionTokens = setdiff(correctionTokens, 'T');
                timeserie = rmfield(timeserie, 'Tcor');
            end;
        end;
    end;

    if ctdAvailable && ismember('C', correctionTokens)
        timeserie.Ccor = nan(size(timeserie.navTime));
        if isfield(options, 'condTimeConstant')
            CTimeConstant = options.condTimeConstant;
        else
            CTimeConstant = findVariableTimeConstant(timeserie, 'conductivity', options);
            disp(['Conductivity time constant found (T): ', num2str(CTimeConstant)]);
            if isnan(CTimeConstant)
                disp('Will not perform C sensor lag correction');
                correctionTokens = setdiff(correctionTokens, 'C');
                timeserie = rmfield(timeserie, 'Ccor');
            end;
        end;
    end;

    
%% SENSOR LAG APPLICATION
% Loop through the list of profiles
    for prfIdx = 1:maxCasts

        % Get the range indexes for this profile
        profileIdxRange = find(timeserie.profile_index == prfIdx);
        
        % Check in this range where we have data from each sensor
        if ctdAvailable

            varsSet = {'T', 'C'};
            fieldsName = {'temperature', 'conductivity'};
            for varIdx = 1:length(varsSet)
                
                if ismember(varsSet{varIdx}, correctionTokens)
                    clear aProfile;
                    aProfile.time                 = timeserie.sciTime    (profileIdxRange);
                    aProfile.depth                = timeserie.depth      (profileIdxRange);
                    aProfile.(fieldsName{varIdx}) = timeserie.(fieldsName{varIdx})(profileIdxRange);
                    [aProfile, goodRows] = cleanProfile(aProfile);
                    newFieldName = [varsSet{varIdx}, 'cor'];
                    theTimeConstant = eval([varsSet{varIdx}, 'TimeConstant']);
                    aProfile.(newFieldName) = correctTimeResponse(...
                        aProfile.(fieldsName{varIdx}), aProfile.time, theTimeConstant);

                    timeserie.(newFieldName)(profileIdxRange(goodRows)) = aProfile.(newFieldName);
                    timeserie.(newFieldName) = timeserie.(newFieldName)(:);
                end;
            end;
        end;
    end;
    
%% THERMAL LAG PARAMS IDENTIFICATION
    if ctdAvailable && ismember('TH', correctionTokens)
        if isfield(options, 'thermalParams') && isfield(options, 'thermalParamsMeaning')
            correctionParams = options.thermalParams;
            correctionParamsMeaning = options.thermalParamsMeaning;
        else
            % Parameters adjusted within this dataset
            % data: alpha offset, alpha slope, tau offset, tau slope
            [correctionParams, correctionParamsMeaning] = findGliderCorrectionParams(timeserie, options);
            
            for rowIdx = 1:size(correctionParams, 1)
                disp(['Thermal params (a_o a_s t_o t_s): ',num2str(correctionParams(rowIdx, :))]);
                if any(isnan(correctionParams(rowIdx, :)))
                    disp('Problems found during Thermal Lag parameters identification');
                    correctionParams(rowIdx, :) = [];
                    correctionParamsMeaning{rowIdx} = [];
                end;
            end;
            if isempty(correctionParams)
                disp('Warning: Thermal lag correction will not be applied');
                correctionTokens = setdiff(correctionTokens, 'TH');
            end;
        end;
    end;
    
    if ctdAvailable && ismember('TH', correctionTokens)
        
        % Prepare timeseries for thermal lag corrected data
        for idx = 1:size(correctionParams, 1)
            newFieldNames = {'ptime', 'depth', 'temp', 'cond', 'pitch'};
            varsList = ['sciTime', 'depth', correctionParamsMeaning{idx}, 'pitch'];
            corFound = strfind(varsList, 'cor');
             salFieldName = 'salinity_corrected';
                for k = 1:length(corFound)
                    if ~isempty(corFound{k})
                        salFieldName = [salFieldName, '_', varsList{k}]; %#ok<AGROW>
                    end;
                end;
                salFieldName = [salFieldName, '_TH']; %#ok<AGROW>
            timeserie.(salFieldName) = nan(size(timeserie.navTime));
        end;

        % Loop through the profiles to apply the thermal lag correction
        for prfIdx = 1:maxCasts

            % Get the range indexes for this profile
            profileIdxRange = find(timeserie.profile_index == prfIdx);
            for idx = 1:size(correctionParams, 1)
                currentCorrectionParams = correctionParams(idx, :);
                varsList = ['sciTime', 'depth', correctionParamsMeaning{idx}, 'pitch'];
                [basicProfileData, goodRows] = buildCombinedProfile(timeserie, profileIdxRange, varsList, newFieldNames);
                if isfield(basicProfileData, 'conductivity')
                    basicProfileData.cond = basicProfileData.conductivity;
                elseif isfield(basicProfileData, 'Ccor')
                    basicProfileData.cond = basicProfileData.Ccor;
                end;
                if isfield(basicProfileData, 'temperature')
                    basicProfileData.temp = basicProfileData.temperature;
                elseif isfield(basicProfileData, 'Tcor')
                    basicProfileData.temp = basicProfileData.Tcor;
                end;
                
                corFound = strfind(varsList, 'cor');
                salFieldName = 'salinity_corrected';
                for k = 1:length(corFound)
                    if ~isempty(corFound{k})
                        salFieldName = [salFieldName, '_', varsList{k}]; %#ok<AGROW>
                    end;
                end;
                salFieldName = [salFieldName, '_TH']; %#ok<AGROW>

                if ~isempty(basicProfileData) 
                    correctedProfileData = correctThermalLag(basicProfileData, currentCorrectionParams);
                    cndr = 10 * basicProfileData.cond / sw_c3515;
                    timeserie.(salFieldName)(profileIdxRange(goodRows)) = ...
                        sw_salt (cndr, ...
                            correctedProfileData.tempInCell, timeserie.pressure(profileIdxRange(goodRows)));
                    timeserie.(salFieldName) = timeserie.(salFieldName)(:);
                end;
            end;
        end;
    end;


%% Quality control and quality assessment missing here
% Note need a Check plot - orig, sensorLagcorr, thermallagCorr

    % QUIRKS MODE FOR NOW
    varsList = fieldnames(timeserie);
    for varIdx = 1:length(varsList)
        currentFieldName = varsList{varIdx};
        switch currentFieldName
            case {'temperature', 'Tcor'}
                minVal = 10;
                maxVal = 40;
                passTest = true;
                
            case {'salinity', 'salinity_corrected_TH'}
                minVal = 2;
                maxVal = 40;
                passTest = true;
                
            otherwise
                passTest = false;
                
        end;
        
        if passTest
            varVector = timeserie.(currentFieldName);
            varVector(varVector < minVal) = nan;
            varVector(varVector > maxVal) = nan;
            timeserie.(currentFieldName) = varVector;
        end;
        
    end;
    % QUIRKS MODE FOR NOW
    
%% Build processed data structure

    % Introduce output values in a structure: timeserie + currents
    processedData = timeserie;
    processedData.timeseries = fieldnames(timeserie);
    
    % Note add our time constants corrected data into structure
    
    if exist('correctionParams', 'var')
        processedData.correctionParams = correctionParams;
    end;

    if exist('transects', 'var')
        processedData.transects = transects;
    end;
    
    if waterAvailable
        processedData.waterInfo  = waterInfo;
    end;
    
    if isfield(gliderData, 'source'),
        processedData.source = gliderData.source;
    end;
end
    
