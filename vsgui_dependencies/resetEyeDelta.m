function ex = resetEyeDelta(ex)

% ex = resetEyeDelta(ex)
%%% if there are several changes of eye position offset (delta x, delta y)
%%% stored from a previous experiment, use only the last one

d = ex.eyeCal.Delta;
ex.eyeCal = rmfield(ex.eyeCal,'Delta');
ex.eyeCal.Delta(1) = d(end);
ex.eyeCal.Delta(1).TrialNo = [];
ex.eyeCal.Delta(1).Time = [];
ex.eyeCal.Delta(1).cnt = 1;