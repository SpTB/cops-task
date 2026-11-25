function out = estimateCoPsOpticalHoldsx(bits,sampleTimes,voltage,refreshIntervalSec,anchorIndices,options)
% Estimate extra held refreshes from optical data and the known code order.
% No per-frame display timestamps are accepted or used. The nominal refresh
% rate locates the optical carrier; its rate and phase are fitted to the diode.
% A repeat-only hidden-state model allows held frames and missed light samples.
% Counts apply between the two selected reference-code rising-edge anchors.
% holdCount is the posterior median, minimizing absolute count error; the
% count on the single most likely complete path is viterbiHoldCount. A large
% family of individually less likely paths can support a different count.
% Posterior ranges condition on this model and its stated probabilities.
arguments
    bits {mustBeNumericOrLogical}
    sampleTimes double
    voltage double
    refreshIntervalSec (1,1) double {mustBePositive,mustBeFinite}
    anchorIndices (1,2) double {mustBeInteger,mustBePositive}
    options.missedLightProbability (1,1) double {mustBeGreaterThan(options.missedLightProbability,0),mustBeLessThan(options.missedLightProbability,1)} = .15
    options.falseLightProbability (1,1) double {mustBeGreaterThan(options.falseLightProbability,0),mustBeLessThan(options.falseLightProbability,1)} = .005
    options.holdProbability (1,1) double {mustBeGreaterThan(options.holdProbability,0),mustBeLessThan(options.holdProbability,1)} = .03
    options.posteriorSamples (1,1) double {mustBeInteger,mustBePositive} = 200
    options.seed (1,1) double {mustBeInteger,mustBeNonnegative} = 1
    options.frameProfile (1,1) logical = false
    options.boundaryIndices (1,:) double {mustBeInteger,mustBePositive} = []
    options.maxTrellisElements (1,1) double {mustBePositive,mustBeFinite} = 2e7
end
bits=double(bits(:)); s=sampleTimes(:); v=voltage(:);
assert(numel(s)==numel(v),'CoPsOpticalHolds:SizeMismatch','Supply one voltage per timestamp.');
good=isfinite(s)&isfinite(v); s=s(good); v=v(good);
assert(numel(s)>=100 && all(diff(s)>0),'CoPsOpticalHolds:Samples','Need increasing finite ADC samples.');
assert(all(bits==0|bits==1) && bits(1)==1,'CoPsOpticalHolds:Code','Supply the active code beginning with its white GO marker.');
n=numel(bits);
assert(all(options.boundaryIndices<=n),'CoPsOpticalHolds:Boundaries','Boundary indices must be within the code.');
assert(anchorIndices(1)<anchorIndices(2) && anchorIndices(2)<=n, ...
    'CoPsOpticalHolds:Anchors','Anchors must be increasing reference-code indices.');
rise=bits==1 & [true;bits(1:end-1)==0];
assert(all(rise(anchorIndices)),'CoPsOpticalHolds:Anchors','Both anchors must begin white-code runs.');
sorted=sort(v); baseline=median(sorted(1:round(.75*numel(v))));
noise=1.4826*median(abs(sorted(1:round(.75*numel(v)))-baseline));
high=sorted(round(.99*numel(v)));
assert(high-baseline>max(1e-6,10*noise),'CoPsOpticalHolds:Contrast','No clear positive optical contrast.');
threshold=max(baseline+6*noise,baseline+.2*(high-baseline));
weights=max(v-threshold,0); bright=weights>0;
assert(nnz(bright)>=16,'CoPsOpticalHolds:Carrier','Too few observed light samples.');
refTime=s(1); u=s-refTime; span=u(end)-u(1);
frequency=1/refreshIntervalSec;
grid=linspace(frequency*(1-.002),frequency*(1+.002),max(51,ceil(.004*frequency*span*12)+1));
carrier=@(f) abs(sum(weights(bright).*exp(2i*pi*f*u(bright))))/sum(weights(bright));
scores=arrayfun(carrier,grid); [~,best]=max(scores);
lo=grid(max(1,best-1)); hi=grid(min(numel(grid),best+1));
opticalHz=fminbnd(@(f)-carrier(f),lo,hi,optimset('TolX',1e-7,'Display','off'));
period=1/opticalHz;
phase=mod(angle(sum(weights(bright).*exp(2i*pi*opticalHz*u(bright))))/(2*pi*opticalHz),period);
bins=floor((u-phase)/period+.5);
% Retain the pretrial record: preparation can produce unrelated light before
% the GO marker. A free initial state must absorb it, rather than forcing that
% first flash to be the beginning of the saved code.
firstBin=min(bins); lastBin=max(bins);
use=bins>=firstBin;
peaks=accumarray(bins(use)-firstBin+1,v(use),[lastBin-firstBin+1 1],@max,NaN);
observation=double(peaks>=threshold); observation(~isfinite(peaks))=NaN;
m=numel(observation); slack=m-(n+1);
assert(slack>=0,'CoPsOpticalHolds:Duration','The optical recording is shorter than the submitted code.');
assert((slack+1)*(m+1)<=options.maxTrellisElements, ...
    'CoPsOpticalHolds:SizeLimit','Optical alignment exceeds the offline memory limit.');

