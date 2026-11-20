function tests = testCoPsPhotodiodeFlashx
% Simulate display flips and a delayed diode on a different, drifting clock.
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
addpath(fileparts(mfilename('fullpath')));
writeMock(folder,'Datapixx',[
    "function varargout=Datapixx(command,varargin)"
    "global COPS_FLASH_TEST"
    "s=COPS_FLASH_TEST; s.calls{end+1}=[{command} varargin]; COPS_FLASH_TEST=s;"
    "switch command"
    "case 'Open', s.open=true;"
    "case 'Close', s.open=false;"
    "case {'RegWrRd','RegWr'}, s.now=s.now+0.0002;"
    "case 'GetTime', varargout={1000+(s.now-0.0001-100)*s.dpRate};"
    "case 'GetAdcStatus'"
    "    count=0;"
    "    if isfinite(s.adcStart) && ~s.noSamples"
    "        stop=s.now; if ~s.running, stop=s.adcStop; end"
    "        count=max(0,min(s.maxFrames,floor((stop-s.adcStart)*s.rate))-s.samples);"
    "    end"
    "    varargout={struct('scheduleRunning',s.running,'freeRunning',s.freeRunning, ..."
    "        'dacAdcLoopback',s.loopback,'newBufferFrames',count,'numStreamOverflows',0)};"
    "case 'SetAdcSchedule', s.rate=varargin{2}; s.maxFrames=varargin{3};"
    "case 'StartAdcSchedule', s.running=true; s.adcStart=s.now; s.samples=0;"
    "case 'StopAdcSchedule', s.running=false; s.adcStop=s.now;"
    "case 'EnableAdcFreeRunning', s.freeRunning=true;"
    "case 'DisableAdcFreeRunning', s.freeRunning=false;"
    "case 'EnableDacAdcLoopback', s.loopback=true;"
    "case 'DisableDacAdcLoopback', s.loopback=false;"
    "case 'ReadAdcBuffer'"
    "    if s.failRead, error('FlashTest:Read','Simulated ADC error'); end"
    "    n=varargin{1}; assert(varargin{2}==-1);"
    "    ptb=s.adcStart+(s.samples+(0:n-1))/s.rate; v=2.5*ones(size(ptb));"
    "    for k=1:size(s.flips,1), v(ptb>=s.flips(k,1)+s.diodeDelay)=2.5+2.5*s.flips(k,2); end"
    "    varargout={v,1000+(ptb-100)*s.dpRate,false,false}; s.samples=s.samples+n;"
    "otherwise, error('FlashTest:Command','Unexpected DataPixx command');"
    "end"
    "COPS_FLASH_TEST=s;"
    "end"]);
writeMock(folder,'Screen',[
    "function varargout=Screen(command,varargin)"
    "global COPS_FLASH_TEST"
    "s=COPS_FLASH_TEST;"
    "switch lower(command)"
    "case 'preference'"
    "    varargout={s.skip}; if numel(varargin)>1, s.skip=varargin{2}; end"
    "case 'getflipinterval', varargout={1/60};"
    "case 'fillrect'"
    "    if numel(varargin)==2, s.background=varargin{2};"
    "    else, s.nextWhite=all(varargin{2}==255); s.patchColor=varargin{2}; end"
    "case 'flip'"
    "    when=0; if numel(varargin)>1, when=varargin{2}; end"
    "    t=ceil((max(when,s.now)+1e-9)*60)/60; missed=0;"
    "    if s.nextWhite && s.delayFirstWhite, t=t+1/60; missed=1/60; s.delayFirstWhite=false; end"
    "    s.now=t; s.flips(end+1,:)=[t s.nextWhite]; varargout={t,t,t,missed};"
    "    s.backgroundAtFlip(end+1)=s.background;"
    "    s.patchAtFlip(end+1)=s.patchColor;"
    "case 'close', s.windowOpen=false;"
    "otherwise, error('FlashTest:Screen','Unexpected Screen command');"
    "end"
    "COPS_FLASH_TEST=s;"
    "end"]);
writeMock(folder,'initDisplayx',[
    "function ex=initDisplayx(ex)"
    "global COPS_FLASH_TEST"
    "COPS_FLASH_TEST.displayOpens=COPS_FLASH_TEST.displayOpens+1;"
    "assert(ex.setup.fullscreen && ~ex.setup.showExperimenterOverlay);"
    "if COPS_FLASH_TEST.failDisplay, error('FlashTest:Display','Simulated display error'); end"
    "COPS_FLASH_TEST.windowOpen=true; COPS_FLASH_TEST.skip=0;"
    "ex.setup.window=7; ex.setup.screenNum=1; ex.setup.screenRect=[0 0 1920 1080];"
    "end"]);
writeMock(folder,'GetSecs',[
    "function t=GetSecs"
    "global COPS_FLASH_TEST"
    "assert(COPS_FLASH_TEST.now<120,'Flash test failed to finish'); t=COPS_FLASH_TEST.now;"
    "end"]);
