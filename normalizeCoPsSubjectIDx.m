function subjectID = normalizeCoPsSubjectIDx(value)
% Make a safe participant ID with a numeric suffix at least three digits wide.
subjectID = sanitizeCoPsFilePrefixx(value);
numberStart = regexp(subjectID, '[0-9]+$', 'start', 'once');
if ~isempty(numberStart)
    numberWidth = numel(subjectID) - numberStart + 1;
    if numberWidth < 3
        subjectID = [subjectID(1:numberStart-1), ...
            repmat('0', 1, 3-numberWidth), subjectID(numberStart:end)];
    end
end
end
