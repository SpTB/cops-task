function tests = testCoPsPointsx
tests = functiontests(localfunctions);
end

function testScoresEvidenceAndAccumlatesAcrossTrials(testCase)
ex = struct('j', 1);
ex = finalizeCoPsPointsx(ex, [2 NaN -3 Inf 4], 2, true, true);
verifyEqual(testCase, ex.Trials(1).rawPointsEvidence, 6);
verifyEqual(testCase, ex.Trials(1).pointsTrace, [1 1 1 1 3]);
verifyEqual(testCase, ex.Trials(1).pointsEarned, 3);
verifyEqual(testCase, ex.totalPoints, 3);
ex.j = 2;
ex = finalizeCoPsPointsx(ex, [1 2], 2, true, true);
verifyEqual(testCase, ex.Trials(2).pointsEarned, 1.5);
verifyEqual(testCase, ex.Trials(2).totalPoints, 4.5);
verifyEqual(testCase, ex.Trials(1).totalPoints, 3);
end

function testInterruptedTrialPreservesTotalAndEvidence(testCase)
ex = struct('j', 1, 'totalPoints', 7);
ex = finalizeCoPsPointsx(ex, [2 4], 2, false, false);
verifyEqual(testCase, ex.totalPoints, 7);
verifyEqual(testCase, ex.Trials(1).pointsEarned, 0);
verifyEqual(testCase, ex.Trials(1).rawPointsEvidence, 6);
verifyEqual(testCase, ex.Trials(1).trialScored);
verifyEqual(testCase, ex.Trials(1).trialCompleted);
end

function testScoredFailureRetainsExistingPartialCreditPolicy(testCase)
ex = finalizeCoPsPointsx(struct('j', 1), [2 4], 2, false, false);
verifyEqual(testCase, ex.totalPoints, 3);
verifyFalse(testCase,ex.trials(1).trialCompleted);
verifyTrue(testCase, ex.Trials(1`).trialScored);
end

function testEmptyEvidenceAndMissingSessionTotal(testCase)
ex = finalizeCoPsPointsx(struct('j', 1), [], 2, true, true);
verifyEqual(testCase, ex.Trials(1).pointsEarned, 0);
verifyEqual(testCase, ex.totalPoints, 0);
verifyEmpty(testCase, ex.Trials(1).pointsTrace);
end
