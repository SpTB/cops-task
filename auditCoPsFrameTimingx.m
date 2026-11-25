function ex = auditCoPsFrameTimingx(ex,options)
% Offline VBL/optical audit. Does not acquire data or change task settings.
% Results describe intervals AFTER the corresponding flip_info row. Optical
% fits receive code order and raw ADC data, never individual VBL timestamps.
arguments
    ex (1,1) struct
    options.posteriorSamples (1,1) double {mustBeInteger,mustBePositive} = 100
    options.windowFrames (1,1) double {mustBeInteger,mustBePositive} = 64
    options.minPayloadFrames (1,1) double {mustBeInteger,mustBePositive} = 128
    % Columns: hold probability, missed-light probability. Union the ranges
    % across these alternatives; a single best path is not frame evidence.
    options.modelSettings (:,2) double = [.03 .15; .005 .30; .15 .05]
    options.verbose (1,1) logical = true
end
assert(~isempty(options.modelSettings) && all(options.modelSettings(:)>0 & options.modelSettings(:)<1), ...
    'CoPsFrameAudit:Models','Model probabilities must lie strictly between zero and one.');
started=tic;
totals=struct('trials',0,'opticalTrials',0,'unavailableTrials',0, ...
    'vblExtraRefreshes',0,'comparedVblExtraRefreshes',0,'photEstimatedExtraRefreshes',0, ...
    'comparedIntervals',0,'goIntervals',0,'missedFrames',0,'missVBLFrames',0, ...
    'missPhotFrames',0,'flaggedFrames',0,'windowSupportedVBLFrames',0,'invalidVBLIntervals',0);
if isfield(ex,'Trials')
    for k=1:numel(ex.Trials)
        tr=ex.Trials(k);
        audit=vblAuditLocal(tr);
        try
            audit=opticalAuditLocal(audit,tr,options,k);
        catch err
            audit.status='opticalUnavailable';
            audit.reason=err.identifier;
            audit.message=err.message;
        end
        ex.Trials(k).frameAudit=audit;
        totals.trials=totals.trials+1;
        totals.opticalTrials=totals.opticalTrials+strcmp(audit.status,'complete');
        totals.unavailableTrials=totals.unavailableTrials+~strcmp(audit.status,'complete');
        totals.vblExtraRefreshes=totals.vblExtraRefreshes+sum(audit.vblMissCount(audit.inGO),'omitnan');
        totals.goIntervals=totals.goIntervals+nnz(audit.inGO);
        totals.invalidVBLIntervals=totals.invalidVBLIntervals+nnz(audit.inGO & ~isfinite(audit.vblMissCount));
        for name={'missed','missVBL','missPhot','flagged'}
            field=[name{1} 'Frames']; totals.(field)=totals.(field)+nnz(audit.(name{1}));
        end
        totals.windowSupportedVBLFrames=totals.windowSupportedVBLFrames+nnz(audit.windowSupportedMissed);
        if ~isempty(audit.windows)
            totals.comparedVblExtraRefreshes=totals.comparedVblExtraRefreshes+sum(audit.windows.vblMissCount,'omitnan');
            totals.photEstimatedExtraRefreshes=totals.photEstimatedExtraRefreshes+sum(audit.windows.photMedianCount);
            totals.comparedIntervals=totals.comparedIntervals+sum(audit.windows.endFrame-audit.windows.startFrame);
        end
        if options.verbose && mod(k,25)==0
            fprintf('Frame audit: %d/%d trials processed.\n',k,numel(ex.Trials));
        end
    end
end
ex.frameAudit=struct('schemaVersion',1,'status','complete', ...
    'createdAt',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
    'elapsedSec',toc(started),'options',options,'summary',totals, ...
    'intervalConvention','Row i describes extra holds after flip_info(i), before flip_info(i+1). Last row is unassessed.', ...
    'scope','GO intervals only; final active-to-syncOffTime interval is excluded.', ...
    'labels','missed=both positive; missVBL=VBL positive and optical upper bound zero; missPhot=optical lower bound positive and VBL zero.', ...
    'uncertainty','Optical bounds unite conditional 95% ranges across saved model settings; they are not absolute error guarantees. Window support does not locate a miss within identical bits.');
if options.verbose
    fprintf('Frame audit saved in ex.frameAudit and Trials.frameAudit: VBL %g; compared VBL %g / optical estimate %g; %d flagged intervals.\n', ...
        totals.vblExtraRefreshes,totals.comparedVblExtraRefreshes, ...
        totals.photEstimatedExtraRefreshes,totals.flaggedFrames);
end
end

