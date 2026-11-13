function out = compareTargetEccentricity(ex, opts)
% compareTargetEccentricity  Compare reward-closer/farther target eccentricity.
%
% out = compareTargetEccentricity(ex, opts)
%
% Target closeness is defined by instantaneous distance from the Gaussian
% reward center. Eccentricity is distance from screen center. Comparisons
% are paired within step and summarized once per trial so long trials do not
% receive extra weight. The switch table contains only direct, inferred
% physical-target switches (TLeft <-> TRight); reward-rank crossings while
% tracking the same target are never treated as switches.
%
% opts fields:
%   trialList          trials to include (default all)
%   hmmMethod          'smoothed' (default), 'filtered', or 'predictive'
%   hmmHardThreshold   two-state assignment threshold (default 0.9)
%   makePlot           create summary plot (default true)
%   transitionPreSec   event-locked time before switch (default 1.5 s)
%   transitionPostSec  event-locked time after switch (default 3.0 s)
%   transitionDtSec    interpolation interval; [] estimates it from steps

% Important outputs:
%   samples      one row per target-motion step
%   trials       paired trial-level means
%   comparison   paired trial-level test of farther-minus-closer eccentricity
%   switches     geometry at genuine physical-target switches

if nargin < 2 || isempty(opts), opts = struct(); end
opts = localDefaults(opts, struct( ...
    'trialList', [], 'hmmMethod', 'smoothed', ...
    'hmmHardThreshold', 0.9, 'makePlot', true, ...
    'transitionPreSec', 1.5, 'transitionPostSec', 3.0, ...
    'transitionDtSec', []));
opts.hmmMethod = validatestring(char(string(opts.hmmMethod)), ...
    {'smoothed','filtered','predictive'});

