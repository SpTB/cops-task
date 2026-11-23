function anchor=getCoPsBenchClockAnchorx()
% PTB clock calibration uses rand internally; never change a trial's stream.
state=rng;
restore=onCleanup(@() rng(state)); %#ok<NASGU>
[ptb,box,confidence]=PsychDataPixx('GetPreciseTime');
anchor=[ptb box confidence];
end