function a=vblAuditLocal(tr)
n=0; if isfield(tr,'flip_info'), n=size(tr.flip_info,1); end
a=struct('schemaVersion',1,'status','opticalUnavailable','reason','','message','', ...
    'inGO',false(n,1),'vblMissCount',nan(n,1), ...
    'photMedianCount',nan(n,1),'photLowerCount',nan(n,1),'photUpperCount',nan(n,1), ...
    'photCompared',false(n,1),'photUncertain',true(n,1), ...
    'missed',false(n,1),'missVBL',false(n,1),'missPhot',false(n,1), ...
    'flagged',false(n,1),'countDisagreement',false(n,1), ...
    'windowSupportedMissed',false(n,1),'windowIndex',zeros(n,1,'uint32'), ...
    'classification',repmat("outsideGO",n,1),'windows',table(), ...
    'modelDiagnostics',table(),'refreshIntervalSec',NaN);
ifi=NaN;
if isfield(tr,'displayRefreshIntervalSec') && isscalar(tr.displayRefreshIntervalSec)
    ifi=double(tr.displayRefreshIntervalSec);
elseif isfield(tr,'sync') && isstruct(tr.sync) && isfield(tr.sync,'refreshIntervalSec')
    ifi=double(tr.sync.refreshIntervalSec);
end
a.refreshIntervalSec=ifi;
if n<2 || ~isscalar(ifi) || ~isfinite(ifi) || ifi<=0
    a.reason='CoPsFrameAudit:NoVBL'; return
end
active=false(n,1);
if isfield(tr,'frameSyncPhase') && numel(tr.frameSyncPhase)==n && any(tr.frameSyncPhase>0)
    active=tr.frameSyncPhase(:)>0;
elseif isfield(tr,'frameState') && numel(tr.frameState)==n && ...
        isfield(tr,'frameStateLookup') && isfield(tr.frameStateLookup,'GO')
    active=tr.frameState(:)==tr.frameStateLookup.GO;
end
a.inGO(1:n-1)=active(1:n-1)&active(2:n);
dt=diff(double(tr.flip_info(:,1))); valid=isfinite(dt)&dt>0;
count=nan(n-1,1); count(valid)=max(0,round(dt(valid)/ifi)-1);
a.vblMissCount(1:n-1)=count;
a.classification(a.inGO)="unassessed";
a.flagged=a.inGO & (a.vblMissCount>0 | ~isfinite(a.vblMissCount));
a.classification(a.flagged)="flagged";
end

function a=opticalAuditLocal(a,tr,o,seed)
assert(isfield(tr,'sync') && isstruct(tr.sync) && isfield(tr.sync,'mode') && strcmp(tr.sync.mode,'binary'), ...
    'CoPsFrameAudit:NotBinary','Independent optical comparison requires binary sync.');
n=numel(a.inGO);
assert(isfield(tr,'frameSyncPhase') && numel(tr.frameSyncPhase)==n && ...
    isfield(tr,'frameSyncBit') && numel(tr.frameSyncBit)==n, ...
    'CoPsFrameAudit:CodeMetadata','Missing or inconsistent code metadata.');
active=find(tr.frameSyncPhase(:)>0); phase=tr.frameSyncPhase(active); phase=phase(:);
bits=double(tr.frameSyncBit(active)); bits=bits(:);
assert(nnz(phase==3)>=o.minPayloadFrames,'CoPsFrameAudit:ShortCode','Not enough payload for an optical audit.');
assert(all(diff(active)==1) && all(bits==0|bits==1), ...
    'CoPsFrameAudit:CodeMetadata','Active code must be contiguous and binary.');
rises=find(bits==1 & [true;bits(1:end-1)==0] & phase==3);
rich=false(size(rises));
for j=1:numel(rises)
    i=rises(j); rich(j)=i>33 && i<=numel(bits)-15 && nnz(diff(bits(max(1,i-15):i+15)))>=8;
end
rises=rises(rich);
assert(numel(rises)>=2,'CoPsFrameAudit:NoAnchors','Not enough distinctive code context.');
boundaries=rises(1);
for i=rises(:)'
    if i-boundaries(end)>=o.windowFrames, boundaries(end+1)=i; end %#ok<AGROW>
end
if boundaries(end)~=rises(end)
    if numel(boundaries)>1 && rises(end)-boundaries(end)<o.windowFrames/2
        boundaries(end)=rises(end);
    else
        boundaries(end+1)=rises(end);
    end
end
assert(numel(boundaries)>=2,'CoPsFrameAudit:NoAnchors','The optical span is too short.');
assert(isfield(tr,'adcChannels') && isfield(tr.sync,'physicalChannel'), ...
    'CoPsFrameAudit:NoADC','Missing physical channel metadata.');
row=find(tr.adcChannels==tr.sync.physicalChannel,1);
assert(~isempty(row),'CoPsFrameAudit:NoADC','The diode channel was not acquired.');
record=struct();
if isfield(tr,'Analog') && isstruct(tr.Analog) && isfield(tr.Analog,'t') && ~isempty(tr.Analog.t)
    record=tr.Analog;
elseif isfield(tr,'Eye') && isstruct(tr.Eye)
    record=tr.Eye;
end
assert(all(isfield(record,{'t','v','n'})) && record.n>0 && row<=size(record.v,1), ...
    'CoPsFrameAudit:NoADC','No recorded photodiode samples.');
