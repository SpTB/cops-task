function [tt, data,ts_of_last_value ] = getDatapixxDin(value);

% function [tt, data,ts_of_last_value ] = getDatapixxDin(value);
%
% 'value': optional input.  If it's given it returns the time stamp of the
% last occurrence of 'value' in 'ts_of_last_value'
% tt     : time stamps of all digital inputs since last call to Datapixx('GetDinStatus');
% data   : digital inputs since last call to Datapixx('GetDinStatus');

ts_of_last_value = [];

Datapixx('RegWrRd');
status = Datapixx('GetDinStatus');
[data tt] = Datapixx('ReadDinLog');
if nargin>0
    idx = find(data==value);
    if ~isempty(idx)
        ts_of_last_value = tt(idx(end));
    end
end
        


