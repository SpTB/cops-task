function stopCoPsBenchOutputx()
% Always return the reward output to low, including on errors and Ctrl+C.
try
    Datapixx('SetDoutValues', 0);
    Datapixx('RegWr');
catch
end
end
