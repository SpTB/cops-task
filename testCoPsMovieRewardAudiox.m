function tests=testCoPsMovieRewardAudiox
tests=functiontests(localfunctions);
end

function testOneBeepPerFiniteCrossingAndSilenceElsewhere(testCase)
rate=8000;
[audio,events]=makeCoPsMovieRewardAudiox([NaN -1 0.25 0.75 1 Inf],1,rate);
verifyEqual(testCase,events,[0.25 0.75]);
verifySize(testCase,audio,[2 8000]);
verifyEqual(testCase,audio(1,:),audio(2,:));
tone=makeCoPsRewardBeepx(rate);
verifyEqual(testCase,audio(:,2001:2240),tone);
verifyEqual(testCase,audio(:,6001:6240),tone);
verifyFalse(testCase,any(audio(:,1:2000),'all'));
verifyFalse(testCase,any(audio(:,2241:6000),'all'));
end

function testBeepAtZeroAndBeepTailKeepRequestedClipLength(testCase)
rate=8000;
[audio,events]=makeCoPsMovieRewardAudiox([0 0.99],1,rate);
tone=makeCoPsRewardBeepx(rate);
verifyEqual(testCase,events,[0 0.99]);
verifySize(testCase,audio,[2 rate]);
verifyEqual(testCase,audio(:,1:240),tone);
verifyEqual(testCase,audio(:,7921:end),tone(:,1:80));
end

function testNearbyCrossingsAreMixedAndClampedRatherThanCoalesced(testCase)
[audio,events]=makeCoPsMovieRewardAudiox(repmat(0.25,1,30),1,8000);
verifyNumElements(testCase,events,30);
verifyLessThanOrEqual(testCase,max(abs(audio(:))),1);
verifyTrue(testCase,any(abs(audio(:))==1));
end

function testSharedCueHasExpectedPitchLengthAndFadedEdges(testCase)
rate=48000; tone=makeCoPsRewardBeepx(rate);
verifySize(testCase,tone,[2 1440]);
verifyEqual(testCase,tone(:,[1 end]),zeros(2,2),'AbsTol',1e-14);
verifyLessThanOrEqual(testCase,max(abs(tone(:))),0.1+eps);
spectrum=abs(fft(tone(1,:)));
[~,peak]=max(spectrum(1:720));
verifyEqual(testCase,(peak-1)*rate/1440,800,'AbsTol',1e-10);
end
