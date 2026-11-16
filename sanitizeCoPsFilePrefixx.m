function prefix = sanitizeCoPsFilePrefixx(value)
% Convert a subject identifier to a single safe filename component.

if isstring(value) && isscalar(value) && ~ismissing(value)
    value = char(value);
elseif ~(ischar(value) && (isrow(value) || isempty(value)))
    error('sanitizeCoPsFilePrefixx:InvalidPrefix', ...
        'Enter a subject identifier as a single string.');
end

prefix = strtrim(value);
% Dots are replaced as well so path-like input cannot retain dot segments.
prefix = regexprep(prefix, '[.<>:"/\\|?*\x00-\x1F\x7F\s]', '_');
if isempty(prefix) || ~any(isstrprop(prefix, 'alphanum'))
    error('sanitizeCoPsFilePrefixx:InvalidPrefix', ...
        'Enter a subject identifier containing at least one letter or digit.');
end
end
