function value = convertCoPsPxFieldsToDeg(value, setup)
% convertCoPsPxFieldsToDeg  Convert Px-labelled public output fields to deg.
%
% Numeric table variables or structure fields whose names contain Px/px
% are multiplied by the display degrees-per-pixel factor and renamed with
% Deg/deg. Nested numeric values below a Px-labelled structure field are
% converted as well (for example sessionSummary.mean.trackErrorPx.all).

scale = px2deg(1, setup);
if ~(isscalar(scale) && isfinite(scale) && scale > 0)
    error('convertCoPsPxFieldsToDeg:BadCalibration', ...
        'Could not derive a finite positive degrees-per-pixel factor.');
end
value = localConvert(value, scale, false);
end


function value = localConvert(value, scale, scaleAll)
if istable(value)
    oldNames = value.Properties.VariableNames;
    newNames = oldNames;
    for i = 1:numel(oldNames)
        oldName = oldNames{i};
        labelledPx = localContainsPx(oldName);
        if (scaleAll || labelledPx) && isnumeric(value.(oldName))
            value.(oldName) = value.(oldName) .* scale;
        end
        newNames{i} = localReplacePx(oldName);
    end
    if numel(unique(newNames)) ~= numel(newNames)
        error('convertCoPsPxFieldsToDeg:DuplicateTableNames', ...
            'Converting Px field names would create duplicate table variables.');
    end
    value.Properties.VariableNames = newNames;
    return
end

if isstruct(value)
    oldNames = fieldnames(value);
    for i = 1:numel(oldNames)
        oldName = oldNames{i};
        labelledPx = localContainsPx(oldName);
        converted = cell(size(value));
        for j = 1:numel(value)
            converted{j} = localConvert(value(j).(oldName), scale, ...
                scaleAll || labelledPx);
        end
        newName = localReplacePx(oldName);
        if ~strcmp(newName, oldName)
            if isfield(value, newName)
                error('convertCoPsPxFieldsToDeg:DuplicateStructNames', ...
                    'Converting %s would collide with existing field %s.', ...
                    oldName, newName);
            end
            value = rmfield(value, oldName);
        end
        [value.(newName)] = converted{:};
    end
    return
end

if iscell(value)
    for i = 1:numel(value)
        value{i} = localConvert(value{i}, scale, scaleAll);
    end
    return
end

if isnumeric(value) && scaleAll
    value = value .* scale;
elseif isstring(value)
    for i = 1:numel(value)
        if ~ismissing(value(i))
            value(i) = string(localReplacePx(char(value(i))));
        end
    end
elseif ischar(value)
    value = localReplacePx(value);
end
end


function tf = localContainsPx(name)
tf = contains(name, 'Px') || contains(name, 'px');
end


function name = localReplacePx(name)
token = regexp(name, '^(.*?)(Px|px)(.*)$', 'tokens', 'once');
if isempty(token)
    return
end
if strcmp(token{2}, 'px')
    suffix = 'deg';
else
    suffix = 'Deg';
end
name = [token{1} token{3} suffix];
end