nTrials = numel(ex.Trials);
trialList = localTrialList(opts.trialList, nTrials);
rect = double(ex.setup.screenRect(:)');
if numel(rect) < 4 || any(~isfinite(rect(1:4)))
    error('compareTargetEccentricity:MissingScreenGeometry', ...
        'ex.setup.screenRect is required.');
end
screenCenter = [(rect(1)+rect(3))/2, (rect(2)+rect(4))/2];

sampleRows = cell(0,1);
switchRows = cell(0,1);
for trialNo = trialList(:)'
    T = ex.Trials(trialNo);
    [~, ~, tRel] = reconstructEyePx(ex, T, true, struct());
    if isempty(tRel), continue; end
    [x1,y1,x2,y2,stepIdx] = mapTargetsByStep(ex,T,tRel);
    [x1,y1,x2,y2] = localCanonicalize(x1,y1,x2,y2);
    valid = isfinite(stepIdx) & isfinite(x1) & isfinite(y1) & ...
        isfinite(x2) & isfinite(y2);
    if ~any(valid), continue; end

    raw = table(double(stepIdx(valid)),double(tRel(valid)),double(x1(valid)), ...
        double(y1(valid)),double(x2(valid)),double(y2(valid)), ...
        'VariableNames',{'step','timeSec','x1','y1','x2','y2'});
    [~,first] = unique(raw.step,'stable');
    S = sortrows(raw(first,:),'step');
    rewardCenter = double(getGaussianCenterPx(ex,T));
    rewardDist1 = hypot(S.x1-rewardCenter(1),S.y1-rewardCenter(2));
    rewardDist2 = hypot(S.x2-rewardCenter(1),S.y2-rewardCenter(2));
    ecc1 = px2deg(hypot(S.x1-screenCenter(1),S.y1-screenCenter(2)),ex.setup);
    ecc2 = px2deg(hypot(S.x2-screenCenter(1),S.y2-screenCenter(2)),ex.setup);
    closerId = nan(height(S),1);
    closerId(rewardDist1 < rewardDist2) = 1;
    closerId(rewardDist2 < rewardDist1) = 2;
    closerEcc = nan(height(S),1); fartherEcc = closerEcc;
    closerEcc(closerId==1)=ecc1(closerId==1);
    fartherEcc(closerId==1)=ecc2(closerId==1);
    closerEcc(closerId==2)=ecc2(closerId==2);
    fartherEcc(closerId==2)=ecc1(closerId==2);
    deltaEcc = fartherEcc-closerEcc;
    isPhysicalSwitch = false(height(S),1);
    sourceTarget = nan(height(S),1); destinationTarget=sourceTarget;
    switchType = strings(height(S),1); switchType(:)="";

    assigned = localHmmStates(T,S.step,opts);
    for k=2:height(S)
        if ismember(assigned(k-1),[1 2]) && ismember(assigned(k),[1 2]) && ...
                assigned(k-1)~=assigned(k)
            isPhysicalSwitch(k)=true;
            sourceTarget(k)=assigned(k-1); destinationTarget(k)=assigned(k);
            sourceRank = localRankOfTarget(sourceTarget(k),closerId(k-1));
            destinationRank = localRankOfTarget(destinationTarget(k),closerId(k));
            if sourceRank==1 && destinationRank==2
                switchType(k)="closer_to_farther";
            elseif sourceRank==2 && destinationRank==1
                switchType(k)="farther_to_closer";
            else
                switchType(k)="other_rank_configuration";
            end
        end
    end

    block = localTrialScalar(T,{'block','blockNo','session'});
    trialColumn = repmat(trialNo,height(S),1);
    blockColumn = repmat(block,height(S),1);
    rewardX = repmat(rewardCenter(1),height(S),1);
    rewardY = repmat(rewardCenter(2),height(S),1);
    sampleRows{end+1,1}=table(trialColumn,blockColumn,S.step,S.timeSec, ... %#ok<AGROW>
        rewardX,rewardY,rewardDist1,rewardDist2,ecc1,ecc2,closerId, ...
        closerEcc,fartherEcc,deltaEcc,assigned,isPhysicalSwitch, ...
        sourceTarget,destinationTarget,switchType, ...
        'VariableNames',{'trial','block','step','timeSec','rewardCenterXPx', ...
        'rewardCenterYPx','rewardDistanceTLeftPx','rewardDistanceTRightPx', ...
        'eccentricityTLeftDeg','eccentricityTRightDeg','closerTargetId', ...
        'closerEccentricityDeg','fartherEccentricityDeg', ...
        'fartherMinusCloserEccentricityDeg','hmmTargetState', ...
        'isPhysicalTargetSwitch','sourceTargetId','destinationTargetId','switchType'});
    if any(isPhysicalSwitch)
        switchRows{end+1,1}=sampleRows{end}(isPhysicalSwitch,:); %#ok<AGROW>
    end
end

samples = localVertcatOrEmpty(sampleRows);
switches = localVertcatOrEmpty(switchRows);
trials = localTrialSummary(samples);
comparison = localComparison(trials);
switchLocked = localSwitchLocked(samples,switches,opts);
figureHandle=[];
if logical(opts.makePlot)
    figureHandle=localPlot(trials,switches,comparison,switchLocked);
end
out=struct('samples',samples,'trials',trials,'comparison',comparison, ...
    'switches',switches,'switchLocked',switchLocked, ...
    'figure',figureHandle,'opts',opts, ...
    'meta',struct('closenessReference','Gaussian reward center', ...
    'eccentricityReference','screen center','screenCenterPx',screenCenter, ...
    'nTrials',height(trials),'nSteps',height(samples), ...
    'nPhysicalSwitches',height(switches)));
end

function assigned=localHmmStates(T,steps,opts)
assigned=nan(size(steps));
if ~isfield(T,'hmm') || ~isfield(T.hmm,opts.hmmMethod), return; end
H=T.hmm.(opts.hmmMethod);
[assigned,available]=assignHmmTrackingStateCoPs(H,steps,opts.hmmHardThreshold);
if ~available, assigned(:)=NaN; end
end

function rank=localRankOfTarget(targetId,closerId)
rank=NaN;
if ismember(targetId,[1 2]) && ismember(closerId,[1 2])
    rank=1+(targetId~=closerId); % 1=closer, 2=farther
end
end

function trials=localTrialSummary(samples)
names={'trial','block','nSteps','meanCloserEccentricityDeg', ...
    'meanFartherEccentricityDeg','meanDifferenceDeg'};
if isempty(samples), trials=array2table(nan(0,numel(names)),'VariableNames',names); return; end
ids=unique(samples.trial,'stable'); rows=nan(numel(ids),numel(names));
for i=1:numel(ids)
    q=samples(samples.trial==ids(i),:);
    rows(i,:)=[ids(i),q.block(1),sum(isfinite(q.fartherMinusCloserEccentricityDeg)), ...
        mean(q.closerEccentricityDeg,'omitnan'), ...
        mean(q.fartherEccentricityDeg,'omitnan'), ...
        mean(q.fartherMinusCloserEccentricityDeg,'omitnan')];
end
trials=array2table(rows,'VariableNames',names);
end

function result=localComparison(trials)
d=trials.meanDifferenceDeg; d=d(isfinite(d));
result=struct('nTrials',numel(d),'meanDifferenceDeg',mean(d,'omitnan'), ...
    'sdDifferenceDeg',std(d,0,'omitnan'),'semDifferenceDeg',NaN, ...
    'tStatistic',NaN,'degreesOfFreedom',NaN,'pValue',NaN, ...
    'testStatus',"fewer than two valid trial means", ...
    'confidenceIntervalDeg',[NaN NaN]);
if ~isempty(d), result.semDifferenceDeg=std(d,0)/sqrt(numel(d)); end
if numel(d)>=2
    result.degreesOfFreedom=numel(d)-1;
    if result.sdDifferenceDeg==0
        result.tStatistic=sign(result.meanDifferenceDeg)*Inf;
        if result.meanDifferenceDeg==0, result.tStatistic=0; end
    else
        result.tStatistic=result.meanDifferenceDeg/result.semDifferenceDeg;
    end
    % Two-sided Student-t p-value via the incomplete beta function. This
    % avoids requiring Statistics and Machine Learning Toolbox merely to
    % report the paired test.
    t2=result.tStatistic^2; df=result.degreesOfFreedom;
    if isinf(t2), result.pValue=0;
    else, result.pValue=betainc(df/(df+t2),df/2,0.5); end
    result.testStatus="paired t-test across trial means";
    if exist('tinv','file')==2
        critical=tinv(0.975,df);
        result.confidenceIntervalDeg=result.meanDifferenceDeg + ...
            [-1 1]*critical*result.semDifferenceDeg;
    end
end
end

function locked=localSwitchLocked(samples,switches,opts)
types=["closer_to_farther","farther_to_closer"];
dt=double(opts.transitionDtSec);
if isempty(dt)
    differences=[];
    if ~isempty(samples)
        trialIds=unique(samples.trial);
        for i=1:numel(trialIds)
            time=sort(samples.timeSec(samples.trial==trialIds(i)));
            differences=[differences;diff(time)]; %#ok<AGROW>
        end
    end
    differences=differences(isfinite(differences)&differences>0);
    dt=median(differences,'omitnan');
end
if ~isscalar(dt)||~isfinite(dt)||dt<=0,dt=0.1;end
time=-double(opts.transitionPreSec):dt:double(opts.transitionPostSec);
traces=nan(height(switches),numel(time));
eventType=strings(height(switches),1);
for i=1:height(switches)
    eventType(i)=switches.switchType(i);
    trialSamples=samples(samples.trial==switches.trial(i),:);
    [sampleTime,uniqueIdx]=unique(trialSamples.timeSec,'stable');
    sampleDelta=trialSamples.fartherMinusCloserEccentricityDeg(uniqueIdx);
    traces(i,:)=interp1(sampleTime,sampleDelta, ...
        switches.timeSec(i)+time,'linear',NaN);
end
meanByType=nan(2,numel(time)); nByType=zeros(2,1);
for j=1:2
    selected=eventType==types(j);
    meanByType(j,:)=mean(traces(selected,:),1,'omitnan');
    nByType(j)=sum(selected);
end
locked=struct('timeSec',time,'traces',traces,'eventType',eventType, ...
    'eventTypes',types,'meanByType',meanByType,'nByType',nByType, ...
    'dtSec',dt);
end

function fig=localPlot(trials,switches,comparison,switchLocked)
fig=figure('Color','w','Position',[100 30 760 1080]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
ax=nexttile; hold(ax,'on');
for i=1:height(trials)
    plot(ax,[1 2],[trials.meanCloserEccentricityDeg(i), ...
        trials.meanFartherEccentricityDeg(i)],'-','Color',[.75 .75 .75]);
end
scatter(ax,ones(height(trials),1),trials.meanCloserEccentricityDeg,22, ...
    [0.20 0.55 0.85],'filled','MarkerFaceAlpha',.45);
scatter(ax,2*ones(height(trials),1),trials.meanFartherEccentricityDeg,22, ...
    [0.90 0.45 0.15],'filled','MarkerFaceAlpha',.45);
xlim(ax,[.6 2.4]);xticks(ax,[1 2]);xticklabels(ax,{'reward-closer','reward-farther'});
ylabel(ax,'Target eccentricity (deg)');grid(ax,'on');title(ax,'Paired trial means');

ax=nexttile; d=trials.meanDifferenceDeg;
scatter(ax,ones(size(d)),d,25,[.25 .25 .25],'filled','MarkerFaceAlpha',.5); hold(ax,'on');
yline(ax,0,'k--'); errorbar(ax,1,comparison.meanDifferenceDeg, ...
    comparison.semDifferenceDeg,'o','Color',[.75 0 .2],'MarkerFaceColor',[.75 0 .2], ...
    'LineWidth',1.5); xlim(ax,[.65 1.35]);xticks(ax,1);
xticklabels(ax,{'farther - closer'});ylabel(ax,'Eccentricity difference (deg)');grid(ax,'on');
if comparison.nTrials<2
    testLabel=sprintf('Mean difference = %.3f deg; n = %d valid trial', ...
        comparison.meanDifferenceDeg,comparison.nTrials);
else
    testLabel=sprintf('Mean difference = %.3f deg, p = %.3g (n = %d trials)', ...
        comparison.meanDifferenceDeg,comparison.pValue,comparison.nTrials);
end
title(ax,testLabel);

ax=nexttile; hold(ax,'on'); types=["closer_to_farther","farther_to_closer"];
for j=1:2
    if isempty(switches), values=[]; else
        values=switches.fartherMinusCloserEccentricityDeg(switches.switchType==types(j));
    end
    scatter(ax,j*ones(size(values)),values,24,'filled','MarkerFaceAlpha',.4);
    if any(isfinite(values)), errorbar(ax,j,mean(values,'omitnan'), ...
            std(values,0,'omitnan')/sqrt(sum(isfinite(values))),'ko','MarkerFaceColor','k'); end
end
yline(ax,0,'k--');xlim(ax,[.6 2.4]);xticks(ax,[1 2]);
xticklabels(ax,{'closer -> farther','farther -> closer'});
ylabel(ax,'Farther - closer eccentricity (deg)');
xlabel(ax,'Genuine HMM physical-target switch');grid(ax,'on');
title(ax,'Target geometry at switch time');

ax=nexttile;hold(ax,'on');colors=lines(2);
labels=["closer -> farther","farther -> closer"];
for j=1:2
    plot(ax,switchLocked.timeSec,switchLocked.meanByType(j,:), ...
        'LineWidth',2,'Color',colors(j,:), ...
        'DisplayName',sprintf('%s (n=%d)',labels(j),switchLocked.nByType(j)));
end
xline(ax,0,'k--','HandleVisibility','off');yline(ax,0,'k:','HandleVisibility','off');
xlabel(ax,'Time from genuine HMM target switch (s)');
ylabel(ax,'Farther - closer eccentricity (deg)');grid(ax,'on');
legend(ax,'Location','best');title(ax,'Switch-locked target geometry');
sgtitle('Reward-relative target identity versus screen-centered eccentricity');
end

function tableOut=localVertcatOrEmpty(rows)
if isempty(rows), tableOut=table(); else, tableOut=vertcat(rows{:}); end
end

function [x1,y1,x2,y2]=localCanonicalize(x1,y1,x2,y2)
first=find(isfinite(x1)&isfinite(y1)&isfinite(x2)&isfinite(y2),1);
if ~isempty(first) && (x1(first)>x2(first) || ...
        (x1(first)==x2(first) && y1(first)>y2(first)))
    [x1,x2]=deal(x2,x1); [y1,y2]=deal(y2,y1);
end
end

function value=localTrialScalar(T,names)
value=NaN;
for i=1:numel(names)
    if isfield(T,names{i}) && isnumeric(T.(names{i})) && ~isempty(T.(names{i}))
        candidate=double(T.(names{i})(1));
        if isfinite(candidate),value=candidate;return;end
    end
end
end

function list=localTrialList(requested,nTrials)
if isempty(requested),list=1:nTrials;else,list=unique(double(requested(:)'));
    if any(~isfinite(list)|list~=round(list)|list<1|list>nTrials)
        error('compareTargetEccentricity:BadTrialList','Invalid opts.trialList.');
    end
end
end

function opts=localDefaults(opts,defaults)
names=fieldnames(defaults);
for i=1:numel(names)
    if ~isfield(opts,names{i}) || (isempty(opts.(names{i})) && ...
            ~strcmp(names{i},'trialList'))
        opts.(names{i})=defaults.(names{i});
    end
end
end
