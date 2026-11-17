function tests = testCoPsTrialCalibrationx
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.originalPath=path;
addpath(fullfile(fileparts(mfilename('fullpath')),'cops_analysis','helpers'));
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testAnalogReconstructionUsesThatTrialsFit(testCase)
ex=struct('fix',struct('PCtr',[960 540]),'setup',struct('adc',struct('Rate',500)));
ex.eyeCal=makeCoPsMouseEyeCalx(); ex.eyeCal.RXGain=100;
T=struct('TrialStart',50,'Eye',struct('n',2,'v',[2 3;4 5;1 1]));
T.eyeCal=makeCoPsMouseEyeCalx();
T.eyeCal.RXGain=2; T.eyeCal.RYGain=3; T.eyeCal.RX0=1;
T.eyeCal.Delta.RX0=0.5;
[x,y]=reconstructEyePx(ex,T,false);
verifyEqual(testCase,x,[961;963]);
verifyEqual(testCase,y,[552;555]);
end

function testNativeReconstructionUsesThatTrialsCorrection(testCase)
ex=struct();
ex.eyeCal=makeCoPsMouseEyeCalx();
ex.eyeCal.correction=struct('enabled',true,'offsetPx',[0 0;0 0], ...
    'gain',[100 100;100 100],'centerPx',[0 0]);
T=struct('TrialStart',50);
T.Eye=struct('n',2,'v',[10 11;20 21;30 30;NaN NaN;NaN NaN;NaN NaN], ...
    'source','eyelink','ptbStart',50,'trackerStart',10,'t',[10 10.002]);
T.eyeCal=makeCoPsMouseEyeCalx();
T.eyeCal.correction=struct('enabled',true,'offsetPx',[1 2;0 0], ...
    'gain',[2 3;1 1],'centerPx',[100 200]);
[x,y]=reconstructEyePx(ex,T,false);
verifyEqual(testCase,x,[118;120]);
verifyEqual(testCase,y,[254;257]);
T.eyeCal=rmfield(T.eyeCal,'correction'); % later fit must not affect raw early gaze
[x,y]=reconstructEyePx(ex,T,false);
verifyEqual(testCase,x,[10;11]);
verifyEqual(testCase,y,[20;21]);
end

function testLegacyFileStillUsesSessionCalibration(testCase)
ex=struct('fix',struct('PCtr',[960 540]),'setup',struct('adc',struct('Rate',500)));
ex.eyeCal=makeCoPsMouseEyeCalx(); ex.eyeCal.RXGain=2;
T=struct('TrialStart',50,'Eye',struct('n',2,'v',[2 3;4 5;1 1]));
[x,y]=reconstructEyePx(ex,T,false);
verifyEqual(testCase,x,[964;966]);
verifyEqual(testCase,y,[544;545]);
end
