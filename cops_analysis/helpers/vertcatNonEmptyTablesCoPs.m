function T = vertcatNonEmptyTablesCoPs(tablesIn)
% vertcatNonEmptyTablesCoPs  Vertically concatenate only non-empty tables.

if nargin < 1 || isempty(tablesIn)
    T = table();
    return
end
if ~iscell(tablesIn)
    tablesIn = {tablesIn};
end

keep = false(size(tablesIn));
for i = 1:numel(tablesIn)
    keep(i) = istable(tablesIn{i}) && width(tablesIn{i}) > 0 && height(tablesIn{i}) > 0;
end
tablesIn = tablesIn(keep);
if isempty(tablesIn)
    T = table();
else
    T = vertcat(tablesIn{:});
end
end
