function out = eventDensityDays(animal, dateFrom, dateTo, analysis, opts)
% eventDensityDays  Internal multi-day collector for blink/reward density.
if nargin<5 || isempty(opts), opts=struct(); end
defaults=struct('minTrials',200,'type','dayMean','model','sm3', ...
    'block','all','makePlot',true,'failFast',false, ...
    'dataRoot','Y:\data\CoPs','hmmRoot',fullfile( ...
    'C:\Users\zajkowskiwk\OneDrive - National Institutes of Health', ...
    'cops_project','output','hmm'));
opts=localDefaults(opts,defaults);
opts.type=validatestring(char(string(opts.type)),{'dayMean','eventAgg'});
analysis=validatestring(char(string(analysis)),{'blink','reward','eccentricity'});
animal=localAnimal(animal);
jobs=localJobs(opts.hmmRoot,animal);
if isempty(jobs), error('eventDensityDays:NoFits','No SM3 fits found for %s.',animal); end
[firstDate,lastDate]=localRange(dateFrom,dateTo,jobs.dateValue);
jobs=jobs(jobs.dateValue>=firstDate & jobs.dateValue<=lastDate,:);
if isempty(jobs), error('eventDensityDays:NoDates','No fitted dates in range.'); end

collector={'minTrials','type','model','block','makePlot','failFast','dataRoot','hmmRoot'};
singleOpts=rmfield(opts,intersect(fieldnames(opts),collector)); singleOpts.makePlot=false;
mergeOpts=struct('model','sm3','block',opts.block,'dataRoot',opts.dataRoot, ...
    'hmmRoot',opts.hmmRoot);
audit=repmat(struct('animal',"",'date',"",'status',"",'nTrials',0, ...
    'nEvents',0,'message',"",'elapsedSec',NaN),height(jobs),1);
dayRows={}; eventTables={}; eventTraces={}; commonTime=[];
for d=1:height(jobs)
    label=char(jobs.date(d)); started=tic;
    audit(d).animal=string(animal); audit(d).date=string(label);
    try
        mergeOpts.predictionFile=char(jobs.predictionFile(d));
        ex=mergeCoPsHmmStruct(animal,label,mergeOpts);
        audit(d).nTrials=numel(ex.Trials);
        if audit(d).nTrials<opts.minTrials
            audit(d).status="below-min-trials";
            audit(d).message=sprintf('%d < %d trials',audit(d).nTrials,opts.minTrials);
            audit(d).elapsedSec=toc(started); continue
        end
        if strcmp(analysis,'blink')
            one=blinkHmmTransitions(ex,singleOpts); traces=one.traces.(one.meta.blinkDefinition);
        elseif strcmp(analysis,'reward')
            one=rewardHmmTransitions(ex,singleOpts); traces=one.rewardDensityHz;
        else
            one=eccentricityHmmTransitions(ex,singleOpts); traces=one.traces;
        end
        if isempty(commonTime), commonTime=one.timeSec(:)'; end
        traces=localResample(traces,one.timeSec,commonTime);
        events=one.events;
        audit(d).nEvents=height(events); audit(d).status="included";
        if ~isempty(events)
            events.animal=repmat(string(animal),height(events),1);
            events.date=repmat(string(label),height(events),1);
            eventTables{end+1,1}=events; eventTraces{end+1,1}=traces; %#ok<AGROW>
        end
        cats=localCategories();
        for k=1:numel(cats)
            selected=~isempty(events) & events.eventCategory==cats(k);
            row=table(string(animal),string(label),cats(k),sum(selected), ...
                {mean(traces(selected,:),1,'omitnan')}, ...
                'VariableNames',{'animal','date','eventCategory','nEvents','meanTrace'});
            if ~any(selected), row.meanTrace={nan(1,numel(commonTime))}; end
            dayRows{end+1,1}=row; %#ok<AGROW>
        end
    catch exception
        audit(d).status="failed";
        audit(d).message=string(exception.identifier)+": "+string(exception.message);
        if opts.failFast, rethrow(exception); end
    end
    audit(d).elapsedSec=toc(started);
    fprintf('[%d/%d] %s %s: %s, %d events\n',d,height(jobs),animal,label, ...
        audit(d).status,audit(d).nEvents);
end
audit=struct2table(audit);
if ~any(audit.status=="included")
    error('eventDensityDays:NoEligibleDays','No eligible days completed.');
end
if isempty(eventTables), events=table(); pooled=nan(0,numel(commonTime));
else, events=vertcat(eventTables{:}); pooled=vertcat(eventTraces{:}); end
dayMeans=vertcat(dayRows{:}); cats=localCategories();
grand=localGrand(cats,opts.type,dayMeans,events,pooled);
fig=[]; if opts.makePlot, fig=localPlot(commonTime,grand,analysis,animal,firstDate,lastDate); end
out=struct('animal',string(animal),'dateFrom',firstDate,'dateTo',lastDate, ...
    'type',string(opts.type),'timeSec',commonTime,'grand',grand, ...
    'dayMeans',dayMeans,'events',events,'traces',pooled,'audit',audit, ...
    'figure',fig,'opts',opts,'meta',struct('nEligibleDays',nnz(audit.status=="included"), ...
    'nEvents',height(events),'analysis',analysis));
end