% State i is the number of submitted code frames reached. Physical slot j
% either advances to i+1 or repeats i. d=j-i bounds the exact trellis width.
% Initial/final black states allow camera samples outside the active code.
code=[0;bits;0]; d=(0:slack)';
forward=-inf(slack+1,m+1); forward(1,1)=0;
viterbi=forward(:,1); pointer=false(slack+1,m+1);
logHold=log(options.holdProbability); logAdvance=log1p(-options.holdProbability);
startSlots=slack+1;
for j=1:m
    state=j-d;
    [stayProb,advanceProb]=transitionLogLocal(state,j,n,startSlots,logHold,logAdvance);
    emission=emissionLocal(observation(j),code(max(1,min(n+2,state+1))),options);
    emission(state==0)=0; % Pretrial light is outside the protocol.
    previous=forward(:,j);
    stay=[-Inf;previous(1:end-1)]+stayProb;
    advance=previous+advanceProb;
    value=logaddLocal(stay,advance)+emission;
    value(state<0|state>n+1)=-Inf;
    forward(:,j+1)=value;
    vs=[-Inf;viterbi(1:end-1)]+stayProb;
    va=viterbi+advanceProb;
    pointer(:,j+1)=vs>va;
    viterbi=max(vs,va)+emission;
    viterbi(state<0|state>n+1)=-Inf;
end
assert(isfinite(forward(end,end)),'CoPsOpticalHolds:Alignment','No complete monotonic code alignment.');
mapState=zeros(m,1); anchorSlots=nan(1,2); current=slack;
for j=m:-1:1
    state=j-current; mapState(j)=state;
    stayed=pointer(current+1,j+1);
    if ~stayed
        anchorSlots(anchorIndices==state)=j;
    end
    current=current-double(stayed);
end
assert(all(isfinite(anchorSlots)),'CoPsOpticalHolds:Anchors','Anchor entry was not found.');

% Exact conditional path samples from the forward probabilities; these retain
% the correlation between the two anchors instead of combining marginal CIs.
oldRng=rng; restore=onCleanup(@() rng(oldRng));
rng(options.seed,'twister');
current=slack*ones(options.posteriorSamples,1); sampledAnchors=nan(options.posteriorSamples,2);
if options.frameProfile
    entrySlots=zeros(options.posteriorSamples,n,'uint32');
end
for j=m:-1:1
    state=j-current;
    [stayProb,advanceProb]=transitionLogLocal(state,j,n,startSlots,logHold,logAdvance);
    offset=(j-1)*(slack+1);
    advance=forward(offset+current+1)+advanceProb;
    stay=-inf(size(current)); use=current>0;
    stay(use)=forward(offset+current(use))+stayProb(use);
    pStay=exp(stay-logaddLocal(stay,advance));
    stayed=rand(size(current))<pStay;
    for a=1:2
        hit=~stayed & state==anchorIndices(a); sampledAnchors(hit,a)=j;
    end
    if options.frameProfile
        hit=find(~stayed & state>=1 & state<=n);
        entrySlots(hit+(state(hit)-1)*options.posteriorSamples)=uint32(j);
    end
    current=current-double(stayed);
