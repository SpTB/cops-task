function [ex,stim]=makeStimulusx(ex)
% xx NON-FUNCTIONAL FOR NOW!
% changes stimulus parameters according to the experimental sequence
% then distributes make** commands according to the stimulus
%
% history
%           hn: wrote it
% 07/03/14  hn: stimulus parameters are now updated here if an experiment
%           is run
% 07/11/14  hn: -included field 'setup' and moved setup parameters into it
%               new parameter name          old parameter name
%               ex.setup.stereo             ex.stereo
%               ex.setup.window             ex.window
%               ex.setup.overlay            ex.overlay
% 07/28/14  hn: included option to run a bar stimulus
% 12/13/14  hn: included option for spatial attention (second RDS); set
%               tracking of second stimulus
%           hn  included flashCue
% 11/01/15  hn: included disparity assignment for cuedUncuedAntiCorrelated
% 11/03/15  hn: AC moved to makeSequence.m
% 12/09/16  hn: included two-pass of random sequence
% 06/16/17  hn: updated two-pass procedure
% 08/06/17  hn: allow for different x & y positions for SA task
% 07/04/22  hn: allow for blocked free viewing/fixation trials
% 11/15/22  hn: allow for free viewing/fixation to change trial-by-trial
% 04/04/23  hn: call makeRDS (independent R/L dots)
% 11/05/24  ik: added 'orNoise' to ex.stim.type

stim=[];

idx = ex.j;
%pass2_flag = 0; % do we have pass2?

% % check whether we run a two-pass experiment
% if isfield(ex.exp,'two_pass') && ex.exp.two_pass
%     if ex.j>ex.stim.nseq
%         % we have finished the first pass for the stimuli
%         % now set the rngstate to that of the relevant first pass
%         rng(ex.stim.rng(ex.stim.idx_2pass(ex.j-ex.stim.nseq)).setting);
%         pass2_flag = 1;
%     else
%         % store the rng settings for the stimulus for repeatability
%         ex.stim.rng(ex.j).setting = rng;
%     end
% end


% check whether we run a two-pass experiment
if isfield(ex.exp,'two_pass')
    currRngState = rng;
    switch ex.exp.two_pass
        case 1
            % set seed
            rng(ex.stim.seedSeq(idx));
            % store the rng settings for the stimulus for repeatability
            ex.stim.rng(ex.j).setting = rng;
        case 2
            
            if mod(ex.goodtrial,ex.stim.fixedSeedEveryN)==0
                rng(ex.stim.seedSeq(1)); % we only have one state that we use
                % repeatedly
                ex.stim.rng(ex.j).setting = rng;
            end
        otherwise
    end
end


% % check whether we are running an experiment and change
% %  stimulus parameters accordingly
% pars = [];
% if pass2_flag && isfield(ex.stim,'seq2pass')
%     pars = fieldnames(ex.stim.seq2pass);
% elseif isfield(ex.stim,'seq')
%     pars = fieldnames(ex.stim.seq);
% end

% check whether we are running an experiment and change
%  stimulus parameters accordingly
pars = [];
if  isfield(ex.stim,'seq')
    pars = fieldnames(ex.stim.seq);
end

par_str=[];
if ~(isfield(ex.exp,'scmap') && ismember(ex.exp.scmap,[1,2]))
    for n = 1:length(pars)
        val = eval(['ex.stim.seq.' pars{n} '(ex.j);']);
        eval(['ex.stim.vals.' pars{n} '= val;']);
        eval(['ex.Trials(ex.j).' pars{n} '=val;']);
        par_str = [par_str ([pars{n} ': ' num2str(val) '  '])];
    end
end

