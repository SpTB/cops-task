function [exOut,report]=applyPupilCorrectionsBySession(ex,opts)
% applyPupilCorrectionsBySession  Fit/apply pupil corrections by calibration group.
%
% Experimental sessions are matched to the most recent EyeCal file whose
% filename time is not later than the session filename time. Sessions that
% reuse the same calibration are pooled and receive one shared correction.
if nargin<2||isempty(opts),opts=struct();end
opts=localDefaults(opts,struct('posCorrected',true, ...
    'posCorrectionSource','calibration','posCorrectionModel',[], ...
    'posCorrectionOpts',struct(),'sacCor',false, ...
    'sacCorrectionSource','calibration','sacCorrectionTemplate',[], ...
    'sacCorrectionOpts',struct(),'animal','','date',''));
if ~isfield(ex,'Trials')||isempty(ex.Trials),error( ...
        'applyPupilCorrectionsBySession:BadEx','ex.Trials is required.');end
[sessions,trialSession]=localSessions(ex);
[calPaths,calMinutes]=localCalibrations(sessions);
groupKey=strings(height(sessions),1);matchedCal=strings(height(sessions),1);
for k=1:height(sessions)
    eligible=find(calMinutes<=sessions.startMinute(k));
    if isempty(eligible)
        % No earlier calibration can be justified: keep this session separate.
        groupKey(k)="session:"+sessions.sourcePath(k);
    else
        chosen=eligible(end);matchedCal(k)=calPaths(chosen);
        groupKey(k)="calibration:"+calPaths(chosen);
    end
