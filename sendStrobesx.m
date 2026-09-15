function sendStrobesx(strobeData)
% Minimal strobe function for testing without hardware dependencies
% This function replaces sendStrobes for testing purposes
%
% Input: strobeData - array of strobe values to send
% Output: None (just logs the strobe data for debugging)

fprintf('Strobe data (minimal version - no hardware): ');
for i = 1:length(strobeData)
    fprintf('%d ', strobeData(i));
end
fprintf('\n');

% No actual hardware calls - just logging for testing
end