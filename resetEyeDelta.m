function ex = resetEyeDelta(ex)

d = ex.eyeCal.Delta;
ex.eyeCal = rmfield(ex.eyeCal,'Delta');
ex.eyeCal.Delta(1) = d(end);
ex.eyeCal.Delta(1).TrialNo = [];
ex.eyeCal.Delta(1).cnt = 1;