writeMock(folder,'WaitSecs',[
    "function WaitSecs(varargin)"
    "global COPS_FLASH_TEST"
    "COPS_FLASH_TEST.now=COPS_FLASH_TEST.now+varargin{end};"
    "end"]);
writeMock(folder,'KbName',[
    "function key=KbName(name)"
    "if strcmp(name,'F4'), key=4; elseif strcmp(name,'ESCAPE'), key=5; else, key=[]; end"
    "end"]);
writeMock(folder,'KbCheck',[
    "function [down,t,keys]=KbCheck(device)"
    "global COPS_FLASH_TEST"
    "assert(device==-1); t=COPS_FLASH_TEST.now; keys=false(1,256);"
    "keys(4)=t>=COPS_FLASH_TEST.abortAt; down=any(keys);"
    "end"]);
for name={'HideCursor','ShowCursor'}
    writeMock(folder,name{1},["function "+name{1}+"(varargin)";"end"]);
end
writeMock(folder,'Eyelink',[
    "function varargout=Eyelink(varargin)"
    "error('FlashTest:EyeLink','The diagnostic must not use EyeLink');"
    "end"]);
addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Datapixx Screen initDisplayx GetSecs WaitSecs KbName KbCheck HideCursor ShowCursor Eyelink
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_FLASH_TEST
end

function setup(~)
global COPS_FLASH_TEST
COPS_FLASH_TEST=struct('calls',{{}},'now',100,'dpRate',1.0002, ...
    'open',false,'running',false,'freeRunning',true,'loopback',false, ...
    'adcStart',NaN,'adcStop',NaN,'rate',2000,'maxFrames',Inf,'samples',0, ...
    'noSamples',false,'failRead',false,'failDisplay',false,'windowOpen',false, ...
    'displayOpens',0,'skip',2,'flips',zeros(0,2),'nextWhite',false, ...
    'background',NaN,'backgroundAtFlip',[],'patchColor',NaN,'patchAtFlip',[], ...
    'diodeDelay',0.012,'delayFirstWhite',false,'abortAt',Inf);
end

function testDefaultFlashesAndADC0AreRecordedOnCommonClock(testCase)
global COPS_FLASH_TEST
data=invoke(testCase);
verifyTrue(testCase,data.completed);
verifyFalse(testCase,data.aborted);
verifyEqual(testCase,data.channel,0);
verifyEqual(testCase,data.patchRect,[1860 1020 1920 1080]);
verifyEqual(testCase,data.backgroundColor,128);
verifyEqual(testCase,data.patchLevels,[0 255]);
verifyEqual(testCase,COPS_FLASH_TEST.patchAtFlip,[0 repmat([255 0],1,5) 0]);
verifyEqual(testCase,COPS_FLASH_TEST.backgroundAtFlip, ...
    128*ones(size(COPS_FLASH_TEST.backgroundAtFlip)));