function grand=localGrand(cats,type,days,events,traces)
rows=cell(numel(cats),1);
for k=1:numel(cats)
    if strcmp(type,'dayMean')
        selected=days.eventCategory==cats(k) & days.nEvents>0;
        units=vertcat(days.meanTrace{selected}); nEvents=sum(days.nEvents(selected));
    else
        selected=events.eventCategory==cats(k); units=traces(selected,:); nEvents=sum(selected);
    end
    n=sum(any(isfinite(units),2)); meanTrace=mean(units,1,'omitnan');
    sem=std(units,0,1,'omitnan')./sqrt(sum(isfinite(units),1));
    rows{k}=table(cats(k),n,nEvents,{meanTrace},{sem}, ...
        'VariableNames',{'eventCategory','nUnits','nEvents','meanTrace','semTrace'});
end
grand=vertcat(rows{:});
end

function fig=localPlot(time,grand,analysis,animal,firstDate,lastDate)
groups={{"nonTracking_to_tracking","tracking_to_nonTracking"}, ...
    {"closer_to_farther","farther_to_closer"}}; colors=lines(4);
fig=figure('Color','w','Position',[100 50 760 920]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
colorRows={[3 4],[1 2]};
for p=1:2
    ax=nexttile; hold(ax,'on');
    for j=1:2
        row=find(grand.eventCategory==groups{p}{j},1); if isempty(row),continue;end
        m=grand.meanTrace{row}; s=grand.semTrace{row};
        color=colors(colorRows{p}(j),:);
        fill(ax,[time fliplr(time)],[m-s fliplr(m+s)],color, ...
            'FaceAlpha',.15,'EdgeColor','none','HandleVisibility','off');
        plot(ax,time,m,'LineWidth',2,'Color',color,'DisplayName',groups{p}{j});
    end
    xline(ax,0,'k--','HandleVisibility','off'); grid(ax,'on');
    xlabel(ax,'Time from HMM transition (s)');
    if strcmp(analysis,'blink'), ylabel(ax,'Blink probability'); ylim(ax,[0 1]);
    elseif strcmp(analysis,'reward'), ylabel(ax,'Reward rate (releases/s)');
    else, ylabel(ax,'Gaze distance from screen center (deg)'); end
    legend(ax,'Location','best','Interpreter','none');
end
sgtitle(sprintf('%s %s, %s to %s',animal,analysis,string(firstDate,'yyyy.MM.dd'),string(lastDate,'yyyy.MM.dd')));
end

function y=localResample(x,old,new)
if isempty(x), y=nan(0,numel(new)); return; end
if numel(old)==numel(new) && max(abs(double(old(:))-double(new(:))))<1e-9, y=x; return; end
y=nan(size(x,1),numel(new)); for i=1:size(x,1),y(i,:)=interp1(old,x(i,:),new,'linear',NaN);end
end
function cats=localCategories()
cats=["nonTracking_to_tracking","tracking_to_nonTracking", ...
    "closer_to_farther","farther_to_closer"];
end
function opts=localDefaults(opts,defaults)
f=fieldnames(defaults); for i=1:numel(f),if ~isfield(opts,f{i})||isempty(opts.(f{i})),opts.(f{i})=defaults.(f{i});end,end
end
function animal=localAnimal(x)
x=lower(char(string(x))); if ismember(x,{'ka','kaki'}),animal='kaki';elseif ismember(x,{'ly','lychee'}),animal='lychee';else,error('Bad animal');end
end
function jobs=localJobs(root,animal)
folder=fullfile(char(root),'tidSM3','preds'); files=dir(fullfile(folder,'*_predictions.csv'));
expr=['^(kaki|lychee)_(\d{4}\.\d{2}\.\d{2})_targetidsens3_distance_gated_' ...
    'random_effect_cv(?:_v\d+)?_predictions\.csv$']; rows={};
for i=1:numel(files)
    t=regexp(files(i).name,expr,'tokens','once'); if isempty(t)||~strcmp(t{1},animal),continue;end
    rows(end+1,:)={string(t{2}),datetime(t{2},'InputFormat','yyyy.MM.dd'), ...
        string(fullfile(files(i).folder,files(i).name)),files(i).datenum}; %#ok<AGROW>
end
if isempty(rows),jobs=table();return;end
jobs=cell2table(rows,'VariableNames',{'date','dateValue','predictionFile','modified'});
jobs=sortrows(jobs,{'dateValue','modified'},{'ascend','descend'}); [~,i]=unique(jobs.date,'stable'); jobs=jobs(sort(i),:);
end
function [a,b]=localRange(x,y,dates)
year0=year(max(dates)); if isempty(x),a=min(dates);else,a=localDate(x,year0);end
if isempty(y),b=max(dates);else,b=localDate(y,year0);end
end
function d=localDate(x,year0)
s=strtrim(char(string(x))); normalized=regexprep(s,'[-_]','.');
try,d=datetime(normalized,'InputFormat','yyyy.MM.dd');return;catch,end
token=regexp(lower(s),['^(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|' ...
    'apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|' ...
    'oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s*([0-9]{1,2})$'], ...
    'tokens','once');
if isempty(token),error('eventDensityDays:BadDate','Use YYYY.MM.DD or jun02.');end
months={'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'};
monthNo=find(strcmp(token{1}(1:3),months),1);
d=datetime(year0,monthNo,str2double(token{2}));
end
