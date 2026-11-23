# Stimulus presentation timing

`runTrialTaskCoPsx` schedules each frame from the preceding actual display
refresh timestamp (VBL). The refresh interval comes from
`Screen('GetFlipInterval', window)`. It does not use the old independent
`ttime > lastframet + frametimestep` gate.

The frame is submitted with `Screen('AsyncFlipBegin', ...)`, targeting
`lastVbl + 0.5 * frameInterval`. Eye sampling, fixation checks, reward evaluation,
and keyboard handling continue while that flip is pending. The next frame is
drawn only after `AsyncFlipCheckEnd` reports completion. This keeps behavioral
evaluation independent of display refresh rate. Drawing and other processing
still consume time; a nominal 500 Hz polling interval is not a guaranteed
500 Hz evaluation rate under load.

The target-step increment takes effect after the submitted flip completes.
Trial completion waits for the final stimulus flip. Pause, timeout, abort, and
error cleanup finish any pending flip before blanking or releasing textures.

Each trial saves `displayRefreshIntervalSec`, all four actual flip outputs in
`flip_info`, and the corresponding `frameState` and `frameStep`. A late frame
remains visible for additional refreshes; its timing is retained in these logs.
For example, inspect consecutive GO frames in a rig E recording:

```matlab
tr = ex.Trials(i);
active = tr.frameState == tr.frameStateLookup.GO;
dt = diff(tr.flip_info(:,1));
dt = dt(active(1:end-1) & active(2:end) & isfinite(dt));
ifi = tr.displayRefreshIntervalSec;
missedRefreshes = sum(max(0, round(dt / ifi) - 1));
```

Run `runtests('testCoPsFrameTimingx.m')` for hardware-free regression coverage.
The simulated display checks 60/120 Hz cadence, recovery after drawing overload,
behavioral polling, and pending-flip handling on exit. Actual timing on the
rig E DataPixx/Cumming3D configuration needs validation with saved flip logs and,
where available, an optical recording.
