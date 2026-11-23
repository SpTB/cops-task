function val = getfieldOrNaN(S, fieldName)
if isstruct(S) && isfield(S, fieldName)
    val = S.(fieldName);
    if isempty(val)
        val = NaN;
    end
else
    val = NaN;
end
end
