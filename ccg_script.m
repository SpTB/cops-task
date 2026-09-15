  o = opts;
  o.ccgTimebase = 'sample';
  o.lowpassHz = [];
  o.interpBlinkSec = 0;
  o.demeanMode = 'none';
  o.targetStepTimingMode = 'frame';   % or 'ideal'
  plotCCG(ex, [], o);

