function computerName = getComputerName()
% return the os host name used to select machine-specific setup settings
% preserve domain suffixes because some rig settings match full hostnames.

[status, computerName] = system('hostname');
computerName = strtrim(computerName);

if status ~= 0 || isempty(computerName)
    error('CoPs: computer name unavailable',...
        'Could not determine the computer name using the hostname command');
end
end
