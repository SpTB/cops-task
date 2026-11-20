function tests = testCoPsPhotodiodeReadoutx
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
testCase.TestData.originalPath=path;
addpath(fileparts(mfilename('fullpath')));
writeMock(folder,'Datapixx',[
    "function varargout=Datapixx(command,varargin)"
    "global COPS_DIODE_TEST"
    "s=COPS_DIODE_TEST; s.calls{end+1}=[{command} varargin]; COPS_DIODE_TEST=s;"
    "switch command"
    "case 'Open', s.open=true;"
    "case 'Close', s.open=false;"
    "case 'GetAdcStatus'"
    "    if s.failStatus, error('DiodeTest:Status','ADC status failed'); end"
    "    varargout={struct('scheduleRunning',s.running,'freeRunning',s.freeRunning, ..."
    "        'dacAdcLoopback',s.loopback,'newBufferFrames',s.count,'numStreamOverflows',0)};"
    "case 'SetAdcSchedule'"
    "    if s.failSetup, error('DiodeTest:Setup','ADC setup failed'); end"
    "case 'StartAdcSchedule', s.running=true;"
    "case 'StopAdcSchedule', s.running=false;"
    "case 'EnableAdcFreeRunning', s.freeRunning=true;"
    "case 'DisableAdcFreeRunning', s.freeRunning=false;"
    "case 'EnableDacAdcLoopback', s.loopback=true;"
    "case 'DisableDacAdcLoopback', s.loopback=false;"
    "case 'ReadAdcBuffer'"
    "    assert(isequal(varargin,{s.count,-1}));"
    "    t=10+(s.samples+(0:s.count-1))/2000;"
    "    varargout={[18.6 2.5],t,s.underflow,s.overflow}; s.samples=s.samples+s.count;"
    "case {'RegWrRd','RegWr'}"
    "otherwise, error('DiodeTest:Command','Unexpected Datapixx command');"
    "end"
    "COPS_DIODE_TEST=s;"
    "end"]);
writeMock(folder,'GetSecs',[
    "function t=GetSecs"
    "global COPS_DIODE_TEST"
    "COPS_DIODE_TEST.now=COPS_DIODE_TEST.now+0.05; t=COPS_DIODE_TEST.now;"
    "end"]);
writeMock(folder,'WaitSecs',["function WaitSecs(varargin)";"end"]);
addpath(folder,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
clear Datapixx GetSecs WaitSecs
folder=testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)));
rmdir(folder,'s');
clear global COPS_DIODE_TEST
end

function setup(~)
global COPS_DIODE_TEST
COPS_DIODE_TEST=struct('calls',{{}},'open',false,'running',false, ...
    'freeRunning',true,'loopback',false,'count',2,'samples',0,'now',0, ...
    'failStatus',false,'failSetup',false,'underflow',false,'overflow',false);
end

function testDefaultIsPhysicalADC0WithTimed2000HzAcquisition(testCase)
global COPS_DIODE_TEST
data=monitor(testCase);
calls=COPS_DIODE_TEST.calls;
schedule=calls(cellfun(@(c) strcmp(c{1},'SetAdcSchedule'),calls));
verifyEqual(testCase,schedule,{{'SetAdcSchedule',0,2000,400,0,4e6,400}});
verifyEqual(testCase,data.channel,0);
verifyEqual(testCase,data.sampleRate,2000);
verifyGreaterThan(testCase,data.n,0);
verifyEqual(testCase,data.time,data.datapixxTime-data.datapixxTime(1));
verifyEqual(testCase,diff(data.time),0.0005*ones(1,data.n-1),'AbsTol',1e-12);
verifyEqual(testCase,data.voltage(1:2),[-1.4 2.5],'AbsTol',1e-12);
verifyEqual(testCase,data.rawVoltage(1:2),[18.6 2.5]);
verifyReleased(testCase);
verifyTrue(testCase,COPS_DIODE_TEST.freeRunning);
verifyFalse(testCase,COPS_DIODE_TEST.loopback);
end

function testAlternateChannelIsExplicit(testCase)
data=monitor(testCase,channel=6);
verifyEqual(testCase,data.channel,6);
verifyReleased(testCase);
end

function testActiveExperimentIsNotStopped(testCase)
global COPS_DIODE_TEST
COPS_DIODE_TEST.running=true;
verifyError(testCase,@() monitor(testCase),'checkCoPsPhotodiodex:AdcBusy');
verifyTrue(testCase,COPS_DIODE_TEST.running);
names=cellfun(@(c) c{1},COPS_DIODE_TEST.calls,'UniformOutput',false);
verifyFalse(testCase,any(ismember(names,{'StopAdcSchedule','SetAdcSchedule'})));
verifyFalse(testCase,COPS_DIODE_TEST.open);
end

function testStatusFailureClosesConnection(testCase)
global COPS_DIODE_TEST
COPS_DIODE_TEST.failStatus=true;
verifyError(testCase,@() monitor(testCase),'DiodeTest:Status');
verifyFalse(testCase,COPS_DIODE_TEST.open);
end

function testSetupFailureStopsAndRestoresADC(testCase)
global COPS_DIODE_TEST
COPS_DIODE_TEST.failSetup=true;
COPS_DIODE_TEST.loopback=true;
verifyError(testCase,@() monitor(testCase),'DiodeTest:Setup');
verifyReleased(testCase);
verifyTrue(testCase,COPS_DIODE_TEST.freeRunning);
verifyTrue(testCase,COPS_DIODE_TEST.loopback);
end

function testReadErrorsStopADCAndCloseConnection(testCase)
global COPS_DIODE_TEST
COPS_DIODE_TEST.underflow=true;
verifyError(testCase,@() monitor(testCase),'readCoPsAnalogx:Underflow');
verifyReleased(testCase);
end

function testNoSamplesIsReportedAfterReleasingADC(testCase)
global COPS_DIODE_TEST
COPS_DIODE_TEST.count=0;
verifyError(testCase,@() monitor(testCase),'checkCoPsPhotodiodex:NoSamples');
verifyReleased(testCase);
end

function data=monitor(testCase,varargin)
original=pwd; cd(testCase.TestData.folder);
cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
evalc('data=checkCoPsPhotodiodex(0.2,''showPlot'',false,varargin{:});');
end

function verifyReleased(testCase)
global COPS_DIODE_TEST
verifyFalse(testCase,COPS_DIODE_TEST.running);
verifyFalse(testCase,COPS_DIODE_TEST.open);
names=cellfun(@(c) c{1},COPS_DIODE_TEST.calls,'UniformOutput',false);
verifyTrue(testCase,any(strcmp(names,'StopAdcSchedule')));
verifyEqual(testCase,names{end},'Close');
end

function writeMock(folder,name,lines)
fid=fopen(fullfile(folder,[name '.m']),'w');
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end
