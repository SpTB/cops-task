function info = getCoPsTrialBlockInfox(ex)
% Describe CoPs trial block counts and indices.

mainN = localNonnegativeRound(localNestedNumeric(ex, {'exp', 'nreps'}, 0));
tutN = localNonnegativeRound(localNestedNumeric(ex, {'exp', 'CoPs', 'tut', 'nreps'}, 0));
purN = localNonnegativeRound(localNestedNumeric(ex, {'exp', 'CoPs', 'pur', 'nreps'}, 0));
preN = localNonnegativeRound(getCoPsPreTrialCountx(ex));
purPriority = localNestedLogical(ex, {'exp', 'CoPs', 'pur', 'priority'}, true);

info = struct();
info.mainN = mainN;
info.tutN = tutN;
info.purN = purN;
info.preN = preN;
info.purPriority = purPriority;
info.totalN = mainN + tutN + purN + preN;

cursor = 1;
info.tutorialIdx = cursor:(cursor + tutN - 1);
cursor = cursor + tutN;

if purPriority
    info.pursuitIdx = cursor:(cursor + purN - 1);
    cursor = cursor + purN;
    info.preIdx = cursor:(cursor + preN - 1);
    cursor = cursor + preN;
    info.mainIdx = cursor:(cursor + mainN - 1);
else
    info.preIdx = cursor:(cursor + preN - 1);
    cursor = cursor + preN;
    info.mainIdx = cursor:(cursor + mainN - 1);
    cursor = cursor + mainN;
    info.pursuitIdx = cursor:(cursor + purN - 1);
end

info.tutorialIdx = localEmptyIfNone(info.tutorialIdx);
info.pursuitIdx = localEmptyIfNone(info.pursuitIdx);
info.preIdx = localEmptyIfNone(info.preIdx);
info.mainIdx = localEmptyIfNone(info.mainIdx);
end


function idx = localEmptyIfNone(idx)
if isempty(idx) || idx(1) > idx(end)
    idx = [];
end
end


function value = localNonnegativeRound(value)
value = round(double(value));
if ~isfinite(value) || value < 0
    value = 0;
end
end


function value = localNestedNumeric(s, path, defaultValue)
value = defaultValue;
node = s;
for i = 1:numel(path)
    key = path{i};
    if isstruct(node) && isfield(node, key)
        node = node.(key);
    else
        return
    end
end
if (isnumeric(node) || islogical(node)) && isscalar(node)
    value = double(node);
end
end


function value = localNestedLogical(s, path, defaultValue)
value = defaultValue;
node = s;
for i = 1:numel(path)
    key = path{i};
    if isstruct(node) && isfield(node, key)
        node = node.(key);
    else
        return
    end
end
if islogical(node) || isnumeric(node)
    value = logical(node(1));
elseif ischar(node) || isstring(node)
    text = strtrim(char(string(node)));
    value = any(strcmpi(text, {'true', '1', 'yes', 'on'}));
end
end