end
assert(all(isfinite(sampledAnchors(:))),'CoPsOpticalHolds:Posterior','A posterior path omitted an anchor.');
holdSamples=sampledAnchors(:,2)-sampledAnchors(:,1)-diff(anchorIndices);
countRange=percentileLocal(holdSamples,[.025 .975]);
predicted=code(mapState+1);
valid=isfinite(observation)&mapState>=anchorIndices(1)&mapState<=anchorIndices(2);
zero=valid&predicted==0; one=valid&predicted==1;
match=.5*(mean(observation(zero)==0)+mean(observation(one)==1));
out=struct('anchorIndices',anchorIndices,'holdCount',percentileLocal(holdSamples,.5), ...
    'viterbiHoldCount',diff(anchorSlots)-diff(anchorIndices), ...
    'posteriorMeanHolds',mean(holdSamples),'posteriorRange95',countRange, ...
    'countResolvedUnderModel',countRange(1)==countRange(2), ...
    'holdSamples',holdSamples,'anchorSlotSamples',sampledAnchors, ...
    'anchorSlots',anchorSlots,'anchorOpticalCentreTimes', ...
        refTime+phase+(firstBin+anchorSlots-1)*period, ...
    'opticalRefreshHz',opticalHz,'carrierCoherence',carrier(opticalHz), ...
    'nominalRefreshHz',frequency,'thresholdV',threshold,'matchFraction',match, ...
    'alignmentReliable',match>=.85 && carrier(opticalHz)>=.1, ...
    'sampleIntervalSec',median(diff(s)),'referenceFrameCount',n, ...
    'physicalSlotTimes',refTime+phase+(firstBin+(0:m-1)')*period, ...
    'physicalSlotPeaksV',peaks,'observedBits',observation,'mapCodeIndex',mapState, ...
    'options',options);
if options.frameProfile
    assert(all(entrySlots(:)>0),'CoPsOpticalHolds:Posterior','A sampled path omitted code frames.');
    holds=diff(double(entrySlots),1,2)-1;
    sortedHolds=sort(holds,1);
    q=max(1,min(options.posteriorSamples,round(1+(options.posteriorSamples-1)*[.025 .5 .975])));
    out.frameProfile=struct('lowerHolds',[sortedHolds(q(1),:) NaN]', ...
        'medianHolds',[sortedHolds(q(2),:) NaN]', ...
        'upperHolds',[sortedHolds(q(3),:) NaN]', ...
        'meanHolds',[mean(holds,1) NaN]', ...
        'probabilityHeld',[mean(holds>0,1) NaN]', ...
        'boundaryIndices',options.boundaryIndices, ...
        'boundarySlotSamples',double(entrySlots(:,options.boundaryIndices)));
end
end

function [stay,advance]=transitionLogLocal(state,j,n,startSlots,logHold,logAdvance)
stay=logHold*ones(size(state)); advance=logAdvance*ones(size(state));
stay(state==n+1)=0; advance(state<=0)=-Inf;
if j<=startSlots
    hazard=1/(startSlots-j+1);
    stay(state==0)=log1p(-hazard); advance(state==1)=log(hazard);
else
    stay(state==0)=-Inf; advance(state==1)=-Inf;
end
end

function value=emissionLocal(observed,bit,options)
if isnan(observed), value=zeros(size(bit)); return; end
if observed
    value=log(options.falseLightProbability)*ones(size(bit));
    value(bit==1)=log1p(-options.missedLightProbability);
else
    value=log1p(-options.falseLightProbability)*ones(size(bit));
    value(bit==1)=log(options.missedLightProbability);
end
end

function out=logaddLocal(a,b)
big=max(a,b); out=-inf(size(big)); good=isfinite(big);
out(good)=big(good)+log1p(exp(-abs(a(good)-b(good))));
end

function value=percentileLocal(x,p)
x=sort(x); value=x(max(1,min(numel(x),round(1+(numel(x)-1)*p))));
value=value(:)';
end