assert(record.n<=numel(record.t) && record.n<=size(record.v,2), ...
    'CoPsFrameAudit:NoADC','ADC sample count exceeds the recorded arrays.');
s=double(record.t(1:record.n)); v=double(record.v(row,1:record.n));
modelRows=struct([]); windowLower=[]; windowUpper=[];
for model=1:size(o.modelSettings,1)
    % No VBL timestamp vector or VBL-derived miss count enters this call.
    fit=estimateCoPsOpticalHoldsx(bits,s,v,a.refreshIntervalSec,boundaries([1 end]), ...
        holdProbability=o.modelSettings(model,1),missedLightProbability=o.modelSettings(model,2), ...
        posteriorSamples=o.posteriorSamples,seed=seed,frameProfile=true,boundaryIndices=boundaries);
    profile=fit.frameProfile;
    r=struct('holdProbability',o.modelSettings(model,1),'missedLightProbability',o.modelSettings(model,2), ...
        'reliable',fit.alignmentReliable,'balancedMatch',fit.matchFraction, ...
        'opticalHz',fit.opticalRefreshHz,'carrierCoherence',fit.carrierCoherence);
    modelRows=[modelRows r]; %#ok<AGROW>
    wc=diff(profile.boundarySlotSamples,1,2)-diff(boundaries);
    sorted=sort(wc,1); q=max(1,round(1+(o.posteriorSamples-1)*[.025 .5 .975]));
    if model==1
        lower=profile.lowerHolds; upper=profile.upperHolds;
        medianCount=profile.medianHolds;
        windowMedian=sorted(q(2),:)'; windowLower=sorted(q(1),:)'; windowUpper=sorted(q(3),:)';
    else
        lower=min(lower,profile.lowerHolds); upper=max(upper,profile.upperHolds);
        windowLower=min(windowLower,sorted(q(1),:)'); windowUpper=max(windowUpper,sorted(q(3),:)');
    end
end
a.modelDiagnostics=struct2table(modelRows);
if ~all(a.modelDiagnostics.reliable)
    a.reason='CoPsFrameAudit:UnreliableAlignment';
    a.message='An alternate optical model did not align reliably.';
    return
end
idx=active(boundaries(1):boundaries(end)-1);
a.photMedianCount(idx)=medianCount(boundaries(1):boundaries(end)-1);
a.photLowerCount(idx)=lower(boundaries(1):boundaries(end)-1);
a.photUpperCount(idx)=upper(boundaries(1):boundaries(end)-1);
a.photCompared(idx)=true;
a.photUncertain(idx)=a.photLowerCount(idx)~=a.photUpperCount(idx);
compared=a.photCompared & a.inGO & isfinite(a.vblMissCount);
a.missed=compared & a.vblMissCount>0 & a.photLowerCount>0;
a.missVBL=compared & a.vblMissCount>0 & a.photUpperCount==0;
a.missPhot=compared & a.vblMissCount==0 & a.photLowerCount>0;
a.countDisagreement=compared & (a.vblMissCount<a.photLowerCount | a.vblMissCount>a.photUpperCount);
a.flagged=a.flagged | (compared & (a.photUncertain | a.countDisagreement));
% A VBL miss with positive, precisely counted optical evidence is resolved.
a.flagged(a.missed & ~a.photUncertain & ~a.countDisagreement)=false;
a.flagged(a.missVBL | a.missPhot)=true;
a.classification(compared & ~a.flagged)="ok";
a.classification(a.flagged)="flagged";
a.classification(a.missed)="missed";
a.classification(a.missVBL)="missVBL";
a.classification(a.missPhot)="missPhot";
windowRows=struct([]);
for j=1:numel(boundaries)-1
    first=active(boundaries(j)); last=active(boundaries(j+1));
    indices=first:last-1; vc=sum(a.vblMissCount(indices));
    lc=windowLower(j); uc=windowUpper(j);
    label="flagged";
    if isfinite(vc)
        if vc>0 && lc>0, label="missed";
        elseif vc>0 && uc==0, label="missVBL";
        elseif vc==0 && lc>0, label="missPhot";
        elseif vc==0 && uc==0, label="ok";
        end
    end
    exact=isfinite(vc) && vc==lc && vc==uc;
    r=struct('startFrame',first,'endFrame',last,'vblMissCount',vc, ...
        'photMedianCount',windowMedian(j),'photLowerCount',lc,'photUpperCount',uc, ...
        'classification',label,'exactCountAgreement',exact, ...
        'flagged',~exact,'startCodeIndex',boundaries(j),'endCodeIndex',boundaries(j+1));
    windowRows=[windowRows r]; %#ok<AGROW>
    a.windowIndex(indices)=uint32(j);
    if exact && vc>0
        a.windowSupportedMissed(indices)=a.vblMissCount(indices)>0;
    end
end
a.windows=struct2table(windowRows);
a.status='complete'; a.reason=''; a.message='';
end
