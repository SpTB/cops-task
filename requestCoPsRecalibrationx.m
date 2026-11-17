function ex = requestCoPsRecalibrationx(ex,nextTrial,source)
% Queue work for runEx, after completed trial data have been checkpointed.
ex.Recalibration.pending = struct('requestedAt',GetSecs, ...
    'nextTrial',nextTrial,'source',source);
fprintf('F6: calibration + validation requested before trial %d.\n',nextTrial);
end