end
[groups,~,sessionGroup]=unique(groupKey,'stable');
exOut=ex;rows=repmat(localEmptyRow(),numel(groups),1);
for groupNo=1:numel(groups)
    selectedSessions=find(sessionGroup==groupNo);
    selectedTrials=find(ismember(trialSession,selectedSessions));
    groupEx=ex;groupEx.Trials=ex.Trials(selectedTrials);
    cal=matchedCal(selectedSessions);cal=cal(strlength(cal)>0);
    if ~isempty(cal),cal=cal(1);else,cal="";end
    positionModel=[];
    if opts.posCorrected
        if ~isempty(opts.posCorrectionModel)
            positionModel=opts.posCorrectionModel;
        elseif strcmpi(opts.posCorrectionSource,'experimental')
            fitOpts=opts.posCorrectionOpts;fitOpts.makePlot=false;
            positionModel=fitPupilExperimentalPositionBias(groupEx,fitOpts);
        else
            if strlength(cal)==0
                error('applyPupilCorrectionsBySession:NoPriorCalibration', ...
                    'No calibration precedes session %s.', ...
                    sessions.sourcePath(selectedSessions(1)));
            end
            fitOpts=opts.posCorrectionOpts;fitOpts.eyeCalPaths=cal;fitOpts.makePlot=false;
            positionModel=fitPupilPositionBias(opts.animal,opts.date,fitOpts);
        end
        [groupEx,posReport]=applyPupilPositionBias(groupEx,positionModel);
    else
        posReport=table();
    end
    if opts.sacCor
        if ~isempty(opts.sacCorrectionTemplate)
            sacModel=opts.sacCorrectionTemplate;
        elseif strcmpi(opts.sacCorrectionSource,'experimental')
            sacOpts=opts.sacCorrectionOpts;sacOpts.makePlot=false;
            if ~isempty(positionModel),sacOpts.positionModel=positionModel;end
            % Estimate from the original group data; positionModel is applied
            % internally exactly once before kernel estimation.
            originalGroup=ex;originalGroup.Trials=ex.Trials(selectedTrials);
            sacModel=fitPupilExperimentalSaccadeKernel(originalGroup,sacOpts);
        else
            if strlength(cal)==0
                error('applyPupilCorrectionsBySession:NoPriorCalibration', ...
                    'No calibration precedes session %s.', ...
                    sessions.sourcePath(selectedSessions(1)));
            end
            sacOpts=opts.sacCorrectionOpts;sacOpts.makePlot=false;
            if ~isempty(positionModel)&&strcmpi(opts.posCorrectionSource,'calibration')
                sacOpts.calibrationModel=positionModel;
            else
                fitOpts=struct('eyeCalPaths',cal,'makePlot',false);
                sacOpts.calibrationModel=fitPupilPositionBias(opts.animal,opts.date,fitOpts);
            end
            sacModel=pupilEyeCalSaccades(opts.animal,opts.date,sacOpts);
        end
        [groupEx,sacReport]=applyPupilSaccadeCorrection(groupEx,sacModel);
    else
        sacReport=table();
    end
    exOut.Trials(selectedTrials)=groupEx.Trials;
    row=localEmptyRow();row.group=groupNo;row.calibrationPath=cal;
    row.sessionBlocks={sessions.block(selectedSessions)'};
    row.sessionPaths={sessions.sourcePath(selectedSessions)'};
    row.nTrials=numel(selectedTrials);
    if ~isempty(posReport)
        row.nPositionRight=sum(posReport.nRightCorrected);
        row.nPositionLeft=sum(posReport.nLeftCorrected);
    end
    if ~isempty(sacReport)
        row.nSaccades=sum(sacReport.nSaccades);
        row.nSaccadeRight=sum(sacReport.nRightCorrected);
        row.nSaccadeLeft=sum(sacReport.nLeftCorrected);
    end
    rows(groupNo)=row;
end
report=struct('scope','session','groups',struct2table(rows), ...
    'sessions',sessions,'positionSource',string(opts.posCorrectionSource), ...
    'saccadeSource',string(opts.sacCorrectionSource));
exOut.pupilCorrectionGroups=report;
end

function [sessions,trialSession]=localSessions(ex)
n=numel(ex.Trials);block=nan(n,1);path=strings(n,1);
for k=1:n
    T=ex.Trials(k);
    if isfield(T,'sessionInDay'),block(k)=double(T.sessionInDay);end
    if isfield(T,'sourceFilePath'),path(k)=string(T.sourceFilePath);end
end
if all(strlength(path)==0)
    error('applyPupilCorrectionsBySession:MissingSessionProvenance', ...
        ['Session-scoped correction requires Trials.sourceFilePath, normally ' ...
         'added by exportHMM/mergeCoPsHmmStruct. Use correctionScope=''day'' ' ...
         'for a standalone ex without this provenance.']);
end
[sourcePath,~,trialSession]=unique(path,'stable');
sessionBlock=nan(numel(sourcePath),1);startMinute=nan(numel(sourcePath),1);
for k=1:numel(sourcePath)
    values=block(trialSession==k);values=values(isfinite(values));
    if ~isempty(values),sessionBlock(k)=values(1);else,sessionBlock(k)=k;end
    startMinute(k)=localTimeFromName(sourcePath(k));
end
[~,order]=sort(startMinute);inverse=zeros(size(order));inverse(order)=1:numel(order);
trialSession=inverse(trialSession);
sessions=table(sessionBlock(order),sourcePath(order),startMinute(order), ...
    'VariableNames',{'block','sourcePath','startMinute'});
end

function [paths,minutes]=localCalibrations(sessions)
firstPath=char(sessions.sourcePath(1));dayFolder=fileparts(fileparts(firstPath));
listing=dir(fullfile(dayFolder,'**','*.EyeCal.mat'));
paths=string(fullfile({listing.folder},{listing.name}))';
minutes=arrayfun(@(p)localTimeFromName(p),paths);
[minutes,order]=sort(minutes);paths=paths(order);
end
function value=localTimeFromName(path)
[~,name]=fileparts(char(path));token=regexp(name,'_(\d{1,2})[._-](\d{2})','tokens','once');
if isempty(token),error('applyPupilCorrectionsBySession:UnknownFileTime', ...
        'Could not parse HH.MM from %s.',path);end
value=str2double(token{1})*60+str2double(token{2});
end
function row=localEmptyRow()
row=struct('group',nan,'calibrationPath',"",'sessionBlocks',{{}}, ...
    'sessionPaths',{{}},'nTrials',0,'nPositionRight',0,'nPositionLeft',0, ...
    'nSaccades',0,'nSaccadeRight',0,'nSaccadeLeft',0);
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults);for k=1:numel(f),if ~isfield(opts,f{k})||isempty(opts.(f{k})),opts.(f{k})=defaults.(f{k});end,end
end
