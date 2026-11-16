function tests = testCoPsBetweenTrialPausesx
tests = functiontests(localfunctions);
end

function testFixedIntervalAndNoPauseAfterFinalTrial(testCase)
ex = fixture(21, 5, 0);
ex = prepareCoPsPauseSchedulex(ex);
verifyEqual(testCase, find(ex.exp.CoPs.pauseSchedule.afterTrial), [5 10 15 20]);
verifyEqual(testCase, ex.exp.CoPs.pauseSchedule.intervals, [5 5 5 5]);
ex.finish = 20;
ex = prepareCoPsPauseSchedulex(ex);
verifyEqual(testCase, find(ex.exp.CoPs.pauseSchedule.afterTrial), [5 10 15]);
end

function testRandomIntervalsAreUniformlyBoundedAndSaved(testCase)
oldState = rng;
cleanup = onCleanup(@() rng(oldState)); %#ok<NASGU>
rng(17);
ex = prepareCoPsPauseSchedulex(fixture(10000, 5, 1));
schedule = ex.exp.CoPs.pauseSchedule;
verifyEqual(testCase, unique(schedule.intervals), [4 5 6]);
verifyEqual(testCase, diff([0 find(schedule.afterTrial)]), schedule.intervals);
verifyEqual(testCase, schedule.meanTrials, 5);
verifyEqual(testCase, schedule.rangeTrials, 1);
verifyLessThan(testCase, abs(mean(schedule.intervals)-5), 0.1);
verifyFalse(testCase, schedule.afterTrial(end));
end

function testDisabledPausesDoNotConsumeRandomNumbers(testCase)
ex = fixture(30, 5, 1);
ex.exp.CoPs.ctl.advance_trial_with_space = false;
oldState = rng;
ex = prepareCoPsPauseSchedulex(ex);
verifyFalse(testCase, any(ex.exp.CoPs.pauseSchedule.afterTrial));
verifyEqual(testCase, rng, oldState);
end

function testFixedIntervalsDoNotConsumeRandomNumbers(testCase)
oldState = rng;
ex = prepareCoPsPauseSchedulex(fixture(30, 5, 0)); %#ok<NASGU>
verifyEqual(testCase, rng, oldState);
end

function testShortSessionDoesNotForceAnExtraPause(testCase)
ex = prepareCoPsPauseSchedulex(fixture(3, 5, 0));
verifyFalse(testCase, any(ex.exp.CoPs.pauseSchedule.afterTrial));
end

function testRangeCannotIncludeZeroLengthIntervals(testCase)
verifyError(testCase, @() prepareCoPsPauseSchedulex(fixture(30, 5, 5)), ...
    'prepareCoPsPauseSchedulex:InvalidRange');
end

function testDefaultSettingsPreserveEveryTrialCadence(testCase)
evalc('ex = setDefaultsCoPs(struct());');
verifyEqual(testCase, ex.exp.CoPs.ctl.between_trial_pause_mean, 1);
verifyEqual(testCase, ex.exp.CoPs.ctl.between_trial_pause_range, 0);
verifyTrue(testCase, ex.exp.CoPs.rew.points_feedback_on);
end

function ex = fixture(nTrials, average, spread)
ex = struct('finish', nTrials);
ex.exp.CoPs.ctl = struct('advance_trial_with_space', true, ...
    'between_trial_pause_mean', average, 'between_trial_pause_range', spread);
end
