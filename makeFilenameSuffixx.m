function sfx = makeFilenameSuffixx(ex)
% currently NON-FUNCTIONAL (probably)
% function sfx = makeFilenameSuffix(ex)
%
% uses the experiment and stimulus information to create the suffix of the
% file name for the current experiment. It consist of two components,
% a stimulus component (STIM) and a component documenting the experiments that
% were run, where each experiment is separated by 'x':  STIM.EXP1xEXP2xEXP3

% history
% 08/03/14  hn: wrote it
% 2020      updated by ik


stim = [];
if isfield(ex,'stim') && isfield(ex.stim,'type')
    stim = ex.stim.type;
end

% temporary solution: treat CoPs as e5
if isfield(ex.exp, 'CoPs')
    ex.exp.e5 = ex.exp.CoPs
end

if isfield(ex,'exp')
    exp = strings(1,5);
    idx = false(1,length(exp));
    for n = 1:length(exp)
        ename = sprintf('e%d',n);
        if isfield(ex.exp,ename)
            idx(n) = true;
            tag = sprintf('exp%d_type',n);
            hobj = findobj('Tag',tag);
            exp_list = cellstr(get(hobj,'String'));
            
            if ismember(ex.exp.(ename).type,exp_list)
                exp(n) = upper(ex.exp.(ename).type);
                switch ex.exp.(ename).type
                    case 'hdx'
                        exp(n) = 'DX';
                    case 'targOn_delay'
                        exp(n) = 'TOD';
                    case 'x0'
                        exp(n) = 'XPos';
                    case 'y0'
                        exp(n) = 'YPos';
                    case 'x02'
                        exp(n) = 'XPos2';
                    case 'y02'
                        exp(n) = 'YPos2';
                    case 'me'
                        exp(n) = 'M';
                    case 'hdx2'
                        exp(n) = 'DX2';
                    case 'y_OffsetCueAmp'
                        exp(n) = 'YO';
                    case 'fixation'
                        exp(n) = 'fix';
                    case 'ce'
                        exp(n) = 'CE';
                    case 'vdx'
                        exp(n) = 'DY';
                    otherwise
                end
            else
                exp(n) = 'XX';
            end
            
        end
    end
end

exp = exp(idx);

if isfield(ex.stim.vals,'RC') && ~isempty(ex.stim.vals.RC) &&  ex.stim.vals.RC
    exp(end+1) = 'RC';
end
if isfield(ex.stim.vals,'adaptation') && ex.stim.vals.adaptation
    exp(end+1) = 'Adapt';
end

exp = sprintf('%sx',exp);

% remove trailing x
if ~isempty(exp) && strcmp(exp(end),'x')
    exp(end) = [];
end

if isempty(exp)
    sfx = stim;
else
    sfx = [stim, '.', exp];
end
