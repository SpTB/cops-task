function d = safeDeltaField(EC, dIdx, fieldName)
d = 0;
if isfield(EC, 'Delta') && ~isempty(EC.Delta)
    dIdx = min(max(1, dIdx), numel(EC.Delta));
    if isfield(EC.Delta, fieldName)
        tmp = EC.Delta(dIdx).(fieldName);
        if ~isempty(tmp) && isfinite(tmp)
            d = tmp;
        end
    end
end
end