function sendStrobes(words)

% function sendStrobes(words)
%
% similar to sendStrobe but can send several words 
% send n 15-bit (1-32767) words (1-by-n vector) from datapixx
% ---- see also sendStrobe
%
%
% history
% 08/05/14  hn: wrote it; 
for n = 1:length(words)
    if words(n) < 32768
        Datapixx('SetDoutValues',words(n) );    
        Datapixx('RegWr');
        Datapixx('SetDoutValues',0);
        Datapixx('RegWr');
    else 
        disp(['strobe word' num2str(words(n)) ' exceeds the usable range: 1-32767'])
    end
end
