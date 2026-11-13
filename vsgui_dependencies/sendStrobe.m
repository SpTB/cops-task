function sendStrobe(word)

% function sendStrobe(word)
% send a single 15-bit (1-32767) word from datapixx
% ------ see also sendStrobes
%
%
% history
% 07/14/14  hn: wrote it; initially send out up to 5-bit. Extend later
% 08/05/14   hn: I am now also using the first bit (dual use for reward and 
%               strobe words.  We can write words up to 32767


if word < 32768
    Datapixx('SetDoutValues',word );    
    Datapixx('RegWr');
    Datapixx('SetDoutValues',0);
    Datapixx('RegWr');
else 
    disp(['strobe word' num2str(word) ' exceeds the available range: 1-32767'])
end