verifyEqual(testCase,data.actualOnsets,(1:5)','AbsTol',1e-10);
verifyEqual(testCase,data.actualOffsets,(1.2:1:5.2)','AbsTol',1e-10);
verifyEqual(testCase,data.events.white,repmat([true;false],5,1));
verifyEqual(testCase,data.events.plannedTime,reshape([1:5;1.2:1:5.2],[],1),'AbsTol',1e-10);
verifyEqual(testCase,data.ptbPerDatapixxSecond,1/COPS_FLASH_TEST.dpRate,'AbsTol',1e-9);
rising=find(diff(data.voltage)>2)+1;
verifyNumElements(testCase,rising,5);
verifyEqual(testCase,data.time(rising)'-data.actualOnsets, ...
    repmat(COPS_FLASH_TEST.diodeDelay,5,1),'AbsTol',1/data.sampleRate+1e-9);
verifyGreaterThan(testCase,data.clockStart.uncertainty,0);
verifyReleased(testCase);
end

function testCustomFlashTimesAndChannel(testCase)
data=invoke(testCase,'onsets',[0.1 0.4 0.7],'pulseDurationSecs',0.1,'tailSecs',0.1,'channel',6);
verifyEqual(testCase,data.channel,6);
verifyEqual(testCase,data.actualOnsets,[0.1;0.4;0.7],'AbsTol',1e-10);
verifyEqual(testCase,data.actualOffsets,[0.2;0.5;0.8],'AbsTol',1e-10);
verifyReleased(testCase);
end

function testComparisonPlotUsesAlignedVoltageSamples(testCase)
original=pwd;
oldVisible=get(groot,'DefaultFigureVisible');
restore=onCleanup(@() restoreGraphicsLocal(original,oldVisible)); %#ok<NASGU>
set(groot,'DefaultFigureVisible','off');
cd(testCase.TestData.folder);
evalc('data=checkCoPsPhotodiodeFlashx(onsets=0.1,pulseDurationSecs=0.1,tailSecs=0.1);');
f=findall(groot,'Type','figure','Name','Photodiode flash timing');
closePlot=onCleanup(@() delete(f(isgraphics(f)))); %#ok<NASGU>
verifyNumElements(testCase,f,1);
axesHandles=findall(f,'Type','axes');
verifyNumElements(testCase,axesHandles,2);
for ax=axesHandles'
    if strcmp(ax.YLabel.String,'ADC0 voltage (V)')
        trace=findobj(ax,'Type','line');
        verifyEqual(testCase,trace.XData,data.time);
        verifyEqual(testCase,trace.YData,data.voltage);
        verifyReleased(testCase);
        return
    end
end
verifyFail(testCase,'The aligned ADC voltage plot was not created.');
end

function testLateFlipIsLoggedInsteadOfAssumingRequestedOnset(testCase)
global COPS_FLASH_TEST
COPS_FLASH_TEST.delayFirstWhite=true;
data=invoke(testCase,'onsets',0.1,'pulseDurationSecs',0.2,'tailSecs',0.1);
verifyEqual(testCase,data.actualOnsets-0.1,1/60,'AbsTol',1e-10);
verifyGreaterThan(testCase,data.events.missed(1),0);
rise=find(diff(data.voltage)>2,1)+1;
verifyEqual(testCase,data.time(rise)-data.actualOnsets,COPS_FLASH_TEST.diodeDelay,'AbsTol',1/data.sampleRate);
end

function testF4DuringWhiteClosesPatchAndReturnsPartialRecording(testCase)
global COPS_FLASH_TEST
COPS_FLASH_TEST.abortAt=100.18;
data=invoke(testCase,'onsets',0.1,'pulseDurationSecs',0.2,'tailSecs',0.1);
verifyTrue(testCase,data.aborted);
verifyFalse(testCase,data.completed);
verifyNumElements(testCase,data.actualOnsets,1);
verifyEmpty(testCase,data.actualOffsets);
verifyLessThan(testCase,data.finalBaselineTime-data.actualOnsets,0.2);
verifyEqual(testCase,COPS_FLASH_TEST.flips(end,2),0);
verifyEqual(testCase,COPS_FLASH_TEST.patchAtFlip(end),0);
verifyReleased(testCase);
end

function testBusyADCDoesNotOpenDisplayOrStopExistingAcquisition(testCase)
global COPS_FLASH_TEST
COPS_FLASH_TEST.running=true;
verifyError(testCase,@() invoke(testCase),'checkCoPsPhotodiodeFlashx:AdcBusy');
verifyTrue(testCase,COPS_FLASH_TEST.running);
verifyEqual(testCase,COPS_FLASH_TEST.displayOpens,0);
commands=cellfun(@(c) c{1},COPS_FLASH_TEST.calls,'UniformOutput',false);
verifyFalse(testCase,any(strcmp(commands,'StopAdcSchedule')));
verifyFalse(testCase,COPS_FLASH_TEST.open);
end

function testInvalidAndSubRefreshSchedulesAreRejected(testCase)
verifyError(testCase,@() invoke(testCase,'onsets',[1 1.1]),'checkCoPsPhotodiodeFlashx:Timing');
verifyError(testCase,@() invoke(testCase,'onsets',1,'pulseDurationSecs',0.001),'checkCoPsPhotodiodeFlashx:Timing');
verifyReleased(testCase);
end

function testADCErrorClosesDisplayAndRestoresSettings(testCase)
global COPS_FLASH_TEST
COPS_FLASH_TEST.failRead=true;
verifyError(testCase,@() invoke(testCase),'FlashTest:Read');
verifyReleased(testCase);
end

function testDisplayErrorStillReleasesADC(testCase)
global COPS_FLASH_TEST
COPS_FLASH_TEST.failDisplay=true;
verifyError(testCase,@() invoke(testCase),'FlashTest:Display');
verifyReleased(testCase);
end

function testNoSamplesCannotBeReportedAsSuccessful(testCase)
global COPS_FLASH_TEST
COPS_FLASH_TEST.noSamples=true;
verifyError(testCase,@() invoke(testCase,'onsets',0.1,'tailSecs',0.1), ...
    'checkCoPsPhotodiodeFlashx:NoSamples');
verifyReleased(testCase);
end

function data=invoke(testCase,varargin)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
evalc('data=checkCoPsPhotodiodeFlashx(''showPlot'',false,varargin{:});');
end

function verifyReleased(testCase)
global COPS_FLASH_TEST
verifyFalse(testCase,COPS_FLASH_TEST.open);
verifyFalse(testCase,COPS_FLASH_TEST.running);
verifyFalse(testCase,COPS_FLASH_TEST.windowOpen);
verifyTrue(testCase,COPS_FLASH_TEST.freeRunning);
verifyFalse(testCase,COPS_FLASH_TEST.loopback);
verifyEqual(testCase,COPS_FLASH_TEST.skip,2);
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end

function restoreGraphicsLocal(folder,visible)
cd(folder);
set(groot,'DefaultFigureVisible',visible);
end