if ex.exp.spatialAttention
    ex.stim.vals.flashCue = 0;
    if ~ex.exp.flashCue % our old way of giving instruction trials
        if  mod(ex.goodtrial,ex.exp.nTrialsInBlock)>= ex.exp.nInstructionTrials && ...
                ~ex.exp.addInstructionTrials
            % if we don't add additional instruction trials
            ex.stim.vals.rds2 = 1;
            ex.Trials(ex.j).instructionTrial = 0;
        else
            % make sure instruction trials are easy
            if ex.stim.vals.Dc<0.25
                ex.stim.vals.Dc = 0.5;
                ex.Trials(ex.j).Dc =0.5;
                par_str = [par_str ' Dc: 0.5'];
            end
            ex.stim.vals.rds2 = 0;
            ex.Trials(ex.j).Dc2 = NaN;
            ex.Trials(ex.j).hdx2 = NaN;
            ex.Trials(ex.j).hdx_seq2 = NaN;
            ex.Trials(ex.j).instructionTrial = 1;
        end
    else
        if  mod(ex.goodtrial,ex.exp.nTrialsInBlock)>= ex.exp.nInstructionTrials
            ex.Trials(ex.j).instructionTrial = 0;
        else ex.Trials(ex.j).instructionTrial = 1;
            ex.stim.vals.flashCue = 1;
            % make sure instruction trials are easy
            if ex.stim.vals.Dc<0.25
                ex.stim.vals.Dc = 0.5;
                ex.Trials(ex.j).Dc =0.5;
            end
        end
        ex.stim.vals.rds2 = 1;
    end
    % once a block is completed switch sides of cued/uncue stimulus
    if ex.goodtrial>=ex.exp.nTrialsInBlock && mod(ex.goodtrial,ex.exp.nTrialsInBlock)==0 && ...
            ex.changedBlock ==0
        % if we have different x & y positions for each side, take these
        if isfield(ex.stim.vals,'x02') &(~isfield(ex.exp,'att_training')||ex.exp.att_training==0)
            x0 = ex.stim.vals.x0;
            ex.stim.vals.x0 = ex.stim.vals.x02 ;
            ex.stim.vals.x02 = x0;
        elseif isfield(ex.stim.vals,'x02') && ex.exp.att_training
            ex.stim.vals.x0 = -sign(ex.stim.vals.x0)*min(abs([ex.stim.vals.x02,ex.stim.vals.x0]));
            ex.stim.vals.x02 = -sign(ex.stim.vals.x02)*max(abs([ex.stim.vals.x02,ex.stim.vals.x0]));
        else
            ex.stim.vals.x02 = ex.stim.vals.x0;
            ex.stim.vals.x0 = -ex.stim.vals.x0;
        end
        if isfield(ex.stim.vals,'y02')
            y0 = ex.stim.vals.y0;
            ex.stim.vals.y0 = ex.stim.vals.y02;
            ex.stim.vals.y02 = y0;
        end
        
        ex.changedBlock =1;
    end
    % store the information of where the cued stimulus is
    ex.Trials(ex.j).x0 = ex.stim.vals.x0;
    
else
    %ex.stim.vals.rds2 =0; % we now allow for 2 stimuli in the normal
    %experiment and don't want this to be overwritten. check that it still
    %works for the attention task
    ex.stim.vals.flashCue = 0;
end
disp(par_str)

% new insertion on 07/04/22
if isfield(ex.exp,'blockedFreeViewing') && ex.exp.blockedFreeViewing
    
    fprintf('ex.goodtrial = %d\n\n',ex.goodtrial)
    
    if ex.goodtrial>=ex.exp.nTrialsInBlock && ...
            mod(ex.goodtrial,ex.exp.nTrialsInBlock) ==0 && ex.changedBlock ==0
        
        % toggle freeViewing (how we control free viewing)
        ex.freeViewing = rem(ex.freeViewing+1,3);
        %{
        if ex.freeViewing
            ex.freeViewing = false;
        else
            ex.freeViewing = true;
        end
        %}
        
        ex.changedBlock = 1;
    end
end

% new on 11/15/22  if we run free-viewing in interleaved trials
if isfield(ex,'Trials') && length(ex.Trials) >= ex.j && ...
        isfield(ex.Trials(ex.j),'freeViewing') && ...
        ~isempty(ex.Trials(ex.j).freeViewing)
    ex.Trials(ex.j).freeViewing
    if ex.Trials(ex.j).freeViewing == true
        ex.freeViewing = true ;
    else
        ex.freeViewing = false;
    end
    ex.freeViewing
end


%disp(['freeviewing: ' num2str(ex.freeViewing)])

% distribute make** command according to the stimulus type
switch ex.stim.type
    case 'grating'
        if ~isfield(ex.stim.vals,'phase')
            ex.stim.vals.phase = 1;
        end
        ex = makeGratingRC(ex);
    case 'rds'
        
        %[ex,stim] = makeRDS_old(ex); % 04/04/23 for backwards
        %compatibility
        [ex,stim] = makeRDS(ex); % 04/04/23 independent R/L RDSs
    case 'bar'
        if ~isfield(ex.stim.vals,'flickerTF')
            ex.stim.vals.flickerTF = 0;
        end
        ex.stim.vals.RC = 0;
    case 'fullfield'
        ex = makeFullField(ex);
    case 'image'
        ex = makeImage(ex);
    case 'orNoise'
        ex = makeORnoise(ex);
    case 'gabor'
        ex = makeGabor(ex);
    otherwise
        
end

% set screen to background
if ex.setup.stereo.Display
    Screen('SelectStereoDrawBuffer', ex.setup.window, 0);
    Screen('FillRect', ex.setup.window, ex.idx.bg_lum);
    
    Screen('SelectStereoDrawBuffer', ex.setup.window, 1);
    Screen('FillRect', ex.setup.window, ex.idx.bg_lum);
    Screen('Flip', ex.setup.window);
else
    Screen('FillRect', ex.setup.window, ex.idx.bg_lum);
    Screen('Flip', ex.setup.window);
end

% reset rng state to what it was before we generated the stimulus
if isfield(ex.exp,'two_pass')
    rng(currRngState);
end

% xx added CoPs here
if isfield(ex.exp, 'CoPs')
    
    % Unpack CoPs parameters
    dirs = ex.exp.CoPs.dirs;
    graph = ex.exp.CoPs.graph;
    ctl = ex.exp.CoPs.ctl;
    posT = ex.Trials(ex.j).posT;
    
    [stimTextures, targPositions] = makeStimulusCoPsx(ex.setup, ctl, dirs, posT, graph);
    stim = [stimTextures, targPositions];
end


