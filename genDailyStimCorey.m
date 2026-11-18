function output = genDailyStimCorey(varargin)
% Generate CoPs texture banks from face/object source PNGs.
%   opts.source_root = 'path/to/source_images';
%   opts.sessions = 1;
%   output = genDailyStimCorey('', 'both', 5, opts);
%
% Source folders: faces_scrambled_raw and objects_scrambled_raw, containing
% fn_####_sample_##.png images. Source root defaults to COPS_STIM_SOURCE_ROOT
% or this repo's stimulus_sources folder; output defaults to repo/stimuli.
% The historical animal/stimType/selection/opts interface is preserved.
% No external synthesis installation, MEX files, or path changes are needed.
% See docs/stimulus_generation.md for all options and task/movie examples.
output = copsstim.generateCorey(varargin{:});
end
