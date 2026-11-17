function tests = testCoPsPayoutx
tests=functiontests(localfunctions);
end

function testDefaultMoneySettingsHaveOneSource(testCase)
evalc('ex=setDefaultsCoPs(struct());');
verifyEqual(testCase,ex.exp.CoPs.pay,resolveCoPsPayx());
verifyFalse(testCase,isfield(ex.exp.CoPs,'ins'));
end

function testMinimumMidpointMaximumAndCap(testCase)
for transform={'linear','logit'}
    pay=resolveCoPsPayx(struct('transform',transform{1}));
    for pair=[0 0;2 0;3 0;14 12.5;25 25;40 25]'
        p=calculateCoPsPayoutx(trialsWithPoints(pair(1)),pay);
        verifyEqual(testCase,p.bonusDollars,pair(2));
    end
end
end

function testPracticeAndExplicitlyUnpaidTrialsAreExcluded(testCase)
t=trialsWithPoints([200 200 14 14 100]);
t(1).isInstructionTutorial=true;
t(2).isInstructionTutorial=true;
t(5).pointsCountTowardTotal=false;
p=calculateCoPsPayoutx(t,resolveCoPsPayx());
verifyEqual(testCase,p.trialMask,[false false true true false]);
verifyEqual(testCase,[p.totalPoints p.nTrials p.averagePointsPerTrial p.bonusDollars],[28 2 14 12.5]);
end

function testZeroPointTrialsCountAndFractionalEvidenceDoesNot(testCase)
t=trialsWithPoints([0 20]);
t(1).pointsEarned=100.9; t(2).pointsEarned=200.9;
p=calculateCoPsPayoutx(t,resolveCoPsPayx());
verifyEqual(testCase,[p.totalPoints p.nTrials p.averagePointsPerTrial p.bonusDollars],[20 2 10 7.95]);
end

function testEmptyAndPracticeOnlyRunsEarnZero(testCase)
pay=resolveCoPsPayx();
p=calculateCoPsPayoutx(struct([]),pay);
verifyEqual(testCase,[p.nTrials p.totalPoints p.bonusDollars],[0 0 0]);
t=trialsWithPoints(100); t.isInstructionTutorial=true;
p=calculateCoPsPayoutx(t,pay);
verifyEqual(testCase,[p.nTrials p.totalPoints p.bonusDollars],[0 0 0]);
end

function testBothCurvesAreMonotoneBoundedAndReachCapOnlyAtThreshold(testCase)
for transform={'linear','logit'}
    pay=resolveCoPsPayx(struct('transform',transform{1}));
    averages=0:0.5:30; bonuses=zeros(size(averages));
    for k=1:numel(averages)
        t=trialsWithPoints([floor(averages(k)) ceil(averages(k))]);
        p=calculateCoPsPayoutx(t,pay);
        bonuses(k)=p.bonusDollars;
    end
    verifyGreaterThanOrEqual(testCase,diff(bonuses),zeros(1,numel(bonuses)-1));
    verifyEqual(testCase,bonuses(averages<=3),zeros(1,nnz(averages<=3)));
    verifyEqual(testCase,bonuses(averages>=25),25*ones(1,nnz(averages>=25)));
    verifyLessThan(testCase,bonuses(averages<25),25);
end
end

function testSigmoidHasTheRequestedSShape(testCase)
pay=resolveCoPsPayx(struct('transform','logit'));
low=calculateCoPsPayoutx(trialsWithPoints([8 9]),pay);
high=calculateCoPsPayoutx(trialsWithPoints([19 20]),pay);
verifyEqual(testCase,low.bonusDollars,1.75);
verifyEqual(testCase,high.bonusDollars,23.24);
verifyEqual(testCase,low.bonusDollarsUnrounded+high.bonusDollarsUnrounded,25,'AbsTol',1e-12);
end

function testNearMaximumCannotRoundUpToMaximumCash(testCase)
t=trialsWithPoints([24 25*ones(1,99)]); % average 24.99
for slope=[1e-12 10 1e6]
    pay=resolveCoPsPayx(struct('transform','logit','logitSlope',slope));
    p=calculateCoPsPayoutx(t,pay);
    verifyTrue(testCase,isfinite(p.bonusDollars));
    verifyLessThan(testCase,p.bonusDollars,25);
end
end

function testCustomMoneySettingsAndValidation(testCase)
pay=resolveCoPsPayx(struct('minPointsPerTrial',2,'maxPointsPerTrial',10,'max_bonus_dollar',12.5));
p=calculateCoPsPayoutx(trialsWithPoints(6),pay);
verifyEqual(testCase,p.bonusDollars,6.25);
verifyError(testCase,@() resolveCoPsPayx(struct('minPointsPerTrial',5,'maxPointsPerTrial',5)), ...
    'resolveCoPsPayx:InvalidThresholds');
verifyError(testCase,@() resolveCoPsPayx(struct('max_bonus_dollar',1.001)), ...
    'resolveCoPsPayx:InvalidCurrencyPrecision');
verifyError(testCase,@() getCoPsEarnedPointsx(struct('pointsEarned',10)), ...
    'getCoPsEarnedPointsx:MissingRewardEvents');
end

function trials=trialsWithPoints(counts)
trials=repmat(struct('times',struct('reward',[]),'isInstructionTutorial',false, ...
    'pointsCountTowardTotal',true),1,numel(counts));
for k=1:numel(counts), trials(k).times.reward=1:counts(k); end
end
